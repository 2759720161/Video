#ifndef VIDEO_PROCESSING_HELPER_H
#define VIDEO_PROCESSING_HELPER_H

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

int32_t vp_create(int32_t qualityLevel);
int32_t vp_set_output_surface(const char *displaySurfaceId);
int32_t vp_get_input_surface_id(char *outSurfaceId, int32_t outSize);
int32_t vp_set_quality_level(int32_t qualityLevel);
int32_t vp_start();
int32_t vp_stop();
void vp_destroy();

#ifdef __cplusplus
}
#endif

#endif
