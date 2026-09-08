#include "m3u8_converter_native.h"

#include <cstdlib>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <exception>
#include <new>
#include <string>
#include <thread>

#include <hilog/log.h>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"

#undef LOG_TAG
#define LOG_TAG "M3u8ConverterNative"

namespace {

struct ConverterUpdate {
    double progress;
    bool finished;
    bool success;
    int errorCode;
    std::string message;
    std::string outputPath;
};

static void CallConverterCallback(napi_env env, napi_value jsCallback, void *context, void *data)
{
    auto *update = static_cast<ConverterUpdate *>(data);
    if (env == nullptr || jsCallback == nullptr || update == nullptr) {
        delete update;
        return;
    }

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_value object;
    napi_create_object(env, &object);

    napi_value progress;
    napi_create_double(env, update->progress, &progress);
    napi_set_named_property(env, object, "progress", progress);

    napi_value finished;
    napi_get_boolean(env, update->finished, &finished);
    napi_set_named_property(env, object, "finished", finished);

    napi_value success;
    napi_get_boolean(env, update->success, &success);
    napi_set_named_property(env, object, "success", success);

    napi_value errorCode;
    napi_create_int32(env, update->errorCode, &errorCode);
    napi_set_named_property(env, object, "errorCode", errorCode);

    napi_value message;
    napi_create_string_utf8(env, update->message.c_str(), NAPI_AUTO_LENGTH, &message);
    napi_set_named_property(env, object, "message", message);

    napi_value outputPath;
    napi_create_string_utf8(env, update->outputPath.c_str(), NAPI_AUTO_LENGTH, &outputPath);
    napi_set_named_property(env, object, "outputPath", outputPath);

    napi_call_function(env, undefined, jsCallback, 1, &object, nullptr);
    delete update;
}

static void EmitUpdate(napi_threadsafe_function callback, double progress, bool finished, bool success,
                       int errorCode, const std::string &message, const std::string &outputPath)
{
    auto *update = new (std::nothrow) ConverterUpdate{
        progress, finished, success, errorCode, message, outputPath
    };
    if (update == nullptr) {
        return;
    }

    if (napi_acquire_threadsafe_function(callback) != napi_ok) {
        delete update;
        return;
    }
    const napi_status status = napi_call_threadsafe_function(callback, update, napi_tsfn_blocking);
    napi_release_threadsafe_function(callback, napi_tsfn_release);
    if (status != napi_ok) {
        delete update;
    }
}

static std::string ReadProperty(int64_t contextId, const char *name)
{
    char *value = mpv_wrapper_get_property_string(contextId, name);
    if (value == nullptr) {
        return std::string();
    }
    std::string result(value);
    mpv_free(value);
    return result;
}

static double ParseDouble(const std::string &value)
{
    if (value.empty()) {
        return 0.0;
    }
    char *end = nullptr;
    const double result = std::strtod(value.c_str(), &end);
    return end != value.c_str() && result >= 0.0 ? result : 0.0;
}

static int SetOption(int64_t contextId, const char *name, const char *value)
{
    return mpv_wrapper_set_property_string(contextId, name, value);
}

static void ConvertOnWorkerBody(const std::string source, const std::string output,
                                napi_threadsafe_function callback)
{
    int64_t contextId = -1;
    bool success = false;
    bool recorderFailed = false;
    int errorCode = 0;
    std::string errorMessage;
    // mpv's stream recorder chooses the muxer from the file extension. Keep
    // .mp4 as the temporary file's final suffix, then publish it atomically.
    const std::string partialOutput = output + ".part.mp4";

    // A partially written MP4 must never be visible to folder scanning or
    // the thumbnail extractor. Publish it only after the muxer is closed.
    std::remove(partialOutput.c_str());

    contextId = mpv_wrapper_create();
    if (contextId < 0) {
        errorCode = contextId;
        errorMessage = "创建转换内核失败";
        OH_LOG_ERROR(LOG_APP, "create converter context failed: %{public}d", errorCode);
    }

    if (contextId >= 0) {
        const int optionErrors[] = {
            // Match Kazumi's HLS download path: copy compressed packets into
            // MP4 instead of decoding and re-encoding through h264_ohcodec.
            // This preserves codec configuration, keyframes and timestamps
            // needed by HarmonyOS's system thumbnail extractor.
            SetOption(contextId, "stream-record", partialOutput.c_str()),
            SetOption(contextId, "vo", "null"),
            SetOption(contextId, "ao", "null"),
            SetOption(contextId, "idle", "yes"),
            SetOption(contextId, "speed", "100"),
            SetOption(contextId, "keep-open", "no"),
            SetOption(contextId, "terminal", "no"),
            SetOption(contextId, "demuxer-lavf-o", "hls_ad_filter=1,seg_allow_img=1")
        };
        const char *optionNames[] = {
            "stream-record", "vo", "ao", "idle", "speed", "keep-open",
            "terminal", "demuxer-lavf-o"
        };
        for (size_t i = 0; i < sizeof(optionErrors) / sizeof(optionErrors[0]); i++) {
            const int optionError = optionErrors[i];
            if (optionError < 0) {
                errorCode = optionError;
                errorMessage = std::string("转换参数失败: ") + optionNames[i];
                OH_LOG_ERROR(LOG_APP, "set converter option failed: %{public}s=%{public}d",
                             optionNames[i], optionError);
                break;
            }
        }
    }

    if (contextId >= 0 && errorMessage.empty()) {
        const int initializeError = mpv_wrapper_initialize(contextId);
        if (initializeError < 0) {
            errorCode = initializeError;
            errorMessage = "初始化转换内核失败";
            OH_LOG_ERROR(LOG_APP, "initialize converter failed: %{public}d", errorCode);
        }
    }

    if (contextId >= 0 && errorMessage.empty()) {
        mpv_wrapper_request_log_messages(contextId, "warn");
        const char *loadArgs[] = {"loadfile", source.c_str(), "replace", nullptr};
        const int loadError = mpv_wrapper_command(contextId, loadArgs);
        if (loadError < 0) {
            errorCode = loadError;
            errorMessage = "无法打开 m3u8 源";
            OH_LOG_ERROR(LOG_APP, "load m3u8 source failed: %{public}d", errorCode);
        } else {
            OH_LOG_INFO(LOG_APP, "converter source loaded: %{public}s", source.c_str());
        }
    }

    if (contextId >= 0 && errorMessage.empty()) {
        bool ended = false;
        double lastProgress = -1.0;
        while (!ended) {
            mpv_event *event = mpv_wrapper_wait_event(contextId, 0.25);
            if (event != nullptr && event->event_id == MPV_EVENT_END_FILE) {
                auto *endFile = static_cast<mpv_event_end_file *>(event->data);
                const int reason = endFile == nullptr ? MPV_END_FILE_REASON_ERROR : endFile->reason;
                errorCode = endFile == nullptr ? MPV_ERROR_GENERIC : endFile->error;
                ended = true;
                if (reason == MPV_END_FILE_REASON_EOF && errorCode == 0 && !recorderFailed) {
                    success = true;
                } else {
                    if (recorderFailed && errorCode == 0) {
                        errorCode = MPV_ERROR_GENERIC;
                    }
                    if (errorMessage.empty()) {
                        errorMessage = recorderFailed ? "MP4 转封装写入失败" :
                            "m3u8 转换失败，请检查源文件";
                    }
                    OH_LOG_ERROR(LOG_APP, "converter ended with failure: reason=%{public}d error=%{public}d message=%{public}s",
                                 static_cast<int>(reason), errorCode, errorMessage.c_str());
                }
            } else if (event != nullptr && event->event_id == MPV_EVENT_LOG_MESSAGE) {
                auto *log = static_cast<mpv_event_log_message *>(event->data);
                if (log != nullptr && log->level != nullptr &&
                    (std::strcmp(log->level, "error") == 0 || std::strcmp(log->level, "fatal") == 0) &&
                    log->text != nullptr) {
                    errorMessage = log->text;
                    if (log->prefix != nullptr && std::strcmp(log->prefix, "recorder") == 0) {
                        recorderFailed = true;
                        errorCode = MPV_ERROR_GENERIC;
                    }
                }
            }

            const double duration = ParseDouble(ReadProperty(contextId, "duration"));
            const double position = ParseDouble(ReadProperty(contextId, "time-pos"));
            double progress = duration > 0.0 ? position / duration : 0.0;
            if (progress < 0.0) progress = 0.0;
            if (progress > 0.99 && !ended) progress = 0.99;
            if (progress - lastProgress >= 0.01 || (ended && progress != lastProgress)) {
                lastProgress = progress;
                EmitUpdate(callback, progress, false, false, 0, "正在转换", output);
            }
        }
    }

    if (contextId >= 0) {
        mpv_wrapper_destroy(contextId);
    }
    if (success && std::rename(partialOutput.c_str(), output.c_str()) != 0) {
        const int renameError = errno;
        success = false;
        errorCode = renameError == 0 ? MPV_ERROR_GENERIC : -renameError;
        errorMessage = "无法发布转换后的 MP4 文件";
        OH_LOG_ERROR(LOG_APP, "publish converted mp4 failed: errno=%{public}d output=%{public}s",
                     renameError, output.c_str());
    }
    if (!success) {
        std::remove(partialOutput.c_str());
        if (errorMessage.empty()) {
            errorMessage = "转换失败";
        }
        OH_LOG_ERROR(LOG_APP, "m3u8 conversion failed: code=%{public}d message=%{public}s",
                     errorCode, errorMessage.c_str());
    } else {
        OH_LOG_INFO(LOG_APP, "m3u8 conversion completed: %{public}s", output.c_str());
    }
    EmitUpdate(callback, success ? 1.0 : 0.0, true, success, errorCode,
               success ? "转换完成" : errorMessage, success ? output : std::string());
}

static void ConvertOnWorker(const std::string source, const std::string output,
                            napi_threadsafe_function callback)
{
    try {
        ConvertOnWorkerBody(source, output, callback);
    } catch (const std::exception &exception) {
        OH_LOG_ERROR(LOG_APP, "converter worker exception: %{public}s", exception.what());
        EmitUpdate(callback, 0.0, true, false, MPV_ERROR_GENERIC, "转换线程异常", output);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "converter worker unknown exception");
        EmitUpdate(callback, 0.0, true, false, MPV_ERROR_GENERIC, "转换线程异常", output);
    }
    // Release the initial reference created by napi_create_threadsafe_function.
    napi_release_threadsafe_function(callback, napi_tsfn_release);
}

} // namespace

napi_value NativeConvertM3u8ToMp4(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 3) {
        napi_value result;
        napi_create_int32(env, -1, &result);
        return result;
    }

    size_t sourceLength = 0;
    size_t outputLength = 0;
    if (napi_get_value_string_utf8(env, args[0], nullptr, 0, &sourceLength) != napi_ok ||
        napi_get_value_string_utf8(env, args[1], nullptr, 0, &outputLength) != napi_ok) {
        napi_value result;
        napi_create_int32(env, -2, &result);
        return result;
    }

    std::string source(sourceLength + 1, '\0');
    std::string output(outputLength + 1, '\0');
    napi_get_value_string_utf8(env, args[0], source.data(), source.size(), &sourceLength);
    napi_get_value_string_utf8(env, args[1], output.data(), output.size(), &outputLength);
    source.resize(sourceLength);
    output.resize(outputLength);
    if (source.empty() || output.empty()) {
        napi_value result;
        napi_create_int32(env, -3, &result);
        return result;
    }

    napi_threadsafe_function callback = nullptr;
    napi_value name;
    napi_create_string_utf8(env, "M3u8Converter", NAPI_AUTO_LENGTH, &name);
    if (napi_create_threadsafe_function(env, args[2], nullptr, name, 64, 1, nullptr, nullptr,
                                        nullptr, CallConverterCallback, &callback) != napi_ok ||
        callback == nullptr) {
        napi_value result;
        napi_create_int32(env, -4, &result);
        return result;
    }

    try {
        std::thread(ConvertOnWorker, source, output, callback).detach();
    } catch (const std::exception &exception) {
        OH_LOG_ERROR(LOG_APP, "converter worker start failed: %{public}s", exception.what());
        napi_release_threadsafe_function(callback, napi_tsfn_release);
        napi_value result;
        napi_create_int32(env, -5, &result);
        return result;
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "converter worker start failed");
        napi_release_threadsafe_function(callback, napi_tsfn_release);
        napi_value result;
        napi_create_int32(env, -5, &result);
        return result;
    }
    napi_value result;
    napi_create_int32(env, 0, &result);
    return result;
}
