"""Prepare headers matching the pinned Node 24.2.0 runtime."""
import hashlib
import pathlib
import tarfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'native/node/vendor'
NAME = 'node-v24.2.0-headers.tar.gz'
URL = 'https://nodejs.org/dist/v24.2.0/' + NAME
EXPECTED = 'aa5506d209cd9da6e3480ffca5ce9a54ed0ae4e169993d9bd14db18548d801b0'

def main():
    VENDOR.mkdir(parents=True, exist_ok=True)
    archive = VENDOR / NAME
    valid = False
    if archive.exists():
        with archive.open('rb') as stream: valid = hashlib.file_digest(stream, 'sha256').hexdigest() == EXPECTED
    if not valid:
        partial = VENDOR / (NAME + '.download')
        with urllib.request.urlopen(urllib.request.Request(URL, headers={'Range': 'bytes=0-0'}), timeout=30) as response:
            total = int(response.headers['Content-Range'].split('/')[1])
        retries = 0
        while (partial.stat().st_size if partial.exists() else 0) < total:
            start = partial.stat().st_size if partial.exists() else 0
            end = min(total, start + 4 * 1024 * 1024) - 1
            try:
                with urllib.request.urlopen(urllib.request.Request(URL, headers={'Range': f'bytes={start}-{end}'}), timeout=30) as response:
                    if response.status != 206 or response.headers['Content-Range'] != f'bytes {start}-{end}/{total}':
                        raise RuntimeError('Invalid header archive range')
                    with partial.open('ab') as output:
                        remaining = end - start + 1
                        while remaining:
                            data = response.read(min(remaining, 128 * 1024))
                            if not data: raise RuntimeError('Incomplete header archive')
                            output.write(data); remaining -= len(data)
                retries = 0
            except Exception:
                retries += 1
                if retries >= 5: raise
                time.sleep(retries)
        with partial.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != EXPECTED: raise RuntimeError('Node header hash mismatch')
        partial.replace(archive)
    with tarfile.open(archive, 'r:gz') as source: source.extractall(VENDOR, filter='data')
    print('Matching official Node headers verified and extracted')

if __name__ == '__main__': main()
