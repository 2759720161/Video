#ifndef MPV_EVENT_HANDLER_H
#define MPV_EVENT_HANDLER_H

#include <cstdint>
#include "napi/native_api.h"

#ifdef __cplusplus
extern "C" {
#endif

int mpv_event_handler_init(napi_env env, napi_value callback, int64_t ctxId);
void mpv_event_handler_destroy();
void mpv_event_handler_wakeup(int64_t ctxId);

#ifdef __cplusplus
}
#endif

#endif // MPV_EVENT_HANDLER_H

