"""Cache the target SDK files on WSL ext4 to avoid per-include DrvFS overhead."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

source = Path(sys.argv[1]).resolve()
work = Path(sys.argv[2]).resolve()
inputs = ['oh-uni-package.json', 'compatible_config.json',
          'llvm/include/libcxx-ohos/include/c++/v1/__config']
digest = hashlib.sha256(b''.join((source / name).read_bytes() for name in inputs)).hexdigest()
sdk = work / 'sdk-local' / digest[:16]
marker = sdk / 'sdk-info.json'
build_marker = work / 'build-sdk.sha256'
if build_marker.exists() and build_marker.read_text(encoding='utf-8').strip() != digest:
    raise RuntimeError('SDK changed. Use a fresh Node build directory; existing objects must not be reused across SDK versions.')
if not marker.exists():
    for name in ['sysroot', 'llvm/include/libcxx-ohos', 'llvm/lib/clang/15.0.4', 'llvm/lib/aarch64-linux-ohos']:
        destination = sdk / name
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run(['rsync', '-a', str(source / name) + '/', str(destination) + '/'], check=True)
    marker.write_text(json.dumps({'source': str(source), 'sdkDigest': digest}, indent=2) + '\n', encoding='utf-8')
build_marker.write_text(digest + '\n', encoding='utf-8')
print(sdk)
