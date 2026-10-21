"""Cache an isolated Linux LLVM 19 toolchain from Ubuntu's official archive API.

Downloads run on the Windows host; packages are only extracted under the WSL
user's cache. No system package configuration or maintainer scripts are run.
"""
import concurrent.futures
import hashlib
import json
import pathlib
import subprocess
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / 'native/node/vendor/toolchain'
PACKAGES = ['clang-19', 'llvm-19', 'llvm-19-tools', 'llvm-19-runtime', 'lld-19',
            'libclang-cpp19', 'libllvm19', 'libclang1-19', 'libclang-common-19-dev',
            'python3.12-minimal', 'libpython3.12-minimal', 'libpython3.12-stdlib']
BASE = 'https://api.launchpad.net/devel/ubuntu/+archive/primary'

def fetch_json(url):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                return json.load(response)
        except Exception:
            if attempt == 4: raise
            time.sleep(attempt + 1)

def open_range(url, start, end):
    for attempt in range(5):
        try:
            return urllib.request.urlopen(urllib.request.Request(url,
                headers={'Range': f'bytes={start}-{end}'}), timeout=30)
        except urllib.error.HTTPError as error:
            if error.code == 404: raise
            if attempt == 4: raise
            time.sleep(attempt + 1)
        except Exception:
            if attempt == 4: raise
            time.sleep(attempt + 1)

def complete_archive(file):
    if not file.exists(): return False
    size = file.stat().st_size
    with file.open('rb') as stream:
        if stream.read(8) != b'!<arch>\n': return False
        position = 8
        while position < size:
            header = stream.read(60)
            if len(header) != 60 or header[58:60] != b'`\n': return False
            length = int(header[48:58].strip())
            position += 60 + length + (length % 2)
            if position > size: return False
            stream.seek(position)
    return position == size

def fetch_package(name):
    file = CACHE / (name + '.deb')
    metadata = CACHE / (name + '.json')
    python_package = 'python3.12' in name
    series = 'noble' if python_package else 'resolute'
    parameters = {'ws.op': 'getPublishedBinaries', 'binary_name': name,
        'exact_match': 'true', 'status': 'Published',
        'distro_arch_series': f'https://api.launchpad.net/1.0/ubuntu/{series}/amd64'}
    if python_package: parameters['pocket'] = 'Release'
    query = urllib.parse.urlencode(parameters)
    if metadata.exists():
        previous = json.loads(metadata.read_text(encoding='utf-8'))
        publication = {'binary_package_version': previous['version'], 'self_link': previous['publication']}
        urls = [previous['url']]
    else:
        entries = fetch_json(BASE + '?' + query)['entries']
        if len(entries) != 1:
            raise RuntimeError(f'Expected one pinned Ubuntu publication for {name}')
        publication = entries[0]
        urls = fetch_json(publication['self_link'] + '?ws.op=binaryFileUrls')
    urls = [url for url in urls if url.endswith('.deb')]
    if len(urls) != 1: raise RuntimeError(f'Unexpected package assets for {name}')
    reuse = False
    if file.exists() and metadata.exists():
        previous = json.loads(metadata.read_text(encoding='utf-8'))
        with file.open('rb') as stream: actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        reuse = previous['version'] == publication['binary_package_version'] and actual == previous['sha256'] and complete_archive(file)
    if not reuse:
        temporary = file.with_suffix('.download')
        filename = urllib.parse.urlparse(urls[0]).path.rsplit('/', 1)[-1]
        folder = 'main/p/python3.12/' if python_package else 'universe/l/llvm-toolchain-19/'
        source = 'https://archive.ubuntu.com/ubuntu/pool/' + folder + filename
        try:
            response = open_range(source, 0, 0)
        except urllib.error.HTTPError as error:
            if error.code != 404: raise
            source = source.replace('/pool/universe/', '/pool/main/')
            response = open_range(source, 0, 0)
        with response:
            total = int(response.headers['Content-Range'].split('/')[1])
        if temporary.exists() and temporary.stat().st_size > total: raise RuntimeError('Invalid package partial length')
        failures = 0
        while (temporary.stat().st_size if temporary.exists() else 0) < total:
            offset = temporary.stat().st_size if temporary.exists() else 0
            end = min(total, offset + 4 * 1024 * 1024) - 1
            try:
                with open_range(source, offset, end) as response, temporary.open('ab') as output:
                    if response.status != 206 or response.headers.get('Content-Range') != f'bytes {offset}-{end}/{total}':
                        raise RuntimeError('Compiler archive server ignored the byte range')
                    remaining = end - offset + 1
                    while remaining:
                        data = response.read(min(128 * 1024, remaining))
                        if not data: raise RuntimeError('Incomplete compiler archive range')
                        output.write(data); remaining -= len(data)
                failures = 0
            except Exception:
                failures += 1
                if failures >= 5: raise
                time.sleep(failures)
        if not complete_archive(temporary): raise RuntimeError('Incomplete Debian archive')
        with temporary.open('rb') as stream:
            if stream.read(8) != b'!<arch>\n': raise RuntimeError(f'Invalid Debian archive for {name}')
            stream.seek(0)
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        temporary.replace(file)
        metadata.write_text(json.dumps({'name': name, 'version': publication['binary_package_version'],
            'publication': publication['self_link'], 'url': urls[0], 'sha256': digest}, indent=2) + '\n', encoding='utf-8')
    print(f'Compiler package {name} ready', flush=True)
    return file

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        files = list(executor.map(fetch_package, PACKAGES))
    subprocess.run(['wsl.exe', '-d', 'Ubuntu', '--exec', 'mkdir', '-p', '/home/ljb/.cache/video-node-toolchain'], check=True)
    for file in files:
        linux_path = '/mnt/' + file.drive[0].lower() + '/' + file.as_posix().split(':/', 1)[1]
        subprocess.run(['wsl.exe', '-d', 'Ubuntu', '--exec', 'dpkg-deb', '-x', linux_path,
            '/home/ljb/.cache/video-node-toolchain'], check=True, stderr=subprocess.DEVNULL)
    print('Isolated LLVM toolchain extracted', flush=True)

if __name__ == '__main__': main()
