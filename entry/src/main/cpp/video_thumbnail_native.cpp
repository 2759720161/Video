#include "video_thumbnail_native.h"

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <exception>
#include <new>
#include <string>
#include <thread>

#include <sys/stat.h>
#include <unistd.h>

#include <hilog/log.h>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"

#undef LOG_TAG
#define LOG_TAG "VideoThumbnailNative"

namespace {

struct ThumbnailUpdate {
    bool success;
    int errorCode;
    std::string message;
    std::string outputPath;
};

static bool IsValidFile(const std::string &path)
{
    struct stat fileStat {};
    return stat(path.c_str(), &fileStat) == 0 && S_ISREG(fileStat.st_mode) && fileStat.st_size > 100;
}

static void CallThumbnailCallback(napi_env env, napi_value jsCallback, void *context, void *data)
{
    auto *update = static_cast<ThumbnailUpdate *>(data);
    if (env == nullptr || jsCallback == nullptr || update == nullptr) {
        delete update;
        return;
    }

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_value object;
    napi_create_object(env, &object);

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

static void EmitThumbnailUpdate(napi_threadsafe_function callback, bool success, int errorCode,
                                const std::string &message, const std::string &outputPath)
{
    auto *update = new (std::nothrow) ThumbnailUpdate{success, errorCode, message, outputPath};
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

static int SetOption(int64_t contextId, const char *name, const char *value)
{
    return mpv_wrapper_set_property_string(contextId, name, value);
}

static void GenerateOnWorkerBody(const std::string source, const std::string output,
                                 napi_threadsafe_function callback)
{
    const std::string frameDirectory = output + ".mpv_frames";
    const std::string generatedFrame = frameDirectory + "/00000001.jpg";
    std::remove(generatedFrame.c_str());
    rmdir(frameDirectory.c_str());

    bool success = false;
    int errorCode = 0;
    std::string errorMessage;
    if (mkdir(frameDirectory.c_str(), 0755) != 0 && errno != EEXIST) {
        errorCode = errno;
        errorMessage = "无法创建封面临时目录";
    }

    int64_t contextId = -1;
    if (errorMessage.empty()) {
        contextId = mpv_wrapper_create();
        if (contextId < 0) {
            errorCode = static_cast<int>(contextId);
            errorMessage = "创建封面解码器失败";
        }
    }

    if (contextId >= 0) {
        struct OptionPair {
            const char *name;
            const char *value;
        };
        const OptionPair options[] = {
            {"vo", "image"},
            {"vo-image-outdir", frameDirectory.c_str()},
            {"vo-image-format", "jpg"},
            {"vo-image-jpeg-quality", "82"},
            {"audio", "no"},
            {"sub", "no"},
            {"hwdec", "no"},
            {"frames", "1"},
            {"start", "1"},
            {"keep-open", "no"},
            {"terminal", "no"}
        };
        for (const auto &option : options) {
            const int optionError = SetOption(contextId, option.name, option.value);
            if (optionError < 0) {
                errorCode = optionError;
                errorMessage = std::string("设置封面解码参数失败: ") + option.name;
                break;
            }
        }
    }

    if (contextId >= 0 && errorMessage.empty()) {
        const int initializeError = mpv_wrapper_initialize(contextId);
        if (initializeError < 0) {
            errorCode = initializeError;
            errorMessage = "初始化封面解码器失败";
        }
    }

    if (contextId >= 0 && errorMessage.empty()) {
        mpv_wrapper_request_log_messages(contextId, "warn");
        const char *loadArgs[] = {"loadfile", source.c_str(), "replace", nullptr};
        const int loadError = mpv_wrapper_command(contextId, loadArgs);
        if (loadError < 0) {
            errorCode = loadError;
            errorMessage = "无法打开视频生成封面";
        } else {
            const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(15);
            while (std::chrono::steady_clock::now() < deadline) {
                mpv_event *event = mpv_wrapper_wait_event(contextId, 0.20);
                if (IsValidFile(generatedFrame)) {
                    success = true;
                    break;
                }
                if (event != nullptr && event->event_id == MPV_EVENT_END_FILE) {
                    auto *endFile = static_cast<mpv_event_end_file *>(event->data);
                    if (endFile != nullptr && endFile->error < 0) {
                        errorCode = endFile->error;
                    }
                    break;
                }
            }
        }
    }

    if (contextId >= 0) {
        mpv_wrapper_destroy(contextId);
    }
    success = success || IsValidFile(generatedFrame);
    if (success) {
        std::remove(output.c_str());
        if (std::rename(generatedFrame.c_str(), output.c_str()) != 0) {
            success = false;
            errorCode = errno;
            errorMessage = "无法保存解码后的封面";
        }
    }
    std::remove(generatedFrame.c_str());
    rmdir(frameDirectory.c_str());

    if (!success && errorMessage.empty()) {
        errorMessage = "mpv 未输出可用视频帧";
    }
    if (success) {
        OH_LOG_INFO(LOG_APP, "mpv thumbnail generated: %{public}s", output.c_str());
    } else {
        OH_LOG_ERROR(LOG_APP, "mpv thumbnail failed: code=%{public}d message=%{public}s",
                     errorCode, errorMessage.c_str());
    }
    EmitThumbnailUpdate(callback, success, errorCode, success ? "封面生成成功" : errorMessage,
                        success ? output : std::string());
}

static void GenerateOnWorker(const std::string source, const std::string output,
                             napi_threadsafe_function callback)
{
    try {
        GenerateOnWorkerBody(source, output, callback);
    } catch (const std::exception &exception) {
        OH_LOG_ERROR(LOG_APP, "thumbnail worker exception: %{public}s", exception.what());
        EmitThumbnailUpdate(callback, false, -1000, "封面解码异常", output);
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "thumbnail worker unknown exception");
        EmitThumbnailUpdate(callback, false, -1001, "封面解码异常", output);
    }
    // Release the initial reference created by napi_create_threadsafe_function.
    napi_release_threadsafe_function(callback, napi_tsfn_release);
}

} // namespace

napi_value NativeGenerateVideoThumbnail(napi_env env, napi_callback_info info)
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
    napi_create_string_utf8(env, "VideoThumbnail", NAPI_AUTO_LENGTH, &name);
    if (napi_create_threadsafe_function(env, args[2], nullptr, name, 8, 1, nullptr, nullptr,
                                        nullptr, CallThumbnailCallback, &callback) != napi_ok ||
        callback == nullptr) {
        napi_value result;
        napi_create_int32(env, -4, &result);
        return result;
    }

    try {
        std::thread(GenerateOnWorker, source, output, callback).detach();
    } catch (const std::exception &exception) {
        OH_LOG_ERROR(LOG_APP, "thumbnail worker start failed: %{public}s", exception.what());
        napi_release_threadsafe_function(callback, napi_tsfn_release);
        napi_value result;
        napi_create_int32(env, -5, &result);
        return result;
    } catch (...) {
        OH_LOG_ERROR(LOG_APP, "thumbnail worker start failed");
        napi_release_threadsafe_function(callback, napi_tsfn_release);
        napi_value result;
        napi_create_int32(env, -5, &result);
        return result;
    }
    napi_value result;
    napi_create_int32(env, 0, &result);
    return result;
}
