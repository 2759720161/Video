# Cat subscription Node runtime

The application embeds the ARM64 Node runtime and its small host/bootstrap
adapters. It does not bundle a CatVod provider program or a default subscription
URL. The user supplies an `index.js.md5` URL; the application downloads and checks
the corresponding `index.js` before executing it. The existing JSON collection
provider remains available separately.

## Prepare the runtime

Run the Python helpers on Windows with Python 3.11 or newer:

```text
python scripts/prepare-node-source.py
python scripts/prepare-node-headers.py
python scripts/prepare-node-toolchain.py
wsl -d Ubuntu --exec bash /mnt/d/HarmonyOS/DevEcoStudioProjects/Video/native/node/build-runtime.sh
powershell -File scripts/sign-node-runtime.ps1
```

The source and headers are pinned to Node 24.2.0 and verified against the official
SHA-256 manifest. The Windows download helpers use bounded byte ranges and check
that the complete archives arrived. LLVM 19 and Python 3.12 are extracted into a
dedicated WSL cache; this avoids changing the system package installation. The
toolchain helper currently targets Ubuntu `resolute` for LLVM and the `noble`
release pocket for Python, with the WSL cache at `/home/ljb/.cache`. Adapt these
explicit paths for another developer machine.

The build uses the project's existing HarmonyOS SDK sysroot and libc++ headers.
Required SDK headers and ARM64 libraries are cached on WSL ext4 to avoid repeated
DrvFS access. SDK metadata is hashed; a changed SDK requires a fresh Node build
directory rather than reusing objects compiled against another version.
Its compatibility changes are limited to:

- Disable libuv's optional io_uring path under `__OHOS__`; use epoll and normal
  filesystem thread-pool operations.
- Replace the reviewed Ada single-container range algorithms with equivalent
  iterator overloads because this SDK's libc++ does not expose all the required
  C++20 range algorithms in its supported configuration.
- Express V8's array allocation for overwrite as `unique_ptr<T[]>(new T[size])`,
  preserving default initialization with the SDK's older libc++ implementation.
- Overlay three V8 headers for the target compiler: use equivalent iterator
  algorithms for Maglev and ordinary integer binary searches for sorted hashes.
  The host snapshot tools retain their original C++20 implementations.
- Replace Node core range views with ordered vectors, ordinary iteration and a
  comma splitter that retains empty trailing fields. Builtin IDs keep the same
  order and use Node's existing vector-to-V8 conversion.
- Defer Undici's WASM parser creation until an actual HTTP/1 request needs it.
  Node 24.2 eagerly starts it while loading unrelated APIs such as FormData,
  causing an unhandled rejection in jitless mode. This follows newer Undici's
  deferred initialization; it does not add a non-WASM parser.
- Select OpenSSL's POSIX `strerror_r` handling on OpenHarmony's musl libc even
  when GNU feature declarations are enabled for other dependencies.
- Compile with LLVM 19 while retaining the SDK's libc++ and compiler runtime
  headers. Only the ARM intrinsic headers needed for modern BF16 types are
  overlaid from LLVM 19; replacing all SDK builtin headers breaks this libc++.
- Build a genuine shared library with `--shared`, normal dynamic TLS, and
  `-Bsymbolic-functions` to bind Node's own function definitions internally.
- Exclude inspector, npm and Corepack from this application runtime. Core Node
  modules used by the supplied package remain built in.

After compilation, the signing helper applies the SDK's native ELF self-signing,
checks the source build hash and writes a CMake marker containing the signed
library's SHA-256. CMake enables execution only when that marker matches the
actual library. A reference prebuilt library can be cached with
`scripts/prepare-node-runtime.py`, but it does not by itself enable execution.
The module's native strip exclusion for `**/libnode.so.137` is required: the
library is already stripped before signing, and stripping it again while
packaging removes its code signature. Verify the library extracted from the
final HAP, rather than relying on the signature of the input file alone.

Generated source archives, toolchains and libraries are ignored by Git. Recreate
them with the helpers rather than committing the large binaries. The HAP must
contain `libs/arm64-v8a/libnode.so.137`, matching the library's SONAME.
`NODE_BUILD_JOBS` controls build parallelism (default 4). Patched files are only
rewritten when their contents change, allowing interrupted builds to resume.
The pinned source's Node and bundled dependency licenses are preserved in
`native/node/LICENSE` and the packaged `catnode/NODE-LICENSE.txt` resource.

## Runtime boundaries

`catnode_napi.cpp` only includes HarmonyOS Native API headers. The separate
`catnode_runtime.cpp` only includes Node/V8 headers. Their boundary uses strings
and function pointers, never cross-engine `napi_env` values.

Node/V8 process initialization runs once. Each run owns an Environment on a
dedicated 16 MiB-stack thread. The host preserves process-wide standard streams
and signal handlers, installs a controlled `process.exit` handler, and stops the
actual Environment rather than the default libuv loop. Native fatal errors still
affect the application process; a worker thread is not process isolation.
Shutdown waits for the native worker to finish before allowing another startup.
Native environment cleanup also stops its own worker. Ownership changes and
cleanup are synchronized so a retiring Ark environment cannot stop a newer run.

The downloaded program and its profile are stored under a SHA-256 namespace of
the subscription URL in the application's private files directory. The engine
binds to loopback on a discovered port. A separate host bridge provides local
profile persistence, playback-state storage, notifications and explicit failure
responses for unsupported interactive actions. Control requests require a
per-run token. Shutdown requests closure of the engine and host bridge, then
stops the actual Environment. Application teardown can interrupt asynchronous
package cleanup; profile updates are persisted synchronously when received.

## Package and protocol

`CatNodeSubscription` validates HTTP(S) URLs ending in `/index.js.md5`, retaining
their query when deriving `/index.js`. It verifies the downloaded bytes against
the published MD5 and stores a second SHA-256 digest locally. Programs use
versioned filenames; the manifest is replaced atomically only after validation.
Starting a subscription checks its checksum again; an unchanged version reuses
the verified cache. Offline startup can use a rechecked cache. HTTP failures,
invalid checksums and MD5 mismatches are reported instead of silently using stale
data. Saving an existing subscription restarts it and checks for updates.

The bootstrap rechecks both digests before loading the downloaded file. `/config` returns
grouped catalogs (`video.sites`, `music.sites`, etc.). Catalog keys are prefixed
with `nodejs_`, while the actual HTTP routes use the underlying spider key.
The application derives that key from the registered local route.

Video listing and episode UI reuse the existing CatVod views. Full-package mode
retains opaque episode IDs and calls the engine's `/play` method before sending
its URL and headers to the player. Direct collection mode continues to reject
opaque tokens. Stable episode identity is separate from temporary playback URLs.

## Current feature limits

- Runs in `--jitless` mode. The supplied package's Migu danmaku decoder uses
  WebAssembly, which is unavailable in the standard jitless configuration.
  Node's built-in fetch also depends on a WASM parser and is unavailable;
  native `http`/`https` and the package's Axios path use the native parser.
- Web login/sniffing and danmaku push are not yet connected to result-bearing
  application adapters. They return explicit unsupported results.
- Parser pages are not passed to mpv as if they were media streams.
- Provider settings and credentials are shared by spiders within one subscription;
  different subscription URLs have separate profiles. One subscription runs per
  application process at a time; switching subscriptions restarts the environment.
- A valid Node runtime cannot by itself repair unavailable remote providers or
  upstream playback authorization failures.

## Verification

```text
node --test scripts/test-catnode-host.mjs
node --test scripts/test-catnode-client.mjs
node --test scripts/test-catnode-subscription.mjs
node scripts/test-catvod.mjs
node scripts/probe-catnode-desktop.mjs --bundle <downloaded-index.js> --browse
wsl -d Ubuntu -- python3 /mnt/d/HarmonyOS/DevEcoStudioProjects/Video/scripts/test-node-sdk-compat.py /home/ljb/.cache/video-node-v24.2.0
node --jitless scripts/test-node-undici-compat.mjs //wsl.localhost/Ubuntu/home/ljb/.cache/video-node-v24.2.0/node-v24.2.0/deps/undici/undici.js
```

The desktop probe executes the complete original package in a fresh process with
filesystem access restricted to a task-owned temporary directory. It checks the
health endpoint and grouped video catalog. This is distinct from HarmonyOS app
sandbox validation and is not evidence of successful device playback.
Its program fixture is provided explicitly (or from the ignored local vendor
fixture cache), never from packaged application resources.

Device tests live in `entry/src/ohosTest/ets/test/CatNodeRuntime.test.ets`.
They exercise native-module loading/argument validation, failed startup, native
HTTP and crypto, full-package startup/health/catalog, and remote listing/detail/
playback URL resolution. The earlier bundled-program implementation passed all
five on HBN-AL10 on 2026-10-15, including separate UI playback. The subscription
version's device tests now use an explicit remote fixture URL and have not been
rerun because automatic device validation was declined. Run only this suite with a
90-second timeout after installing the app and test HAP:

```text
hdc shell aa test -b com.yingxia.hmos -m entry_test -s unittest OpenHarmonyTestRunner -s class CatNodeRuntimeDevice -s timeout 90000
```

For this workstation, `scripts/build-catnode-debug.ps1 -Target default` (and
`-Target ohosTest`) uses signing material from the ignored local build profile.
It restores the existing build profile byte for byte and preserves a recoverable
backup if another edit occurs during signing. Expired or undecryptable signing
material must be refreshed in DevEco Studio's Signing Configs; the helper does
not create or weaken certificates. A release-signed HAP is not a substitute for
a device-authorized debug package when installing with HDC.

References: [Node embedding API](https://nodejs.org/api/embedding.html),
[OpenHarmony shared-library reference](https://github.com/electerm/ohos-node-shared),
[Undici HTTP parser initialization](https://github.com/nodejs/undici/blob/main/lib/dispatcher/client-h1.js),
[HarmonyOS binary signing](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/binary-sign-tool).
