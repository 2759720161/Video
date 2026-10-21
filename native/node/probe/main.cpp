#include "catnode_runtime.h"
#include <cstdio>
#include <string>

struct ProbeOutput { std::string file; };

static void Emit(const char* json, void* context)
{
    auto* output = static_cast<ProbeOutput*>(context);
    // A private state file lets the host inspect readiness without echoing the
    // per-run control token into general device logs.
    FILE* file = fopen(output->file.c_str(), "w");
    if (file == nullptr) return;
    fputs(json, file);
    fclose(file);
}

int main(int argc, char** argv)
{
    if (argc != 3) return 2;
    ProbeOutput output{std::string(argv[2]) + "/probe-state.json"};
    CatNodePrepare();
    return CatNodeRun(argv[1], argv[2], Emit, &output);
}
