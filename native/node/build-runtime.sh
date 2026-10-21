#!/usr/bin/env bash
set -euo pipefail

# Run in Ubuntu/WSL after scripts/prepare-node-source.py. The build stays on ext4.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NODE_WORK_DIR="${HOME}/.cache/video-node-v24.2.0"
NODE_SDK_NATIVE="${1:-/mnt/d/HarmonyOS/API26/DevEco Studio/sdk/default/openharmony/native}"
NODE_TOOLCHAIN="${HOME}/.cache/video-node-toolchain"
mkdir -p "${NODE_WORK_DIR}/wrappers" "${NODE_WORK_DIR}/intrinsic-headers"
for header in arm_neon.h arm_bf16.h arm_sve.h arm_vector_types.h; do
    ln -sfn "${NODE_TOOLCHAIN}/usr/lib/llvm-19/lib/clang/19/include/${header}" "${NODE_WORK_DIR}/intrinsic-headers/${header}"
done
exec >"${NODE_WORK_DIR}/build.log" 2>&1
if [[ ! -f "${NODE_WORK_DIR}/node-v24.2.0/configure" ]]; then
    tar -xzf "${PROJECT_ROOT}/native/node/vendor/node-v24.2.0.tar.gz" -C "${NODE_WORK_DIR}"
fi
NODE_SDK_LOCAL="$(python3 "${PROJECT_ROOT}/scripts/cache-node-sdk.py" "${NODE_SDK_NATIVE}" "${NODE_WORK_DIR}")"
ln -sfn "${NODE_SDK_LOCAL}" "${NODE_WORK_DIR}/sdk"
export NODE_WORK_DIR
python3 - <<'PY'
import os, re
from pathlib import Path
root = Path(os.environ['NODE_WORK_DIR']) / 'node-v24.2.0'
def write_changed(path, value):
    if not path.exists() or path.read_text(encoding='utf-8') != value:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding='utf-8')
linux = root / 'deps/uv/src/unix/linux.c'
text = linux.read_text(encoding='utf-8')
original = '#if defined(__ANDROID_API__)\n  return 0;  /* Possibly available but blocked by seccomp. */'
replacement = '#if defined(__ANDROID_API__) || defined(__OHOS__)\n  return 0;  /* App sandbox: use epoll and the filesystem thread pool. */'
if original in text:
    linux.write_text(text.replace(original, replacement, 1), encoding='utf-8')
elif replacement not in text:
    raise RuntimeError('Unexpected libuv source; sandbox patch was not applied')
# This SDK's libc++ 15 exposes ranges but lacks its C++20 algorithms. Ada only
# uses single-container algorithms here; preserve their predicates and ordering
# with the equivalent standard iterator overloads instead of adding std symbols.
pattern = re.compile(r'std::ranges::(replace|find_if_not|find_if|stable_sort|any_of|all_of)\(\s*(\*?[A-Za-z_][A-Za-z_0-9]*(?:\.value\(\))?)\s*,')
for name in ['ada.h', 'ada.cpp']:
    ada = root / 'deps/ada' / name
    value = ada.read_text(encoding='utf-8')
    def iterator_algorithm(match):
        container = '(' + match.group(2) + ')'
        return 'std::' + match.group(1) + '(' + container + '.begin(), ' + container + '.end(),'
    value = pattern.sub(iterator_algorithm, value)
    if 'std::ranges::' in value:
        raise RuntimeError('Unreviewed Ada range algorithm requires explicit porting')
    write_changed(ada, value)
vector = root / 'deps/v8/src/base/vector.h'
value = vector.read_text(encoding='utf-8')
value = value.replace('std::make_unique_for_overwrite<T[]>(size)', 'std::unique_ptr<T[]>(new T[size])')
write_changed(vector, value)
openssl = root / 'deps/openssl/openssl/crypto/o_str.c'
value = openssl.read_text(encoding='utf-8')
value = value.replace('#elif defined(_GNU_SOURCE)\n    char *err;', '#elif defined(_GNU_SOURCE) && !defined(__OHOS__)\n    char *err;')
value = value.replace('#elif (defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE >= 200112L)', '#elif defined(__OHOS__) || (defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE >= 200112L)')
write_changed(openssl, value)
# Keep target-only SDK adaptations separate from host tools. Both lower_bound
# calls search integer indices projected to sorted hashes. An ordinary binary
# search preserves the first >= hash result, including the end sentinel.
overlay = Path(os.environ['NODE_WORK_DIR']) / 'compat-headers'
lower_bound = re.compile(
    r'  int (number|i) = \*std::ranges::lower_bound\(std::views::iota\(0, end\), hash,'
    r'\s*std::less<>\(\), \[&\]\(int i\) \{\s*Tagged<Name> entry = (GetSortedKey|GetKey)\(i\);'
    r'\s*return entry->hash\(\);\s*\}\);')
for name, expected_variable, expected_getter in [
    ('objects/descriptor-array-inl.h', 'number', 'GetSortedKey'),
    ('objects/transitions-inl.h', 'i', 'GetKey')
]:
    original = (root / 'deps/v8/src' / name).read_text(encoding='utf-8')
    matches = list(lower_bound.finditer(original))
    if len(matches) != 1 or matches[0].groups() != (expected_variable, expected_getter):
        raise RuntimeError('Unexpected V8 binary search source: ' + name)
    replacement = f'''  int {expected_variable} = 0;
  int search_upper = end;
  while ({expected_variable} < search_upper) {{
    const int middle = {expected_variable} + (search_upper - {expected_variable}) / 2;
    if ({expected_getter}(middle)->hash() < hash) {{
      {expected_variable} = middle + 1;
    }} else {{
      search_upper = middle;
    }}
  }}'''
    write_changed(overlay / 'src' / name, lower_bound.sub(replacement, original))
maglev = 'maglev/maglev-inlining.h'
value = (root / 'deps/v8/src' / maglev).read_text(encoding='utf-8')
for algorithm in ['find_if', 'max_element']:
    pattern = re.compile(r'std::ranges::' + algorithm + r'\(\s*graph_->inlineable_calls\(\),')
    value, count = pattern.subn('std::' + algorithm + '(graph_->inlineable_calls().begin(), graph_->inlineable_calls().end(),', value)
    if count != 1:
        raise RuntimeError('Unexpected V8 inlining algorithm: ' + algorithm)
if 'std::ranges::' in value:
    raise RuntimeError('Unreviewed V8 range algorithm')
write_changed(overlay / 'src' / maglev, value)
PY
python3 "${PROJECT_ROOT}/scripts/prepare-node-sdk-compat.py" "${NODE_WORK_DIR}"

cat > "${NODE_WORK_DIR}/wrappers/cc" <<EOF
#!/usr/bin/env bash
exec env LD_LIBRARY_PATH="${NODE_TOOLCHAIN}/usr/lib/x86_64-linux-gnu" "${NODE_TOOLCHAIN}/usr/bin/clang-19" --target=aarch64-linux-ohos --sysroot="${NODE_WORK_DIR}/sdk/sysroot" -resource-dir="${NODE_WORK_DIR}/sdk/llvm/lib/clang/15.0.4" -isystem "${NODE_WORK_DIR}/intrinsic-headers" -D__OHOS__ -fno-emulated-tls -fPIC -L"${NODE_WORK_DIR}/sdk/llvm/lib/aarch64-linux-ohos" -B"${NODE_TOOLCHAIN}/usr/lib/llvm-19/bin" -fuse-ld=lld -Wno-unused-command-line-argument "\$@"
EOF
cat > "${NODE_WORK_DIR}/wrappers/cxx" <<EOF
#!/usr/bin/env bash
exec env LD_LIBRARY_PATH="${NODE_TOOLCHAIN}/usr/lib/x86_64-linux-gnu" "${NODE_TOOLCHAIN}/usr/bin/clang++-19" --target=aarch64-linux-ohos --sysroot="${NODE_WORK_DIR}/sdk/sysroot" -resource-dir="${NODE_WORK_DIR}/sdk/llvm/lib/clang/15.0.4" -D__OHOS__ -fno-emulated-tls -fPIC -stdlib=libc++ -I"${NODE_WORK_DIR}/compat-headers" -isystem "${NODE_WORK_DIR}/sdk/llvm/include/libcxx-ohos/include/c++/v1" -isystem "${NODE_WORK_DIR}/intrinsic-headers" -L"${NODE_WORK_DIR}/sdk/llvm/lib/aarch64-linux-ohos" -B"${NODE_TOOLCHAIN}/usr/lib/llvm-19/bin" -fuse-ld=lld -Wno-unused-command-line-argument "\$@"
EOF
chmod +x "${NODE_WORK_DIR}/wrappers/cc" "${NODE_WORK_DIR}/wrappers/cxx"
export CC="${NODE_WORK_DIR}/wrappers/cc"
export CXX="${NODE_WORK_DIR}/wrappers/cxx"
export CC_host=gcc CXX_host=g++
export AR="${NODE_TOOLCHAIN}/usr/bin/llvm-ar-19" NM="${NODE_TOOLCHAIN}/usr/bin/llvm-nm-19" RANLIB="${NODE_TOOLCHAIN}/usr/bin/llvm-ranlib-19"
export LD="${NODE_TOOLCHAIN}/usr/bin/ld.lld-19"
export LD_LIBRARY_PATH="${NODE_TOOLCHAIN}/usr/lib/x86_64-linux-gnu"
export LDFLAGS="-Wl,-Bsymbolic-functions"
export CFLAGS="-D_GNU_SOURCE"
export CXXFLAGS="-D_GNU_SOURCE"
export PYTHONHOME="${NODE_TOOLCHAIN}/usr"
export PYTHON="${NODE_TOOLCHAIN}/usr/bin/python3.12"
cd "${NODE_WORK_DIR}/node-v24.2.0"
    "${PYTHON}" configure.py --dest-cpu=arm64 --dest-os=openharmony --cross-compiling --use_clang \
        --openssl-no-asm --shared --without-npm --without-corepack --without-inspector
make -C out BUILDTYPE=Release V=0 -j"${NODE_BUILD_JOBS:-4}" libnode
NODE_LIB="$(find out/Release -maxdepth 2 -type f -name 'libnode.so*' | head -1)"
if [[ -z "${NODE_LIB}" ]]; then echo 'Shared Node output not found' >&2; exit 1; fi
mkdir -p "${PROJECT_ROOT}/native/node/dist/patched" "${PROJECT_ROOT}/entry/libs/arm64-v8a"
cp "${NODE_LIB}" "${PROJECT_ROOT}/native/node/dist/patched/libnode.so.137"
"${NODE_TOOLCHAIN}/usr/bin/llvm-strip-19" --strip-unneeded "${PROJECT_ROOT}/native/node/dist/patched/libnode.so.137"
export NODE_PROJECT_ROOT="${PROJECT_ROOT}"
"${PYTHON}" - <<'PY'
import hashlib, json, os
from pathlib import Path
project = Path(os.environ['NODE_PROJECT_ROOT'])
library = project / 'native/node/dist/patched/libnode.so.137'
data = {'nodeVersion': '24.2.0', 'ioUringDisabled': True, 'symbolicFunctions': True,
        'sdkDigest': (Path(os.environ['NODE_WORK_DIR']) / 'build-sdk.sha256').read_text(encoding='utf-8').strip(),
        'sha256': hashlib.sha256(library.read_bytes()).hexdigest()}
(library.parent / 'build-info.json').write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
PY
echo 'Patched Node library ready for native signing.'
