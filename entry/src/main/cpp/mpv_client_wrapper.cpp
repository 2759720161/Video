#include <algorithm>
#include <cctype>
#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "mpv/client.h"
#include "mpv/stream_cb.h"
#include "mpv_client_wrapper.h"
#include "napi/native_api.h"

static const char *TAG = "MpvClientWrapper";

struct MpvContext {
    mpv_handle *handle;
    bool initialized;
    std::mutex subtitleMutex;
    std::unordered_map<std::string, std::shared_ptr<const std::vector<uint8_t>>> subtitleStreams;
    uint64_t nextSubtitleId;
};

struct SubtitleStreamCookie {
    std::shared_ptr<const std::vector<uint8_t>> data;
    uint64_t position;
};

static std::unordered_map<int64_t, MpvContext *> g_contexts;
static int64_t g_next_id = 1;
static std::mutex g_mutex;

static int64_t subtitle_stream_read(void *cookieValue, char *buffer, uint64_t byteCount)
{
    auto *cookie = static_cast<SubtitleStreamCookie *>(cookieValue);
    if (!cookie || !cookie->data || !buffer) {
        return -1;
    }

    const uint64_t dataSize = static_cast<uint64_t>(cookie->data->size());
    if (cookie->position >= dataSize) {
        return 0;
    }

    const uint64_t available = dataSize - cookie->position;
    const uint64_t readSize = std::min(byteCount, available);
    std::memcpy(buffer, cookie->data->data() + cookie->position, static_cast<size_t>(readSize));
    cookie->position += readSize;
    return static_cast<int64_t>(readSize);
}

static int64_t subtitle_stream_seek(void *cookieValue, int64_t offset)
{
    auto *cookie = static_cast<SubtitleStreamCookie *>(cookieValue);
    if (!cookie || !cookie->data || offset < 0 || static_cast<uint64_t>(offset) > cookie->data->size()) {
        return MPV_ERROR_GENERIC;
    }

    cookie->position = static_cast<uint64_t>(offset);
    return offset;
}

static int64_t subtitle_stream_size(void *cookieValue)
{
    auto *cookie = static_cast<SubtitleStreamCookie *>(cookieValue);
    if (!cookie || !cookie->data) {
        return MPV_ERROR_GENERIC;
    }
    return static_cast<int64_t>(cookie->data->size());
}

static void subtitle_stream_close(void *cookieValue)
{
    delete static_cast<SubtitleStreamCookie *>(cookieValue);
}

static int subtitle_stream_open(void *userData, char *uri, mpv_stream_cb_info *info)
{
    auto *ctx = static_cast<MpvContext *>(userData);
    if (!ctx || !uri || !info) {
        return MPV_ERROR_LOADING_FAILED;
    }

    std::shared_ptr<const std::vector<uint8_t>> data;
    {
        std::lock_guard<std::mutex> lock(ctx->subtitleMutex);
        auto it = ctx->subtitleStreams.find(uri);
        if (it == ctx->subtitleStreams.end()) {
            return MPV_ERROR_LOADING_FAILED;
        }
        data = it->second;
    }

    auto *cookie = new (std::nothrow) SubtitleStreamCookie{data, 0};
    if (!cookie) {
        return MPV_ERROR_NOMEM;
    }

    std::memset(info, 0, sizeof(*info));
    info->cookie = cookie;
    info->read_fn = subtitle_stream_read;
    info->seek_fn = subtitle_stream_seek;
    info->size_fn = subtitle_stream_size;
    info->close_fn = subtitle_stream_close;
    return 0;
}

static std::string sanitize_extension(const char *extension)
{
    if (!extension) {
        return "ass";
    }

    std::string value(extension);
    if (!value.empty() && value.front() == '.') {
        value.erase(value.begin());
    }
    if (value.empty() || value.size() > 16) {
        return "ass";
    }

    for (char &character : value) {
        const unsigned char code = static_cast<unsigned char>(character);
        if (!std::isalnum(code)) {
            return "ass";
        }
        character = static_cast<char>(std::tolower(code));
    }
    return value;
}

static MpvContext *find_context(int64_t id)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(id);
    if (it != g_contexts.end()) {
        return it->second;
    }
    return nullptr;
}

static int64_t store_context(MpvContext *ctx)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    int64_t id = g_next_id++;
    g_contexts[id] = ctx;
    return id;
}

static void remove_context(int64_t id)
{
    MpvContext *context = nullptr;
    {
        // Only protect the context registry itself. mpv_terminate_destroy()
        // may wait for decoder/render threads for several seconds; holding the
        // global registry mutex across that wait blocks a replacement
        // nativeCreate() on ArkUI's main thread and triggers THREAD_BLOCK_6S.
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_contexts.find(id);
        if (it == g_contexts.end()) {
            return;
        }
        context = it->second;
        g_contexts.erase(it);
    }

    if (context->handle) {
        mpv_terminate_destroy(context->handle);
    }
    delete context;
}

extern "C" int64_t mpv_wrapper_create()
{
    mpv_handle *handle = mpv_create();
    if (!handle) {
        return -1;
    }

    MpvContext *ctx = new MpvContext();
    ctx->handle = handle;
    ctx->initialized = false;
    ctx->nextSubtitleId = 1;

    int streamError = mpv_stream_cb_add_ro(handle, "ohsubtitle", ctx, subtitle_stream_open);
    if (streamError < 0) {
        mpv_terminate_destroy(handle);
        delete ctx;
        return -1;
    }

    int64_t id = store_context(ctx);
    return id;
}

extern "C" int mpv_wrapper_initialize(int64_t ctxId)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }

    int err = mpv_initialize(ctx->handle);
    if (err >= 0) {
        ctx->initialized = true;
    }
    return err;
}

extern "C" int mpv_wrapper_command(int64_t ctxId, const char **args)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_command(ctx->handle, args);
}

extern "C" int mpv_wrapper_command_async(int64_t ctxId, const char **args)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_command_async(ctx->handle, 0, args);
}

extern "C" int mpv_wrapper_command_string(int64_t ctxId, const char *args)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_command_string(ctx->handle, args);
}

extern "C" int mpv_wrapper_load_subtitle_memory(int64_t ctxId, const uint8_t *data, size_t size,
                                                   const char *extension, const char *title)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle || !ctx->initialized || !data || size == 0) {
        return MPV_ERROR_INVALID_PARAMETER;
    }

    std::shared_ptr<const std::vector<uint8_t>> subtitleData;
    try {
        subtitleData = std::make_shared<const std::vector<uint8_t>>(data, data + size);
    } catch (const std::bad_alloc &) {
        return MPV_ERROR_NOMEM;
    }

    std::string uri;
    {
        std::lock_guard<std::mutex> lock(ctx->subtitleMutex);
        uri = "ohsubtitle://subtitle-" + std::to_string(ctx->nextSubtitleId++) + "." +
              sanitize_extension(extension);
        ctx->subtitleStreams[uri] = subtitleData;
    }

    const char *subtitleTitle = (title && title[0] != '\0') ? title : nullptr;
    const char *args[] = {"sub-add", uri.c_str(), "select", subtitleTitle, nullptr};
    int result = mpv_command(ctx->handle, args);
    if (result < 0) {
        std::lock_guard<std::mutex> lock(ctx->subtitleMutex);
        ctx->subtitleStreams.erase(uri);
    }
    return result;
}

extern "C" int mpv_wrapper_set_property_string(int64_t ctxId, const char *name, const char *value)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_set_property_string(ctx->handle, name, value);
}

extern "C" char *mpv_wrapper_get_property_string(int64_t ctxId, const char *name)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return nullptr;
    }
    return mpv_get_property_string(ctx->handle, name);
}

extern "C" int mpv_wrapper_observe_property(int64_t ctxId, uint64_t reply_userdata, const char *name, mpv_format format)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_observe_property(ctx->handle, reply_userdata, name, format);
}

extern "C" int mpv_wrapper_unobserve_property(int64_t ctxId, uint64_t reply_userdata)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_unobserve_property(ctx->handle, reply_userdata);
}

extern "C" int mpv_wrapper_request_log_messages(int64_t ctxId, const char *minLevel)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle || !minLevel) {
        return MPV_ERROR_INVALID_PARAMETER;
    }
    return mpv_request_log_messages(ctx->handle, minLevel);
}

extern "C" mpv_event *mpv_wrapper_wait_event(int64_t ctxId, double timeout)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return nullptr;
    }
    return mpv_wait_event(ctx->handle, timeout);
}

extern "C" void mpv_wrapper_wakeup(int64_t ctxId)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return;
    }
    mpv_wakeup(ctx->handle);
}

extern "C" void mpv_wrapper_set_wakeup_callback(int64_t ctxId, void (*cb)(void *), void *userData)
{
    MpvContext *ctx = find_context(ctxId);
    if (!ctx || !ctx->handle) {
        return;
    }
    mpv_set_wakeup_callback(ctx->handle, cb, userData);
}

extern "C" void mpv_wrapper_destroy(int64_t ctxId)
{
    remove_context(ctxId);
}

extern "C" unsigned long mpv_wrapper_client_api_version()
{
    return mpv_client_api_version();
}

extern "C" const char *mpv_wrapper_error_string(int error)
{
    return mpv_error_string(error);
}
