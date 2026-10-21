#include "catnode_runtime.h"
#include "node.h"
#include "uv.h"
#include <atomic>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
std::mutex environmentMutex;
node::Environment* environment = nullptr;
std::once_flag initialization;
// V8 is initialized for the process lifetime; unloading it while an application
// engine can be restarted is unsafe. The OS releases this bounded platform at exit.
node::MultiIsolatePlatform* platform = nullptr;
std::string initializationError;
std::atomic<bool> running{false};
std::atomic<bool> stopRequested{false};

std::string Quote(const std::string& value)
{
    static const char hex[] = "0123456789abcdef";
    std::string result = "\"";
    for (unsigned char c : value) {
        if (c == '\\' || c == '"') { result += '\\'; result += c; }
        else if (c < 0x20) {
            result += "\\u00";
            result += hex[c >> 4]; result += hex[c & 15];
        } else result += c;
    }
    return result + "\"";
}

struct Host {
    CatNodeEmit emit;
    void* context;
};

class RegisteredEnvironment {
public:
    explicit RegisteredEnvironment(node::Environment* value) {
        std::lock_guard<std::mutex> lock(environmentMutex);
        environment = value;
    }
    ~RegisteredEnvironment() {
        std::lock_guard<std::mutex> lock(environmentMutex);
        environment = nullptr;
    }
};

void Notify(const v8::FunctionCallbackInfo<v8::Value>& args)
{
    if (args.Length() != 1 || !args[0]->IsString()) return;
    auto* host = static_cast<Host*>(args.Data().As<v8::External>()->Value());
    v8::String::Utf8Value value(args.GetIsolate(), args[0]);
    if (*value != nullptr && value.length() <= 65536) host->emit(*value, host->context);
}

void Error(Host& host, const std::string& message)
{
    const auto json = "{\"type\":\"error\",\"message\":" + Quote(message) + "}";
    host.emit(json.c_str(), host.context);
}
}

int CatNodeRun(const char* script, const char* root, CatNodeEmit emit, void* context)
{
    Host host{emit, context};
#ifndef CATNODE_SANDBOX_READY
    Error(host, "当前安装包尚未包含可用的完整猫源，请更新应用");
    return 1;
#endif
    if (running.exchange(true)) { Error(host, "猫源正在运行"); return 1; }
    int exitCode = 1;
    try {
        const std::vector<std::string> input{
            "embedded-node", "--jitless", "--max-old-space-size=192", script, root
        };
        std::vector<std::string> args;
        std::vector<std::string> execArgs;
        // Node/V8 process initialization is performed once. Each subsequent run
        // owns a separate Environment; global stdio/signal handlers are preserved.
        std::call_once(initialization, [&]() {
            auto result = node::InitializeOncePerProcess(input, {
                node::ProcessInitializationFlags::kNoInitializeV8,
                node::ProcessInitializationFlags::kNoInitializeNodeV8Platform,
                node::ProcessInitializationFlags::kNoStdioInitialization,
                node::ProcessInitializationFlags::kNoDefaultSignalHandling,
                node::ProcessInitializationFlags::kNoAdjustResourceLimits
            });
            if (result->early_return()) {
                initializationError = result->errors().empty() ? "Node 初始化失败" : result->errors().front();
                return;
            }
            platform = node::MultiIsolatePlatform::Create(2).release();
            v8::V8::InitializePlatform(platform);
            if (!v8::V8::Initialize()) initializationError = "V8 初始化失败";
        });
        if (!initializationError.empty()) throw std::runtime_error(initializationError);
        // InitializeOncePerProcess parsed this fixed flag set on the first run.
        args = {"embedded-node", script, root};
        execArgs = {"--jitless", "--max-old-space-size=192"};
        std::vector<std::string> errors;
        auto setup = node::CommonEnvironmentSetup::Create(platform, &errors,
            args, execArgs, node::EnvironmentFlags::kNoFlags);
        if (!setup) throw std::runtime_error(errors.empty() ? "Node 环境创建失败" : errors.front());
        auto* isolate = setup->isolate();
        {
            v8::Locker locker(isolate);
            v8::Isolate::Scope isolateScope(isolate);
            v8::HandleScope handles(isolate);
            const auto jsContext = setup->context();
            v8::Context::Scope contextScope(jsContext);
            auto* env = setup->env();
            RegisteredEnvironment registration(env);
            node::SetProcessExitHandler(env, [&host](node::Environment* current, int code) {
                Error(host, "Node 请求退出（" + std::to_string(code) + "）");
                node::Stop(current);
            });
            auto notify = v8::Function::New(jsContext, Notify, v8::External::New(isolate, &host)).ToLocalChecked();
            jsContext->Global()->Set(jsContext,
                v8::String::NewFromUtf8Literal(isolate, "videoNativeNotify"), notify).Check();
            v8::TryCatch caught(isolate);
            const auto bootstrap = "require('node:module').createRequire(" + Quote(script) + ")(" + Quote(script) + ");";
            if (stopRequested) {
                node::Stop(env);
            } else if (node::LoadEnvironment(env, bootstrap).IsEmpty()) {
                v8::String::Utf8Value detail(isolate, caught.Exception());
                Error(host, *detail == nullptr ? "猫源启动失败" : *detail);
                node::Stop(env);
            } else if (stopRequested) node::Stop(env);
            exitCode = node::SpinEventLoop(env).FromMaybe(1);
            if (!stopRequested) Error(host, "Node 服务提前结束（" + std::to_string(exitCode) + "）");
        }
        // setup owns and frees the Environment and loop after leaving its scopes.
    } catch (const std::exception& error) {
        Error(host, error.what());
    } catch (...) {
        Error(host, "猫源运行环境异常");
    }
    {
        std::lock_guard<std::mutex> lock(environmentMutex);
        environment = nullptr;
    }
    running = false;
    return exitCode;
}

void CatNodePrepare()
{
    stopRequested = false;
}

void CatNodeStop()
{
    stopRequested = true;
    std::lock_guard<std::mutex> lock(environmentMutex);
    if (environment != nullptr) node::Stop(environment);
}
