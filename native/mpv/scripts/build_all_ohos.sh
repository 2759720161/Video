#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OHOS_NDK="${1:-$HOME/ohos_ndk}"

bash "${SCRIPT_DIR}/build_ffmpeg_ohos.sh" "${OHOS_NDK}"
bash "${SCRIPT_DIR}/build_libmpv_ohos.sh" "${OHOS_NDK}"

echo "MPV_ROOT_BUILD_OK"
