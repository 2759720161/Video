#ifndef MPV_CLIENT_WRAPPER_H
#define MPV_CLIENT_WRAPPER_H

#include <cstddef>
#include <cstdint>
#include "mpv/client.h"

#ifdef __cplusplus
extern "C" {
#endif

int64_t mpv_wrapper_create();
int mpv_wrapper_initialize(int64_t ctxId);
int mpv_wrapper_command(int64_t ctxId, const char **args);
int mpv_wrapper_command_async(int64_t ctxId, const char **args);
int mpv_wrapper_command_string(int64_t ctxId, const char *args);
int mpv_wrapper_load_subtitle_memory(int64_t ctxId, const uint8_t *data, size_t size, const char *extension,
                                     const char *title);
int mpv_wrapper_set_property_string(int64_t ctxId, const char *name, const char *value);
char *mpv_wrapper_get_property_string(int64_t ctxId, const char *name);
int mpv_wrapper_observe_property(int64_t ctxId, uint64_t reply_userdata, const char *name, mpv_format format);
int mpv_wrapper_unobserve_property(int64_t ctxId, uint64_t reply_userdata);
int mpv_wrapper_request_log_messages(int64_t ctxId, const char *minLevel);
mpv_event *mpv_wrapper_wait_event(int64_t ctxId, double timeout);
void mpv_wrapper_wakeup(int64_t ctxId);
void mpv_wrapper_set_wakeup_callback(int64_t ctxId, void (*cb)(void *), void *userData);
void mpv_wrapper_destroy(int64_t ctxId);
unsigned long mpv_wrapper_client_api_version();
const char *mpv_wrapper_error_string(int error);

#ifdef __cplusplus
}
#endif

#endif // MPV_CLIENT_WRAPPER_H
