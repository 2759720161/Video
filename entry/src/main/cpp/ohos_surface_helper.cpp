#include <cstring>
#include <string>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"
#include "ohos_surface_helper.h"
#include "napi/native_api.h"

static const char *TAG = "OhosSurfaceHelper";

extern "C" int ohos_surface_set_surface_id(int64_t ctxId, const char *surfaceId)
{
    if (!surfaceId || strlen(surfaceId) == 0) {
        return MPV_ERROR_INVALID_PARAMETER;
    }

    int err = mpv_wrapper_set_property_string(ctxId, "vo", "ohcodec");
    if (err < 0) {
        return err;
    }

    err = mpv_wrapper_set_property_string(ctxId, "wid", surfaceId);
    return err;
}

extern "C" int ohos_surface_configure_ohcodec(int64_t ctxId, bool enable_hwdec)
{
    if (enable_hwdec) {
        int err = mpv_wrapper_set_property_string(ctxId, "hwdec", "auto");
        if (err < 0) {
            return err;
        }
    } else {
        mpv_wrapper_set_property_string(ctxId, "hwdec", "no");
    }
    return 0;
}