"""Fetch the pinned OpenHarmony runtime with verified, resumable range downloads."""
import concurrent.futures
import hashlib
import pathlib
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
URL = 'https://github.com/electerm/ohos-node-shared/releases/download/ohos-node-shared-v24.2.0/libnode-arm64.so'
SHA256 = '3019bf5f9a279d98a87606fc13c53b0e797b6a50cf174f8a1243d880c71151a1'
TOTAL = 126809264
CHUNK = 8 * 1024 * 1024
DEST = ROOT / 'native/node/dist/lib/arm64-v8a/libnode.so'
PARTS = ROOT / 'native/node/download-cache'

def digest(file):
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def fetch_part(index):
    start = index * CHUNK
    end = min(TOTAL, start + CHUNK) - 1
    part = PARTS / f'{index:03}.part'
    for attempt in range(5):
        present = part.stat().st_size if part.exists() else 0
        if present == end - start + 1:
            return part
        if present > end - start + 1:
            raise RuntimeError('Invalid partial download length')
        request = urllib.request.Request(URL, headers={
            'Range': f'bytes={start + present}-{end}',
            'User-Agent': 'Video-Node-Runtime-Preparation/1.0'
        })
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                expected = f'bytes {start + present}-{end}/{TOTAL}'
                if response.status != 206 or response.headers.get('Content-Range') != expected:
                    raise RuntimeError('Server did not honor the verified byte range')
                with part.open('ab') as stream:
                    while data := response.read(128 * 1024):
                        stream.write(data)
            if part.stat().st_size == end - start + 1:
                print(f'Runtime part {index + 1}/{(TOTAL + CHUNK - 1) // CHUNK} ready', flush=True)
                return part
        except Exception as error:
            if attempt == 4:
                raise RuntimeError(f'Runtime part {index} failed: {type(error).__name__}') from error
            time.sleep(attempt + 1)
    raise RuntimeError('Incomplete runtime part')

def main():
    if DEST.exists() and digest(DEST) == SHA256:
        print('Pinned runtime already verified', flush=True)
        return
    DEST.parent.mkdir(parents=True, exist_ok=True)
    PARTS.mkdir(parents=True, exist_ok=True)
    count = (TOTAL + CHUNK - 1) // CHUNK
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        parts = list(executor.map(fetch_part, range(count)))
    temporary = DEST.with_suffix('.verified-download')
    with temporary.open('wb') as output:
        for part in parts:
            with part.open('rb') as stream:
                while data := stream.read(1024 * 1024):
                    output.write(data)
    if temporary.stat().st_size != TOTAL or digest(temporary) != SHA256:
        raise RuntimeError('Runtime SHA-256 verification failed; not installed')
    temporary.replace(DEST)
    print(f'Pinned ARM64 runtime verified: {TOTAL} bytes', flush=True)

if __name__ == '__main__':
    main()
