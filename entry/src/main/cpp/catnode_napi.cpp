#include "napi/native_api.h"
#include "catnode_runtime.h"
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <pthread.h>

namespace {
std::atomic<bool> workerRunning{false};
std::mutex workerMutex;
napi_env workerEnvironment = nullptr;

void Cleanup(void* value)
{
    std::lock_guard<std::mutex> lock(workerMutex);
    if (workerEnvironment == static_cast<napi_env>(value)) CatNodeStop();
}

bool ReadString(napi_env env, napi_value value, std::string& output)
{
    napi_valuetype type;
    if (napi_typeof(env, value, &type) != napi_ok || type != napi_string) return false;
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok || size > 4096) return false;
    output.resize(size + 1);
    if (napi_get_value_string_utf8(env, value, output.data(), output.size(), &size) != napi_ok) return false;
    output.resize(size);
    return output.find('\0') == std::string::npos;
}

void Deliver(napi_env env, napi_value callback, void*, void* data)
{
    std::unique_ptr<std::string> message(static_cast<std::string*>(data));
    if (env == nullptr || callback == nullptr) return;
    napi_value value = nullptr;
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    if (napi_create_string_utf8(env, message->c_str(), message->size(), &value) == napi_ok) {
        napi_call_function(env, undefined, callback, 1, &value, nullptr);
    }
}

void Emit(const char* json, void* context)
{
    auto function = static_cast<napi_threadsafe_function>(context);
    auto* message = new std::string(json);
    if (napi_call_threadsafe_function(function, message, napi_tsfn_nonblocking) != napi_ok) delete message;
}

struct Worker {
    std::string script;
    std::string root;
    napi_threadsafe_function function;
};

void* RunWorker(void* value)
{
    std::unique_ptr<Worker> worker(static_cast<Worker*>(value));
    CatNodeRun(worker->script.c_str(), worker->root.c_str(), Emit, worker->function);
    {
        std::lock_guard<std::mutex> lock(workerMutex);
        workerEnvironment = nullptr;
        workerRunning = false;
    }
    Emit("{\"type\":\"stopped\"}", worker->function);
    napi_release_threadsafe_function(worker->function, napi_tsfn_release);
    return nullptr;
}

napi_value Start(napi_env env, napi_callback_info info)
{
    size_t count = 3;
    napi_value values[3];
    napi_get_cb_info(env, info, &count, values, nullptr, nullptr);
    std::string script;
    std::string root;
    napi_valuetype callbackType;
    if (count != 3 || !ReadString(env, values[0], script) || !ReadString(env, values[1], root) ||
        napi_typeof(env, values[2], &callbackType) != napi_ok || callbackType != napi_function ||
        root.empty() || root.front() != '/' || script.compare(0, root.size() + 1, root + "/") != 0) {
        napi_throw_type_error(env, nullptr, "猫源启动参数无效"); return nullptr;
    }
    if (workerRunning.exchange(true)) {
        napi_throw_error(env, nullptr, "猫源正在启动或运行"); return nullptr;
    }
    napi_value resourceName;
    napi_create_string_utf8(env, "CatNodeHost", NAPI_AUTO_LENGTH, &resourceName);
    napi_threadsafe_function function = nullptr;
    const auto result = napi_create_threadsafe_function(env, values[2], nullptr, resourceName,
        128, 1, nullptr, nullptr, nullptr, Deliver, &function);
    if (result != napi_ok) {
        workerRunning = false;
        napi_throw_error(env, nullptr, "猫源通信桥创建失败"); return nullptr;
    }
    napi_unref_threadsafe_function(env, function);
    {
        std::lock_guard<std::mutex> lock(workerMutex);
        CatNodePrepare();
        workerEnvironment = env;
    }
    auto* worker = new Worker{script, root, function};
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, 16 * 1024 * 1024);
    pthread_t thread;
    const auto created = pthread_create(&thread, &attributes, RunWorker, worker);
    pthread_attr_destroy(&attributes);
    if (created != 0) {
        delete worker;
        {
            std::lock_guard<std::mutex> lock(workerMutex);
            workerEnvironment = nullptr;
            workerRunning = false;
        }
        napi_release_threadsafe_function(function, napi_tsfn_abort);
        napi_throw_error(env, nullptr, "猫源运行线程创建失败"); return nullptr;
    }
    pthread_detach(thread);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value Stop(napi_env env, napi_callback_info)
{
    CatNodeStop();
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value IsRunning(napi_env env, napi_callback_info)
{
    napi_value value;
    napi_get_boolean(env, workerRunning.load(), &value);
    return value;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_add_env_cleanup_hook(env, Cleanup, env);
    napi_property_descriptor properties[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, IsRunning, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 3, properties);
    return exports;
}
}

static napi_module module = {1, 0, nullptr, Init, "catnode_napi", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterCatNodeModule()
{
    napi_module_register(&module);
}
