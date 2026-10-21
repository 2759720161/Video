"""Download Node's official source and verify its published SHA-256."""
import concurrent.futures
import hashlib
import pathlib
import re
import tarfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = 'https://nodejs.org/dist/v24.2.0/'
NAME = 'node-v24.2.0.tar.gz'
DEST = ROOT / 'native/node/vendor' / NAME
CACHE = ROOT / 'native/node/source-download-cache'
CHUNK = 8 * 1024 * 1024

def copy_license():
    with tarfile.open(DEST, 'r:gz') as archive:
        license_bytes = archive.extractfile('node-v24.2.0/LICENSE').read()
    (ROOT / 'native/node/LICENSE').write_bytes(license_bytes)
    (ROOT / 'entry/src/main/resources/rawfile/catnode/NODE-LICENSE.txt').write_bytes(license_bytes)

def main():
    with urllib.request.urlopen(BASE + 'SHASUMS256.txt', timeout=30) as response:
        manifest = response.read().decode('utf-8')
    expected = re.search(r'^([0-9a-f]{64})  ' + re.escape(NAME) + '$', manifest, re.M).group(1)
    if DEST.exists():
        with DEST.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() == expected:
                print('Official Node source already verified', flush=True)
                copy_license()
                return
    request = urllib.request.Request(BASE + NAME, headers={'Range': 'bytes=0-0'})
    with urllib.request.urlopen(request, timeout=30) as response:
        total = int(response.headers['Content-Range'].split('/')[1])
    CACHE.mkdir(parents=True, exist_ok=True)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    def fetch(index):
        start, end = index * CHUNK, min(total, (index + 1) * CHUNK) - 1
        part = CACHE / f'{index:03}.part'
        for attempt in range(5):
            present = part.stat().st_size if part.exists() else 0
            if present == end - start + 1:
                return part
            request = urllib.request.Request(BASE + NAME, headers={'Range': f'bytes={start + present}-{end}'})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    if response.status != 206 or response.headers['Content-Range'] != f'bytes {start + present}-{end}/{total}':
                        raise RuntimeError('Invalid source download range')
                    with part.open('ab') as stream:
                        while data := response.read(128 * 1024): stream.write(data)
                if part.stat().st_size == end - start + 1:
                    print(f'Source part {index + 1} ready', flush=True)
                    return part
            except Exception:
                if attempt == 4: raise
                time.sleep(attempt + 1)
        raise RuntimeError('Incomplete source range')
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        parts = list(executor.map(fetch, range((total + CHUNK - 1) // CHUNK)))
    temporary = DEST.with_suffix('.download')
    with temporary.open('wb') as output:
        for part in parts:
            with part.open('rb') as stream:
                while data := stream.read(1024 * 1024): output.write(data)
    with temporary.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
            raise RuntimeError('Official Node source hash mismatch')
    temporary.replace(DEST)
    copy_license()
    (DEST.parent / 'node-source.sha256').write_text(expected + '  ' + NAME + '\n', encoding='utf-8')
    print(f'Official Node source verified: {total} bytes, SHA256 {expected}', flush=True)

if __name__ == '__main__': main()
