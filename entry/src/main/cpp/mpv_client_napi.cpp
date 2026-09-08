#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"
#include "ohos_surface_helper.h"
#include "mpv_event_handler.h"
#include "video_processing_helper.h"
#include "m3u8_converter_native.h"
#include "video_thumbnail_native.h"
#include "napi/native_api.h"

#ifndef DECLARE_NAPI_FUNCTION
#define DECLARE_NAPI_FUNCTION(name, func) \
    { (name), nullptr, (func), nullptr, nullptr, nullptr, napi_default, nullptr }
#endif

#ifndef EXTERN_C_START
#ifdef __cplusplus
#define EXTERN_C_START extern "C" {
#define EXTERN_C_END }
#else
#define EXTERN_C_START
#define EXTERN_C_END
#endif
#endif

static const char *TAG = "MpvClientNapi";

static napi_value NativeCreate(napi_env env, napi_callback_info info)
{
    napi_value result;
    int64_t ctxId = mpv_wrapper_create();
    napi_create_int32(env, static_cast<int32_t>(ctxId), &result);
    return result;
}

static napi_value NativeInitialize(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    int err = mpv_wrapper_initialize(ctxId);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeCommand(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    napi_value cmd_array = args[1];
    uint32_t cmd_count;
    napi_get_array_length(env, cmd_array, &cmd_count);

    const char **cmd_args = new const char *[cmd_count + 1];
    for (uint32_t i = 0; i < cmd_count; i++) {
        napi_value elem;
        napi_get_element(env, cmd_array, i, &elem);
        size_t len = 0;
        napi_get_value_string_utf8(env, elem, nullptr, 0, &len);
        cmd_args[i] = new char[len + 1];
        napi_get_value_string_utf8(env, elem, const_cast<char *>(cmd_args[i]), len + 1, &len);
    }
    cmd_args[cmd_count] = nullptr;

    int err = mpv_wrapper_command(ctxId, cmd_args);

    for (uint32_t i = 0; i < cmd_count; i++) {
        delete[] cmd_args[i];
    }
    delete[] cmd_args;

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeCommandAsync(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    napi_value cmd_array = args[1];
    uint32_t cmd_count;
    napi_get_array_length(env, cmd_array, &cmd_count);

    const char **cmd_args = new const char *[cmd_count + 1];
    for (uint32_t i = 0; i < cmd_count; i++) {
        napi_value elem;
        napi_get_element(env, cmd_array, i, &elem);
        size_t len = 0;
        napi_get_value_string_utf8(env, elem, nullptr, 0, &len);
        cmd_args[i] = new char[len + 1];
        napi_get_value_string_utf8(env, elem, const_cast<char *>(cmd_args[i]), len + 1, &len);
    }
    cmd_args[cmd_count] = nullptr;

    int err = mpv_wrapper_command_async(ctxId, cmd_args);

    for (uint32_t i = 0; i < cmd_count; i++) {
        delete[] cmd_args[i];
    }
    delete[] cmd_args;

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeLoadSubtitleMemory(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    int err = MPV_ERROR_INVALID_PARAMETER;

    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) == napi_ok && argc == 4) {
        int64_t ctxId = 0;
        void *data = nullptr;
        size_t dataSize = 0;
        size_t extensionLength = 0;
        size_t titleLength = 0;

        napi_status ctxStatus = napi_get_value_int64(env, args[0], &ctxId);
        napi_status dataStatus = napi_get_arraybuffer_info(env, args[1], &data, &dataSize);
        napi_status extensionStatus = napi_get_value_string_utf8(env, args[2], nullptr, 0, &extensionLength);
        napi_status titleStatus = napi_get_value_string_utf8(env, args[3], nullptr, 0, &titleLength);

        if (ctxStatus == napi_ok && dataStatus == napi_ok && extensionStatus == napi_ok && titleStatus == napi_ok &&
            data != nullptr && dataSize > 0 && extensionLength <= 16 && titleLength <= 1024) {
            std::vector<char> extension(extensionLength + 1, '\0');
            std::vector<char> title(titleLength + 1, '\0');
            if (napi_get_value_string_utf8(env, args[2], extension.data(), extension.size(), nullptr) == napi_ok &&
                napi_get_value_string_utf8(env, args[3], title.data(), title.size(), nullptr) == napi_ok) {
                err = mpv_wrapper_load_subtitle_memory(ctxId, static_cast<const uint8_t *>(data), dataSize,
                                                       extension.data(), title.data());
            }
        }
    }

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeSetProperty(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    char name[256] = {0};
    napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);

    char value[1024] = {0};
    napi_get_value_string_utf8(env, args[2], value, sizeof(value), nullptr);

    int err = mpv_wrapper_set_property_string(ctxId, name, value);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeGetProperty(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    char name[256] = {0};
    napi_get_value_string_utf8(env, args[1], name, sizeof(name), nullptr);

    char *value = mpv_wrapper_get_property_string(ctxId, name);

    napi_value result;
    if (value) {
        napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
        mpv_free(value);
    } else {
        napi_get_null(env, &result);
    }
    return result;
}

static napi_value NativeObserveProperty(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    double reply_userdata;
    napi_get_value_double(env, args[1], &reply_userdata);

    char name[256] = {0};
    napi_get_value_string_utf8(env, args[2], name, sizeof(name), nullptr);

    int32_t format;
    napi_get_value_int32(env, args[3], &format);

    int err = mpv_wrapper_observe_property(ctxId, static_cast<uint64_t>(reply_userdata), name, static_cast<mpv_format>(format));

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeDestroy(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    mpv_event_handler_destroy();

    std::thread([ctxId]() {
        mpv_wrapper_destroy(ctxId);
    }).detach();

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

static napi_value NativeSetSurfaceId(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    char surfaceId[256] = {0};
    napi_get_value_string_utf8(env, args[1], surfaceId, sizeof(surfaceId), nullptr);

    int err = ohos_surface_set_surface_id(ctxId, surfaceId);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeApiVersion(napi_env env, napi_callback_info info)
{
    unsigned long version = mpv_wrapper_client_api_version();
    napi_value result;
    napi_create_double(env, static_cast<double>(version), &result);
    return result;
}

static napi_value NativeOnEvent(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int64_t ctxId;
    napi_get_value_int64(env, args[0], &ctxId);

    napi_value callback = args[1];

    int err = mpv_event_handler_init(env, callback, ctxId);

    napi_value result;
    napi_create_int32(env, err, &result);
    return result;
}

static napi_value NativeVpCreate(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t qualityLevel;
    napi_get_value_int32(env, args[0], &qualityLevel);

    int32_t ret = vp_create(qualityLevel);

    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value NativeVpSetOutputSurface(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char surfaceId[256] = {0};
    napi_get_value_string_utf8(env, args[0], surfaceId, sizeof(surfaceId), nullptr);

    int32_t ret = vp_set_output_surface(surfaceId);

    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value NativeVpGetInputSurfaceId(napi_env env, napi_callback_info info)
{
    char inputSurfaceId[256] = {0};
    int32_t ret = vp_get_input_surface_id(inputSurfaceId, sizeof(inputSurfaceId));

    napi_value result;
    if (ret == 0 && strlen(inputSurfaceId) > 0) {
        napi_create_string_utf8(env, inputSurfaceId, NAPI_AUTO_LENGTH, &result);
    } else {
        napi_get_null(env, &result);
    }
    return result;
}

static napi_value NativeVpSetQualityLevel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t qualityLevel;
    napi_get_value_int32(env, args[0], &qualityLevel);

    int32_t ret = vp_set_quality_level(qualityLevel);

    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value NativeVpStart(napi_env env, napi_callback_info info)
{
    int32_t ret = vp_start();

    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value NativeVpStop(napi_env env, napi_callback_info info)
{
    int32_t ret = vp_stop();

    napi_value result;
    napi_create_int32(env, ret, &result);
    return result;
}

static napi_value NativeVpDestroy(napi_env env, napi_callback_info info)
{
    vp_destroy();

    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        DECLARE_NAPI_FUNCTION("nativeCreate", NativeCreate),
        DECLARE_NAPI_FUNCTION("nativeInitialize", NativeInitialize),
        DECLARE_NAPI_FUNCTION("nativeCommand", NativeCommand),
        DECLARE_NAPI_FUNCTION("nativeCommandAsync", NativeCommandAsync),
        DECLARE_NAPI_FUNCTION("nativeLoadSubtitleMemory", NativeLoadSubtitleMemory),
        DECLARE_NAPI_FUNCTION("nativeSetProperty", NativeSetProperty),
        DECLARE_NAPI_FUNCTION("nativeGetProperty", NativeGetProperty),
        DECLARE_NAPI_FUNCTION("nativeObserveProperty", NativeObserveProperty),
        DECLARE_NAPI_FUNCTION("nativeDestroy", NativeDestroy),
        DECLARE_NAPI_FUNCTION("nativeSetSurfaceId", NativeSetSurfaceId),
        DECLARE_NAPI_FUNCTION("nativeApiVersion", NativeApiVersion),
        DECLARE_NAPI_FUNCTION("nativeOnEvent", NativeOnEvent),
        DECLARE_NAPI_FUNCTION("nativeVpCreate", NativeVpCreate),
        DECLARE_NAPI_FUNCTION("nativeVpSetOutputSurface", NativeVpSetOutputSurface),
        DECLARE_NAPI_FUNCTION("nativeVpGetInputSurfaceId", NativeVpGetInputSurfaceId),
        DECLARE_NAPI_FUNCTION("nativeVpSetQualityLevel", NativeVpSetQualityLevel),
        DECLARE_NAPI_FUNCTION("nativeVpStart", NativeVpStart),
        DECLARE_NAPI_FUNCTION("nativeVpStop", NativeVpStop),
        DECLARE_NAPI_FUNCTION("nativeVpDestroy", NativeVpDestroy),
        DECLARE_NAPI_FUNCTION("nativeConvertM3u8ToMp4", NativeConvertM3u8ToMp4),
        DECLARE_NAPI_FUNCTION("nativeGenerateVideoThumbnail", NativeGenerateVideoThumbnail),
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module _module = {
    1,
    0,
    nullptr,
    Init,
    "mpv_napi",
    nullptr,
    {0},
};

extern "C" __attribute__((constructor)) void RegisterModule(void)
{
    napi_module_register(&_module);
}
