#ifndef OHOS_SURFACE_HELPER_H
#define OHOS_SURFACE_HELPER_H

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

int ohos_surface_set_surface_id(int64_t ctxId, const char *surfaceId);
int ohos_surface_configure_ohcodec(int64_t ctxId, bool enable_hwdec);

#ifdef __cplusplus
}
#endif

#endif // OHOS_SURFACE_HELPER_H

