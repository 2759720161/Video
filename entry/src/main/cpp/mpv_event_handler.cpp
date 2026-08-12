#include <cstring>
#include <string>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <atomic>
#include <thread>

#include "mpv/client.h"
#include "mpv_client_wrapper.h"
#include "mpv_event_handler.h"
#include "napi/native_api.h"

static const char *TAG = "MpvEventHandler";

static napi_threadsafe_function g_tsfn = nullptr;
static std::atomic<bool> g_tsfn_initialized{false};
static constexpr size_t MAX_EVENT_QUEUE_SIZE = 1024;

struct MpvEventData {
    int64_t ctxId;
    int eventId;
    int errorCode;
    char propertyName[256];
    char propertyValueStr[1024];
    double propertyValueDouble;
    int reason;
    char logPrefix[128];
    char logLevel[32];
    char logText[2048];
};

static std::queue<int64_t> g_pending_contexts;
static std::mutex g_signal_mutex;
static std::condition_variable g_signal_cv;
static std::thread g_event_thread;
static std::atomic<bool> g_event_thread_running{false};

static void call_js_cb(napi_env env, napi_value js_cb, void *context, void *data)
{
    if (env == nullptr || js_cb == nullptr) {
        return;
    }

    MpvEventData *event = static_cast<MpvEventData *>(data);
    if (!event) {
        return;
    }

    napi_value undefined;
    napi_get_undefined(env, &undefined);

    napi_value obj;
    napi_create_object(env, &obj);

    napi_value ctx_id;
    napi_create_int64(env, event->ctxId, &ctx_id);
    napi_set_named_property(env, obj, "ctxId", ctx_id);

    napi_value event_id;
    napi_create_int32(env, event->eventId, &event_id);
    napi_set_named_property(env, obj, "eventId", event_id);

    napi_value error_code;
    napi_create_int32(env, event->errorCode, &error_code);
    napi_set_named_property(env, obj, "errorCode", error_code);

    napi_value property_name;
    napi_create_string_utf8(env, event->propertyName, NAPI_AUTO_LENGTH, &property_name);
    napi_set_named_property(env, obj, "propertyName", property_name);

    napi_value property_value_str;
    napi_create_string_utf8(env, event->propertyValueStr, NAPI_AUTO_LENGTH, &property_value_str);
    napi_set_named_property(env, obj, "propertyValueStr", property_value_str);

    napi_value property_value_double;
    napi_create_double(env, event->propertyValueDouble, &property_value_double);
    napi_set_named_property(env, obj, "propertyValueDouble", property_value_double);

    napi_value reason;
    napi_create_int32(env, event->reason, &reason);
    napi_set_named_property(env, obj, "reason", reason);

    napi_value log_prefix;
    napi_create_string_utf8(env, event->logPrefix, NAPI_AUTO_LENGTH, &log_prefix);
    napi_set_named_property(env, obj, "logPrefix", log_prefix);

    napi_value log_level;
    napi_create_string_utf8(env, event->logLevel, NAPI_AUTO_LENGTH, &log_level);
    napi_set_named_property(env, obj, "logLevel", log_level);

    napi_value log_text;
    napi_create_string_utf8(env, event->logText, NAPI_AUTO_LENGTH, &log_text);
    napi_set_named_property(env, obj, "logText", log_text);

    napi_call_function(env, undefined, js_cb, 1, &obj, nullptr);

    delete event;
}

static void on_mpv_events(int64_t ctxId)
{
    while (true) {
        mpv_event *event = mpv_wrapper_wait_event(ctxId, 0.0);
        if (!event || event->event_id == MPV_EVENT_NONE) {
            break;
        }

        if (!g_tsfn_initialized.load()) {
            break;
        }

        MpvEventData *data = new MpvEventData();
        data->ctxId = ctxId;
        data->eventId = event->event_id;
        data->errorCode = event->error;
        data->propertyName[0] = '\0';
        data->propertyValueStr[0] = '\0';
        data->propertyValueDouble = 0.0;
        data->reason = 0;
        data->logPrefix[0] = '\0';
        data->logLevel[0] = '\0';
        data->logText[0] = '\0';

        if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
            mpv_event_property *prop = static_cast<mpv_event_property *>(event->data);
            if (prop && prop->name) {
                strncpy(data->propertyName, prop->name, sizeof(data->propertyName) - 1);
                data->propertyName[sizeof(data->propertyName) - 1] = '\0';
            }
            if (prop) {
                if (prop->format == MPV_FORMAT_STRING) {
                    const char **val = static_cast<const char **>(prop->data);
                    if (val && *val) {
                        strncpy(data->propertyValueStr, *val, sizeof(data->propertyValueStr) - 1);
                        data->propertyValueStr[sizeof(data->propertyValueStr) - 1] = '\0';
                    }
                } else if (prop->format == MPV_FORMAT_DOUBLE) {
                    double *val = static_cast<double *>(prop->data);
                    if (val) {
                        data->propertyValueDouble = *val;
                    }
                } else if (prop->format == MPV_FORMAT_FLAG) {
                    int *val = static_cast<int *>(prop->data);
                    if (val) {
                        data->propertyValueDouble = static_cast<double>(*val);
                    }
                }
            }
        } else if (event->event_id == MPV_EVENT_END_FILE) {
            mpv_event_end_file *ef = static_cast<mpv_event_end_file *>(event->data);
            if (ef) {
                data->reason = ef->reason;
                data->errorCode = ef->error;
            }
        } else if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
            mpv_event_log_message *msg = static_cast<mpv_event_log_message *>(event->data);
            if (msg) {
                if (msg->prefix) {
                    strncpy(data->logPrefix, msg->prefix, sizeof(data->logPrefix) - 1);
                    data->logPrefix[sizeof(data->logPrefix) - 1] = '\0';
                }
                if (msg->level) {
                    strncpy(data->logLevel, msg->level, sizeof(data->logLevel) - 1);
                    data->logLevel[sizeof(data->logLevel) - 1] = '\0';
                }
                if (msg->text) {
                    strncpy(data->logText, msg->text, sizeof(data->logText) - 1);
                    data->logText[sizeof(data->logText) - 1] = '\0';
                }
            }
        }

        napi_acquire_threadsafe_function(g_tsfn);
        napi_status status = napi_call_threadsafe_function(g_tsfn, data, napi_tsfn_nonblocking);
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        if (status != napi_ok) {
            delete data;
        }
    }
}

static void mpv_wakeup_callback(void *ctx)
{
    int64_t ctxId = static_cast<int64_t>(reinterpret_cast<intptr_t>(ctx));
    {
        std::lock_guard<std::mutex> lock(g_signal_mutex);
        g_pending_contexts.push(ctxId);
    }
    g_signal_cv.notify_one();
}

static void event_thread_main()
{
    while (g_event_thread_running.load()) {
        int64_t ctxId = 0;
        {
            std::unique_lock<std::mutex> lock(g_signal_mutex);
            g_signal_cv.wait(lock, [] {
                return !g_pending_contexts.empty() || !g_event_thread_running.load();
            });
            if (!g_event_thread_running.load()) {
                break;
            }
            ctxId = g_pending_contexts.front();
            g_pending_contexts.pop();
        }
        on_mpv_events(ctxId);
    }
}

static void ensure_event_thread_started()
{
    bool expected = false;
    if (g_event_thread_running.compare_exchange_strong(expected, true)) {
        g_event_thread = std::thread(event_thread_main);
    }
}

static void stop_event_thread()
{
    if (!g_event_thread_running.exchange(false)) {
        return;
    }
    g_signal_cv.notify_all();
    if (g_event_thread.joinable()) {
        g_event_thread.join();
    }

    std::lock_guard<std::mutex> lock(g_signal_mutex);
    std::queue<int64_t> empty;
    std::swap(g_pending_contexts, empty);
}

extern "C" int mpv_event_handler_init(napi_env env, napi_value callback, int64_t ctxId)
{
    if (g_tsfn_initialized.load()) {
        ensure_event_thread_started();
        mpv_wrapper_request_log_messages(ctxId, "info");
        mpv_wrapper_set_wakeup_callback(ctxId, mpv_wakeup_callback,
                                         reinterpret_cast<void *>(static_cast<intptr_t>(ctxId)));
        return 0;
    }

    napi_value work_name;
    napi_create_string_utf8(env, "MpvEventHandler", NAPI_AUTO_LENGTH, &work_name);

    napi_create_threadsafe_function(
        env, callback, nullptr, work_name,
        MAX_EVENT_QUEUE_SIZE, 1,
        nullptr, nullptr, nullptr, call_js_cb, &g_tsfn);

    g_tsfn_initialized.store(true);
    ensure_event_thread_started();

    mpv_wrapper_request_log_messages(ctxId, "info");
    mpv_wrapper_set_wakeup_callback(ctxId, mpv_wakeup_callback,
                                     reinterpret_cast<void *>(static_cast<intptr_t>(ctxId)));
    return 0;
}

extern "C" void mpv_event_handler_destroy()
{
    if (g_tsfn_initialized.load()) {
        stop_event_thread();
        g_tsfn_initialized.store(false);
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_abort);
        g_tsfn = nullptr;
    }
}

extern "C" void mpv_event_handler_wakeup(int64_t ctxId)
{
    mpv_wrapper_wakeup(ctxId);
}
