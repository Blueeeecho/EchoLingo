# EchoLingo offline translation worker

This independent IPC wrapper embeds the pinned Mozilla Translations native CPU
inference library. It has no HTTP client, model downloader or credential access.
Model downloads and the app's provider selection belong to separate build/app
code. The two directions are loaded lazily and retained only in this process.

## Build

Use CMake 3.31.6, Python 3.9+ and a C++17 compiler. On Windows run in an x64 MSVC
developer environment with Ninja available:

```powershell
python scripts/offline-engine/build.py --work-dir C:\build\echolingo-engine --output-dir resources/offline-translation/bin --generator Ninja --jobs 4
```

On macOS, Xcode Command Line Tools and CMake are sufficient; omit `--generator`
to use Unix Makefiles. `--cmake /absolute/path/to/cmake` selects an isolated CMake
installation. Source downloads are checked against `sources.lock.json` before
extraction. No model is downloaded by this script. `--prepare-only` prepares
source without compiling.

To rebuild from the separate source-offer archive without downloading sources,
pass `--prepared-source /absolute/path/to/source-root`. That root contains
`translations-69455acaecbe8650cdba988dbcf7c10ca20e7c48`, `pcre2-10.46` and
`nlohmann-json` as siblings. This wrapper directory and lock file must also be
the copies from that same source offer.

Native Windows generic code uses upstream's `BUILD_ARCH=core2` mapping rather
than its default AVX2-wide build. INTGEMM/Ruy retain their CPU-dispatched kernels.
The application must still check its supported CPU requirements before starting
the worker; a successful build on one CI machine is not evidence for every CPU.

## Protocol

Start `echolingo-offline-engine[.exe] --model-root /absolute/path/to/models`.
Add `--once` for one request followed by exit. Otherwise it processes JSON lines
until stdin closes. `--version` prints the wrapper protocol and upstream commit.

```json
{"id":"request-1","source":"en","target":"zh","text":"Hello world."}
```

Successful stdout is one JSON line with the same string ID:

```json
{"id":"request-1","text":"你好,世界。"}
```

Errors contain `id`, `code` and a generic `error`, without submitted text or
filesystem paths. Valid direction IDs are exactly `en`→`zh` and `zh`→`en`.
Input lines are bounded to 256 KiB, source text to 80,000 UTF-8 bytes and output
text to 256 KiB. The parent enforces its user-facing character count, timeout,
request cancellation and worker termination. No automatic retry occurs here.
Windows uses wide argv and filesystem reads into aligned model memory, avoiding
the upstream narrow CRT file loader for non-ASCII installation paths.

The model root has `en-zh` and `zh-en` subdirectories with the exact official
decompressed filenames recorded in `resources/offline-translation/manifest.json`.
No nonbreaking-prefix dataset is loaded. Explicit newlines, CRLF, indentation,
empty lines and common list/heading markers are preserved outside the model.
The model can still mistranslate technical identifiers and terminology; this is
a basic offline translator, not a guarantee of API-model quality.

## Upstream and source changes

The Mozilla commit and all source dependencies are pinned in `sources.lock.json`.
The engine/model license is MPL-2.0; PCRE2, SentencePiece, Ruy, INTGEMM, CPUINFO,
SIMD utilities and nlohmann JSON have their own retained notices. The package's
third-party notices and source offer supply the exact license texts.

`build.py` makes four explicit compatibility changes in the supplied upstream
source: a fixed revision header instead of reading a nonexistent archive `.git`,
a non-constexpr tokenizer sentinel accepted by modern Clang, and an explicit
`fenv.h` include in the SIMD helper; compiler-specific diagnostics around Ruy's
third-party declarations suppress MSVC's zero-point conversion warning only for
those headers while preserving Marian's `/W4 /WX`. These modified files are
included in the source offer. No model weights are modified.
