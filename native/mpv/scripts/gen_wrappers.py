#!/usr/bin/env python3
r"""Generate clang wrapper scripts for OHOS cross-compilation in WSL.

These wrappers:
1. Add -target aarch64-linux-ohos, --sysroot, -D__MUSL__ automatically
2. Add OHOS multimedia include paths automatically (for OHCodec support)
3. Convert /mnt/* paths to Windows format via wslpath -w
4. Other paths passed through as-is (set TMPDIR=/mnt/d/... before building!)

The caller supplies OHOS_NDK, WRAPPER_DIR and MPV_BUILD_TMPDIR. This keeps the
toolchain fully project-relative and avoids dependencies on reference projects.
"""
import os
import subprocess

WRAPPER_DIR = os.path.abspath(os.environ["WRAPPER_DIR"])
OHOS_NDK_WSL = os.path.abspath(os.path.expanduser(os.environ["OHOS_NDK"]))
PROJECT_TMPDIR_WSL = os.path.abspath(os.environ["MPV_BUILD_TMPDIR"])
OHOS_NDK_WIN_OVERRIDE = os.environ.get("OHOS_NDK_WIN_OVERRIDE", "").strip()
OHOS_NDK_WIN = OHOS_NDK_WIN_OVERRIDE or subprocess.check_output(
    ["wslpath", "-w", OHOS_NDK_WSL], text=True
).strip()
SYSROOT_WIN = OHOS_NDK_WIN + r"\sysroot"
SYSROOT_LIB_WIN = SYSROOT_WIN + r"\usr\lib\aarch64-linux-ohos"
SYSROOT_INC_WIN = SYSROOT_WIN + r"\usr\include"
SYSROOT_ARCH_INC_WIN = SYSROOT_INC_WIN + r"\aarch64-linux-ohos"
MEDIA_INC_WIN = SYSROOT_INC_WIN + r"\multimedia\player_framework"
NATIVE_INC_WIN = SYSROOT_INC_WIN + r"\multimedia\native_avcodec"

os.makedirs(WRAPPER_DIR, exist_ok=True)

# Wrapper: adds OHOS target flags, sysroot, multimedia includes, and converts /mnt/* paths
clang_wrapper = f'''#!/bin/bash
# Wrapper for Windows clang.exe - adds OHOS target flags and converts /mnt/* paths
for arg in "$@"; do
    if [[ "$arg" == "-Wl,--version" ]]; then
        echo "LLD 15.0.4"
        exit 0
    fi
done

has_input=0
has_linker_probe=0
for arg in "$@"; do
    case "$arg" in
        -|*.c|*.cc|*.cpp|*.cxx|*.m|*.mm|*.S|*.s|*.o|*.a|*.so)
            has_input=1
            ;;
        -Wl,*)
            has_linker_probe=1
            ;;
    esac
done
if [[ "$has_linker_probe" == "1" && "$has_input" == "0" ]]; then
    exit 0
fi

mkdir -p "{PROJECT_TMPDIR_WSL}"
STDIN_SRC="{PROJECT_TMPDIR_WSL}/stdin_input.$$.c"
cleanup() {{
    rm -f "$STDIN_SRC"
}}
trap cleanup EXIT

MESON_TEST=0
OUT_WSL=""
prev_is_output=0
for arg in "$@"; do
    if [[ "$prev_is_output" == "1" ]]; then
        OUT_WSL="$arg"
        prev_is_output=0
    elif [[ "$arg" == "-o" ]]; then
        prev_is_output=1
    fi
    case "$arg" in
        */meson-private/tmp*/testfile.c)
            MESON_TEST=1
            ;;
    esac
done

ARGS=()
for arg in "$@"; do
    case "$arg" in
        -)
            : > "$STDIN_SRC"
            win_src=$(wslpath -w "$STDIN_SRC" 2>/dev/null)
            ARGS+=("${{win_src:-$STDIN_SRC}}")
            ;;
        -I/mnt/*)
            inc_path="${{arg#-I}}"
            win_inc=$(wslpath -w "$inc_path" 2>/dev/null)
            ARGS+=("-I${{win_inc:-$inc_path}}")
            ;;
        -L/mnt/*)
            lib_path="${{arg#-L}}"
            win_lib=$(wslpath -w "$lib_path" 2>/dev/null)
            ARGS+=("-L${{win_lib:-$lib_path}}")
            ;;
        /mnt/*)
            win_path=$(wslpath -w "$arg" 2>/dev/null)
            ARGS+=("${{win_path:-$arg}}")
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done
CMD=({OHOS_NDK_WSL}/llvm/bin/clang.exe -target aarch64-linux-ohos --sysroot="{SYSROOT_WIN}" -D__MUSL__ -I"{SYSROOT_INC_WIN}" -I"{SYSROOT_ARCH_INC_WIN}" -I"{MEDIA_INC_WIN}" -I"{NATIVE_INC_WIN}" "${{ARGS[@]}}")
if [[ "$MESON_TEST" == "1" ]]; then
    "${{CMD[@]}}" &
    child=$!
    for _ in {{1..20}}; do
        if ! kill -0 "$child" 2>/dev/null; then
            wait "$child"
            exit $?
        fi
        sleep 1
    done
    kill -9 "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    if [[ -n "$OUT_WSL" && -s "$OUT_WSL" ]]; then
        exit 0
    fi
    exit 124
fi
exec "${{CMD[@]}}"
'''

clangxx_wrapper = f'''#!/bin/bash
# Wrapper for Windows clang++.exe - adds OHOS target flags and converts /mnt/* paths
for arg in "$@"; do
    if [[ "$arg" == "-Wl,--version" ]]; then
        echo "LLD 15.0.4"
        exit 0
    fi
done

has_input=0
has_linker_probe=0
for arg in "$@"; do
    case "$arg" in
        -|*.c|*.cc|*.cpp|*.cxx|*.m|*.mm|*.S|*.s|*.o|*.a|*.so)
            has_input=1
            ;;
        -Wl,*)
            has_linker_probe=1
            ;;
    esac
done
if [[ "$has_linker_probe" == "1" && "$has_input" == "0" ]]; then
    exit 0
fi

mkdir -p "{PROJECT_TMPDIR_WSL}"
STDIN_SRC="{PROJECT_TMPDIR_WSL}/stdin_input.$$.cpp"
cleanup() {{
    rm -f "$STDIN_SRC"
}}
trap cleanup EXIT

MESON_TEST=0
OUT_WSL=""
prev_is_output=0
for arg in "$@"; do
    if [[ "$prev_is_output" == "1" ]]; then
        OUT_WSL="$arg"
        prev_is_output=0
    elif [[ "$arg" == "-o" ]]; then
        prev_is_output=1
    fi
    case "$arg" in
        */meson-private/tmp*/testfile.cpp|*/meson-private/tmp*/testfile.cc|*/meson-private/tmp*/testfile.cxx)
            MESON_TEST=1
            ;;
    esac
done

ARGS=()
for arg in "$@"; do
    case "$arg" in
        -)
            : > "$STDIN_SRC"
            win_src=$(wslpath -w "$STDIN_SRC" 2>/dev/null)
            ARGS+=("${{win_src:-$STDIN_SRC}}")
            ;;
        -I/mnt/*)
            inc_path="${{arg#-I}}"
            win_inc=$(wslpath -w "$inc_path" 2>/dev/null)
            ARGS+=("-I${{win_inc:-$inc_path}}")
            ;;
        -L/mnt/*)
            lib_path="${{arg#-L}}"
            win_lib=$(wslpath -w "$lib_path" 2>/dev/null)
            ARGS+=("-L${{win_lib:-$lib_path}}")
            ;;
        /mnt/*)
            win_path=$(wslpath -w "$arg" 2>/dev/null)
            ARGS+=("${{win_path:-$arg}}")
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done
CMD=({OHOS_NDK_WSL}/llvm/bin/clang++.exe -target aarch64-linux-ohos --sysroot="{SYSROOT_WIN}" -D__MUSL__ -I"{SYSROOT_INC_WIN}" -I"{SYSROOT_ARCH_INC_WIN}" -I"{MEDIA_INC_WIN}" -I"{NATIVE_INC_WIN}" "${{ARGS[@]}}")
if [[ "$MESON_TEST" == "1" ]]; then
    "${{CMD[@]}}" &
    child=$!
    for _ in {{1..20}}; do
        if ! kill -0 "$child" 2>/dev/null; then
            wait "$child"
            exit $?
        fi
        sleep 1
    done
    kill -9 "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    if [[ -n "$OUT_WSL" && -s "$OUT_WSL" ]]; then
        exit 0
    fi
    exit 124
fi
exec "${{CMD[@]}}"
'''

clang_path = os.path.join(WRAPPER_DIR, "ohos-clang")
clangxx_path = os.path.join(WRAPPER_DIR, "ohos-clang++")

with open(clang_path, "w", newline="\n") as f:
    f.write(clang_wrapper)

with open(clangxx_path, "w", newline="\n") as f:
    f.write(clangxx_wrapper)

os.chmod(clang_path, 0o755)
os.chmod(clangxx_path, 0o755)

tool_wrappers = {
    "ohos-ar": "llvm-ar.exe",
    "ohos-nm": "llvm-nm.exe",
    "ohos-ranlib": "llvm-ranlib.exe",
    "ohos-strip": "llvm-strip.exe",
}

for wrapper_name, tool_name in tool_wrappers.items():
    wrapper = f'''#!/bin/bash
# Wrapper for Windows {tool_name} - converts WSL paths to Windows paths.
for arg in "$@"; do
    case "$arg" in
        --version|-V|-v)
            echo "{tool_name} 15.0.4"
            exit 0
            ;;
    esac
done

mkdir -p "{PROJECT_TMPDIR_WSL}"
EMPTY_RSP="{PROJECT_TMPDIR_WSL}/empty_rsp.$$"
: > "$EMPTY_RSP"
cleanup() {{
    rm -f "$EMPTY_RSP"
}}
trap cleanup EXIT

ARGS=()
for arg in "$@"; do
    case "$arg" in
        @/dev/null)
            win_rsp=$(wslpath -w "$EMPTY_RSP" 2>/dev/null)
            ARGS+=("@${{win_rsp:-$EMPTY_RSP}}")
            ;;
        @/mnt/*)
            rsp_path="${{arg#@}}"
            win_rsp=$(wslpath -w "$rsp_path" 2>/dev/null)
            ARGS+=("@${{win_rsp:-$rsp_path}}")
            ;;
        /mnt/*)
            win_path=$(wslpath -w "$arg" 2>/dev/null)
            ARGS+=("${{win_path:-$arg}}")
            ;;
        *)
            if [[ "$arg" == /* && -e "$arg" ]]; then
                win_path=$(wslpath -w "$arg" 2>/dev/null)
                ARGS+=("${{win_path:-$arg}}")
            else
                ARGS+=("$arg")
            fi
            ;;
    esac
done

exec "{OHOS_NDK_WSL}/llvm/bin/{tool_name}" "${{ARGS[@]}}"
'''
    wrapper_path = os.path.join(WRAPPER_DIR, wrapper_name)
    with open(wrapper_path, "w", newline="\n") as f:
        f.write(wrapper)
    os.chmod(wrapper_path, 0o755)
    print(f"Generated: {wrapper_path}")

print(f"Generated: {clang_path}")
print(f"Generated: {clangxx_path}")
