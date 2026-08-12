#include <cstring>
#include <hilog/log.h>
#include <multimedia/video_processing_engine/video_processing.h>
#include <multimedia/video_processing_engine/video_processing_types.h>
#include <multimedia/player_framework/native_avformat.h>
#include <native_window/external_window.h>

#include "video_processing_helper.h"

static const char *TAG = "VideoProcessingHelper";
static OH_VideoProcessing *g_videoProcessor = nullptr;
static VideoProcessing_Callback *g_callback = nullptr;
static OHNativeWindow *g_inputWindow = nullptr;

static void OnVpError(OH_VideoProcessing *vp, VideoProcessing_ErrorCode error, void *userData)
{
    OH_LOG_WARN(LOG_APP, "VideoProcessing error: %{public}d", error);
}

static void OnVpState(OH_VideoProcessing *vp, VideoProcessing_State state, void *userData)
{
    const char *stateStr = (state == VIDEO_PROCESSING_STATE_RUNNING) ? "RUNNING" : "STOPPED";
    OH_LOG_INFO(LOG_APP, "VideoProcessing state: %{public}s", stateStr);
}

static void OnVpNewOutputBuffer(OH_VideoProcessing *vp, uint32_t index, void *userData)
{
    OH_VideoProcessing_RenderOutputBuffer(vp, index);
}

static void vp_destroy_internal()
{
    if (g_videoProcessor != nullptr) {
        OH_VideoProcessing_Stop(g_videoProcessor);
        OH_VideoProcessing_Destroy(g_videoProcessor);
        g_videoProcessor = nullptr;
    }
    if (g_callback != nullptr) {
        OH_VideoProcessingCallback_Destroy(g_callback);
        g_callback = nullptr;
    }
    if (g_inputWindow != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(g_inputWindow);
        g_inputWindow = nullptr;
    }
}

extern "C" {

int32_t vp_create(int32_t qualityLevel)
{
    if (g_videoProcessor != nullptr) {
        OH_LOG_WARN(LOG_APP, "VideoProcessing instance already exists, destroying first");
        vp_destroy_internal();
    }

    VideoProcessing_ErrorCode ret = OH_VideoProcessing_InitializeEnvironment();
    if (ret != VIDEO_PROCESSING_SUCCESS && ret != VIDEO_PROCESSING_ERROR_OPERATION_NOT_PERMITTED) {
        OH_LOG_WARN(LOG_APP, "VideoProcessing InitializeEnvironment: %{public}d (non-fatal)", ret);
    }

    ret = OH_VideoProcessing_Create(&g_videoProcessor, VIDEO_PROCESSING_TYPE_DETAIL_ENHANCER);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing Create failed: %{public}d", ret);
        g_videoProcessor = nullptr;
        return ret;
    }

    ret = OH_VideoProcessingCallback_Create(&g_callback);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessingCallback Create failed: %{public}d", ret);
        OH_VideoProcessing_Destroy(g_videoProcessor);
        g_videoProcessor = nullptr;
        return ret;
    }

    OH_VideoProcessingCallback_BindOnError(g_callback, OnVpError);
    OH_VideoProcessingCallback_BindOnState(g_callback, OnVpState);
    OH_VideoProcessingCallback_BindOnNewOutputBuffer(g_callback, OnVpNewOutputBuffer);

    ret = OH_VideoProcessing_RegisterCallback(g_videoProcessor, g_callback, nullptr);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing RegisterCallback failed: %{public}d", ret);
        OH_VideoProcessingCallback_Destroy(g_callback);
        g_callback = nullptr;
        OH_VideoProcessing_Destroy(g_videoProcessor);
        g_videoProcessor = nullptr;
        return ret;
    }

    if (qualityLevel >= 0) {
        OH_AVFormat *param = OH_AVFormat_Create();
        OH_AVFormat_SetIntValue(param, VIDEO_DETAIL_ENHANCER_PARAMETER_KEY_QUALITY_LEVEL, qualityLevel);
        ret = OH_VideoProcessing_SetParameter(g_videoProcessor, param);
        OH_AVFormat_Destroy(param);
        if (ret != VIDEO_PROCESSING_SUCCESS) {
            OH_LOG_WARN(LOG_APP, "VideoProcessing SetParameter quality=%{public}d failed: %{public}d (non-fatal)",
                qualityLevel, ret);
        } else {
            OH_LOG_INFO(LOG_APP, "VideoProcessing quality level set: %{public}d", qualityLevel);
        }
    }

    OH_LOG_INFO(LOG_APP, "VideoProcessing created successfully");
    return VIDEO_PROCESSING_SUCCESS;
}

int32_t vp_set_output_surface(const char *displaySurfaceId)
{
    if (g_videoProcessor == nullptr) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing set_output_surface: no instance");
        return VIDEO_PROCESSING_ERROR_INVALID_INSTANCE;
    }
    if (!displaySurfaceId || strlen(displaySurfaceId) == 0) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing set_output_surface: invalid surfaceId");
        return VIDEO_PROCESSING_ERROR_INVALID_PARAMETER;
    }

    uint64_t surfaceId = 0;
    if (sscanf(displaySurfaceId, "%llu", (unsigned long long *)&surfaceId) != 1) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing: failed to parse surfaceId: %{public}s", displaySurfaceId);
        return VIDEO_PROCESSING_ERROR_INVALID_PARAMETER;
    }

    OHNativeWindow *displayWindow = nullptr;
    int32_t err = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &displayWindow);
    if (err != 0 || displayWindow == nullptr) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing: CreateNativeWindowFromSurfaceId failed: %{public}d", err);
        return VIDEO_PROCESSING_ERROR_INVALID_PARAMETER;
    }

    VideoProcessing_ErrorCode ret = OH_VideoProcessing_SetSurface(g_videoProcessor, displayWindow);
    OH_NativeWindow_DestroyNativeWindow(displayWindow);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing SetSurface failed: %{public}d", ret);
        return ret;
    }

    OH_LOG_INFO(LOG_APP, "VideoProcessing output surface set: %{public}s", displaySurfaceId);
    return VIDEO_PROCESSING_SUCCESS;
}

int32_t vp_get_input_surface_id(char *outSurfaceId, int32_t outSize)
{
    if (g_videoProcessor == nullptr) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing get_input_surface_id: no instance");
        return VIDEO_PROCESSING_ERROR_INVALID_INSTANCE;
    }

    if (g_inputWindow != nullptr) {
        OH_NativeWindow_DestroyNativeWindow(g_inputWindow);
        g_inputWindow = nullptr;
    }

    VideoProcessing_ErrorCode ret = OH_VideoProcessing_GetSurface(g_videoProcessor, &g_inputWindow);
    if (ret != VIDEO_PROCESSING_SUCCESS || g_inputWindow == nullptr) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing GetSurface failed: %{public}d", ret);
        return ret;
    }

    uint64_t inputSurfaceId = 0;
    int32_t err = OH_NativeWindow_GetSurfaceId(g_inputWindow, &inputSurfaceId);
    if (err != 0) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing GetSurfaceId failed: %{public}d", err);
        return VIDEO_PROCESSING_ERROR_INVALID_PARAMETER;
    }

    snprintf(outSurfaceId, outSize, "%llu", (unsigned long long)inputSurfaceId);
    OH_LOG_INFO(LOG_APP, "VideoProcessing input surface id: %{public}s", outSurfaceId);
    return VIDEO_PROCESSING_SUCCESS;
}

int32_t vp_set_quality_level(int32_t qualityLevel)
{
    if (g_videoProcessor == nullptr) {
        return VIDEO_PROCESSING_ERROR_INVALID_INSTANCE;
    }

    OH_AVFormat *param = OH_AVFormat_Create();
    OH_AVFormat_SetIntValue(param, VIDEO_DETAIL_ENHANCER_PARAMETER_KEY_QUALITY_LEVEL, qualityLevel);
    VideoProcessing_ErrorCode ret = OH_VideoProcessing_SetParameter(g_videoProcessor, param);
    OH_AVFormat_Destroy(param);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_WARN(LOG_APP, "VideoProcessing SetQualityLevel %{public}d failed: %{public}d", qualityLevel, ret);
    } else {
        OH_LOG_INFO(LOG_APP, "VideoProcessing quality level changed: %{public}d", qualityLevel);
    }
    return ret;
}

int32_t vp_start()
{
    if (g_videoProcessor == nullptr) {
        return VIDEO_PROCESSING_ERROR_INVALID_INSTANCE;
    }
    VideoProcessing_ErrorCode ret = OH_VideoProcessing_Start(g_videoProcessor);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_ERROR(LOG_APP, "VideoProcessing Start failed: %{public}d", ret);
    } else {
        OH_LOG_INFO(LOG_APP, "VideoProcessing started");
    }
    return ret;
}

int32_t vp_stop()
{
    if (g_videoProcessor == nullptr) {
        return VIDEO_PROCESSING_SUCCESS;
    }
    VideoProcessing_ErrorCode ret = OH_VideoProcessing_Stop(g_videoProcessor);
    if (ret != VIDEO_PROCESSING_SUCCESS) {
        OH_LOG_WARN(LOG_APP, "VideoProcessing Stop failed: %{public}d", ret);
    } else {
        OH_LOG_INFO(LOG_APP, "VideoProcessing stopped");
    }
    return ret;
}

void vp_destroy()
{
    vp_destroy_internal();
    OH_LOG_INFO(LOG_APP, "VideoProcessing destroyed");
}

} // extern "C"
