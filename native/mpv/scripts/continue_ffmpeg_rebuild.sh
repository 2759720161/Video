#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPV_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${MPV_ROOT}/ffmpeg-src"
PREFIX="${MPV_ROOT}/prebuilt/ffmpeg"
CCW="${MPV_ROOT}/build/wrappers/ohos-clang"
ARW="${MPV_ROOT}/build/wrappers/ohos-ar"

cd "${SRC}"
[ "$(pwd -P)" = "${SRC}" ]

# Only generated build files are removed. Source and configuration are kept.
# SKIP_MAIN_BUILD is useful after the main archives already compiled and only
# one of the manually enabled OHCodec translation units needs another pass.
if [ "${SKIP_MAIN_BUILD:-0}" != "1" ]; then
    find . -type f -name '*.d' -delete
    make clean
    make -j"$(nproc)"
fi

"${CCW}" -fPIC -O2 -flto -c -I. -Ilibavutil \
    -o libavutil/hwcontext_oh.o libavutil/hwcontext_oh.c
"${ARW}" rcs libavutil/libavutil.a libavutil/hwcontext_oh.o

"${CCW}" -fPIC -O2 -c -I. -Ilibavcodec -Ilibavutil \
    -o libavcodec/ohcodec.o libavcodec/ohcodec.c
"${CCW}" -fPIC -O2 -c -I. -Ilibavcodec -Ilibavutil \
    -o libavcodec/ohdec.o libavcodec/ohdec.c
"${ARW}" rcs libavcodec/libavcodec.a libavcodec/ohcodec.o libavcodec/ohdec.o

mkdir -p "${PREFIX}/lib" "${PREFIX}/include"
for lib in libavutil libswresample libswscale libavcodec libavformat libavfilter; do
    cp -f "${SRC}/${lib}/${lib}.a" "${PREFIX}/lib/"
    if [ "${SKIP_MAIN_BUILD:-0}" != "1" ]; then
        mkdir -p "${PREFIX}/include/${lib}"
        cp -f "${SRC}/${lib}/"*.h "${PREFIX}/include/${lib}/"
    fi
done

echo FFMPEG_CONTINUE_OK
