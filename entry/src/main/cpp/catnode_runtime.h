#pragma once

// This boundary carries bytes and function pointers, never either engine's napi_env.
using CatNodeEmit = void (*)(const char* json, void* context);
int CatNodeRun(const char* script, const char* root, CatNodeEmit emit, void* context);
void CatNodePrepare();
void CatNodeStop();
