#!/bin/bash
# build_libmpv_ohos.sh - Cross-compile libmpv for HarmonyOS NEXT (aarch64)
# Run in WSL with NTFS metadata enabled
#
# Prerequisites: FFmpeg already built, meson, ninja, pkg-config
#
# Usage:
#   ./build_libmpv_ohos.sh [OHOS_NDK_PATH] [FFMPEG_PREFIX] [DEPS_PREFIX] [STAGE_PREFIX]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPV_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OHOS_NDK="${1:-$HOME/ohos_ndk}"
FFMPEG_PREFIX="${2:-${MPV_ROOT}/prebuilt/ffmpeg}"
DEPS_PREFIX="${3:-${MPV_ROOT}/prebuilt/deps}"
STAGE_PREFIX="${4:-${MPV_ROOT}/build/install}"
DIST_DIR="${MPV_ROOT}/dist"
JOBS=$(nproc)
MPV_SRC="${MPV_ROOT}/src"

WRAPPER_DIR="${MPV_ROOT}/build/wrappers"
mkdir -p "${WRAPPER_DIR}"
export OHOS_NDK WRAPPER_DIR MPV_BUILD_TMPDIR="${MPV_ROOT}/build/tmp"

wsl_to_win() {
    # Keep explicit /mnt/<drive>/ paths logical; resolving aliases can bring
    # spaces from the DevEco Studio installation path back into clang args.
    if [[ "$1" =~ ^/mnt/([a-zA-Z])/(.*)$ ]]; then
        local drive="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]}"
        drive="${drive^^}"
        rest="${rest//\\/}"
        rest="${rest//\//\\}"
        printf '%s' "${drive}:\\${rest}"
    else
        wslpath -w "$1" 2>/dev/null || echo "$1"
    fi
}

OHOS_NDK_WIN=$(wsl_to_win "${OHOS_NDK}")
SYSROOT_WIN=$(wsl_to_win "${OHOS_NDK}/sysroot")
SYSROOT_LIB_WIN=$(wsl_to_win "${OHOS_NDK}/sysroot/usr/lib/aarch64-linux-ohos")
export OHOS_NDK_WIN_OVERRIDE="${OHOS_NDK_WIN}"
FFMPEG_WIN=$(wsl_to_win "${FFMPEG_PREFIX}")
DEPS_WIN=$(wsl_to_win "${DEPS_PREFIX}")

echo "=== libmpv Cross-Compile for HarmonyOS NEXT ==="
echo "NDK (Win):     ${OHOS_NDK_WIN}"
echo "Sysroot (Win): ${SYSROOT_WIN}"
echo "FFmpeg:        ${FFMPEG_PREFIX}"
echo "mpv src:       ${MPV_SRC}"
echo "Stage:         ${STAGE_PREFIX}"
echo "Distribution:  ${DIST_DIR}"
echo "Jobs:          ${JOBS}"

[ ! -d "${OHOS_NDK}" ] && { echo "ERROR: NDK not found"; exit 1; }
[ ! -d "${FFMPEG_PREFIX}/lib" ] && { echo "ERROR: FFmpeg not found at ${FFMPEG_PREFIX} - run build_ffmpeg_ohos.sh first"; exit 1; }

# Generate wrapper scripts (same as FFmpeg build)
python3 "${SCRIPT_DIR}/gen_wrappers.py"

CC_WRAPPER="${WRAPPER_DIR}/ohos-clang"
CXX_WRAPPER="${WRAPPER_DIR}/ohos-clang++"

# pkg-config output is consumed by Meson's Python process.  The project lives
# under a Chinese directory name, while WSL's sed/pkg-config combination
# escaped those UTF-8 bytes in .pc files.  Give pkg-config stable ASCII
# symlinks instead, and fix any copied stale prefix at the same time.
PKG_LINK_ROOT="${WRAPPER_DIR}/video_native"
mkdir -p "${PKG_LINK_ROOT}"
ln -sfn "${FFMPEG_PREFIX}" "${PKG_LINK_ROOT}/ffmpeg"
ln -sfn "${DEPS_PREFIX}" "${PKG_LINK_ROOT}/deps"
FFMPEG_PKG_PREFIX="${PKG_LINK_ROOT}/ffmpeg"
DEPS_PKG_PREFIX="${PKG_LINK_ROOT}/deps"
export PKG_CONFIG_PATH="${FFMPEG_PKG_PREFIX}/lib/pkgconfig:${DEPS_PKG_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH}"
unset PKG_CONFIG_SYSROOT_DIR

# The copied native tree can contain .pc files generated in another project.
# Meson follows prefix values in copied .pc files. Normalize them to this
# project-owned native module before configuring.
for pc in "${FFMPEG_PKG_PREFIX}"/lib/pkgconfig/*.pc "${DEPS_PKG_PREFIX}"/lib/pkgconfig/*.pc; do
    [ -f "${pc}" ] || continue
    if [[ "${pc}" == "${FFMPEG_PKG_PREFIX}"/* ]]; then
        sed -i "s|^prefix=.*$|prefix=${FFMPEG_PKG_PREFIX}|" "${pc}"
    else
        sed -i "s|^prefix=.*$|prefix=${DEPS_PKG_PREFIX}|" "${pc}"
    fi
done

[ ! -f "${MPV_SRC}/meson.build" ] && {
    echo "ERROR: dex2oat/mpv source not found at ${MPV_SRC}"
    exit 1
}

cd "${MPV_SRC}"

AR_PATH="${WRAPPER_DIR}/ohos-ar"
NM_PATH="${WRAPPER_DIR}/ohos-nm"
RANLIB_PATH="${WRAPPER_DIR}/ohos-ranlib"
STRIP_PATH="${WRAPPER_DIR}/ohos-strip"
PKG_CONFIG_BIN=$(which pkg-config)

echo "Creating meson cross file..."

cat > ohos_cross.txt << CROSSFILE
[binaries]
c = '${CC_WRAPPER}'
cpp = '${CXX_WRAPPER}'
ar = '${AR_PATH}'
nm = '${NM_PATH}'
ranlib = '${RANLIB_PATH}'
strip = '${STRIP_PATH}'
pkg-config = '${PKG_CONFIG_BIN}'

[built-in options]
c_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${FFMPEG_PREFIX}/include', '-I${DEPS_PREFIX}/include', '-I${DEPS_PREFIX}/include/freetype2']
c_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${FFMPEG_WIN}\\lib', '-L${DEPS_WIN}\\lib', '-L${SYSROOT_LIB_WIN}', '-lavformat', '-lavcodec', '-lavfilter', '-lswresample', '-lswscale', '-lavutil', '-lmbedtls', '-lmbedx509', '-lmbedcrypto', '-lnative_media_venc', '-lm', '-lc', '-lpthread']
cpp_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-D__MUSL__', '-fPIC', '-O2', '-I${FFMPEG_PREFIX}/include', '-I${DEPS_PREFIX}/include', '-I${DEPS_PREFIX}/include/freetype2']
cpp_link_args = ['-target', 'aarch64-linux-ohos', '--sysroot=${SYSROOT_WIN}', '-L${FFMPEG_WIN}\\lib', '-L${DEPS_WIN}\\lib', '-L${SYSROOT_LIB_WIN}', '-lavformat', '-lavcodec', '-lavfilter', '-lswresample', '-lswscale', '-lavutil', '-lmbedtls', '-lmbedx509', '-lmbedcrypto', '-lnative_media_venc', '-lm', '-lc', '-lpthread']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
CROSSFILE

echo "Cross file contents:"
cat ohos_cross.txt

echo "Configuring mpv with meson..."

rm -rf build/
meson setup build/ \
    --cross-file ohos_cross.txt \
    --prefix="${STAGE_PREFIX}" \
    --default-library=shared \
    -Dlibmpv=true \
    -Dcplayer=false \
    -Dbuild-date=false \
    -Dohos=enabled \
    -Degl-ohos=enabled \
    -Dgl=enabled \
    -Degl=disabled \
    -Degl-android=disabled \
    -Degl-angle=disabled \
    -Dvulkan=disabled \
    -Dwayland=disabled \
    -Ddmabuf-wayland=disabled \
    -Dx11=disabled \
    -Dd3d11=disabled \
    -Dd3d-hwaccel=disabled \
    -Ddirect3d=disabled \
    -Dcocoa=disabled \
    -Ddrm=disabled \
    -Dgbm=disabled \
    -Dcaca=disabled \
    -Dsixel=disabled \
    -Dvapoursynth=disabled \
    -Dlua=disabled \
    -Djavascript=disabled \
    -Dsdl2-audio=disabled \
    -Dsdl2-video=disabled \
    -Dsdl2-gamepad=disabled \
    -Dsndio=disabled \
    -Dpulse=disabled \
    -Dalsa=disabled \
    -Djack=disabled \
    -Dopensles=disabled \
    -Daudiounit=disabled \
    -Dcoreaudio=disabled \
    -Dwasapi=disabled \
    -Ddvdnav=disabled \
    -Dcdda=disabled \
    -Duchardet=disabled \
    -Drubberband=disabled \
    -Dlcms2=disabled \
    -Dzimg=disabled \
    -Dvdpau=disabled \
    -Dvaapi=disabled \
    -Dlibavdevice=disabled \
    -Diconv=disabled \
    -Djpeg=disabled \
    -Dlibarchive=disabled \
    -Dlibbluray=disabled

echo "Building mpv..."
ninja -C build/ -j${JOBS}

echo "Installing mpv..."
ninja -C build/ install

echo "Copying headers..."
mkdir -p "${STAGE_PREFIX}/include/mpv"
if [ -f include/mpv/client.h ]; then
    cp include/mpv/client.h include/mpv/render.h include/mpv/render_gl.h include/mpv/stream_cb.h \
        "${STAGE_PREFIX}/include/mpv/"
else
    cp libmpv/mpv/client.h libmpv/mpv/render.h libmpv/mpv/render_gl.h libmpv/mpv/stream_cb.h \
        "${STAGE_PREFIX}/include/mpv/"
fi

echo "=== libmpv build complete ==="
mkdir -p "${DIST_DIR}/lib/arm64-v8a" "${DIST_DIR}/include/mpv"
cp -f "${STAGE_PREFIX}/lib/libmpv.so" \
    "${DIST_DIR}/lib/arm64-v8a/libmpv.so"
cp -f "${STAGE_PREFIX}/include/mpv/"*.h "${DIST_DIR}/include/mpv/"
ls -la "${DIST_DIR}/lib/arm64-v8a/"
ls -la "${DIST_DIR}/include/mpv/"
