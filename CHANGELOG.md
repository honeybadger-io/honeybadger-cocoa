# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-07-03
### Breaking
- `resetContext:(NSDictionary*)` changed to `resetContext` (no arguments). Clears context to an empty dictionary. Use `resetContext` + `setContext:` to replace context with a new dictionary. (This API change is why this release is 2.0.0.)
- Minimum deployment targets raised to iOS 16.0 and macOS 13.0 (visionOS 1.0 unchanged).

### Added
- Binary image capture: crash reports include a `binary_images` array with UUID, load address, ASLR slide, and architecture for each loaded Mach-O image, enabling server-side dSYM symbolication.
- Server metadata: payloads include `server.hostname` and `server.pid`.
- dSYM upload script (`bin/upload-dsyms.sh`) for uploading dSYM bundles to Honeybadger. Runs as an Xcode build phase or a manual/CI step. Vendored with the CocoaPods install via `preserve_paths`.
- Configurable `revision` for release tracking: `configure(apiKey:environment:revision:)` reports the value as `server.revision`, and `bin/upload-dsyms.sh` accepts a matching `--revision` option. dSYM-to-crash matching remains UUID-based, so revision is optional.

### Fixed
- Replaced deprecated `NXArchInfo` APIs with `<mach-o/utils.h>` equivalents; the SDK now compiles warning-free (including under `-Werror`).
- Signal crash reports carry the context (`setContext:`) from the crashed process. A JSON snapshot is maintained off the crash path and persisted at crash time; previously context was rebuilt on the next launch, losing user/session IDs for signal crashes.
- Signal crash reports now persist the crashed process's binary images (load addresses, ASLR slides, UUIDs) at crash time. Previously the image list was rebuilt on the next launch, whose ASLR slides differ — so every signal crash symbolicated against the wrong address space.
- Signal handlers run on a dedicated alternate stack (`SA_ONSTACK`); an introspection hook extends the alternate stack to every thread created after `configure`, so stack-overflow crashes — previously uncapturable — are recorded on the configure thread and all later-created threads. (Threads already running at `configure` time cannot be given an alternate stack.)
- The signal-handler entry latch re-arms if the process survives a handled fatal signal, so a co-installed reporter or `SIG_IGN`'d predecessor can no longer permanently disable crash capture.
- `server.hostname` is populated on replayed signal-crash reports (pending reports are now sent after the cached hostname resolves).
- Crash addresses are attributed to a binary image only when they fall inside its recorded `[load_address, load_address + size)` range, and the image table holds 1024 entries (was 512) — addresses in dropped or unmapped ranges are reported unattributed instead of blamed on the nearest image. Signal crash-file format is now v4; stale v3 files are discarded on next launch.
- The shipped SDK no longer exports internal `hb_*` symbols that could collide with a host app's own (`static` restored; tests compile the implementation directly).
- Converted signal reports get unique filenames; a fixed name could clobber a still-unsent earlier report and lose it.
- The exception-captured latch resets if the process survives a capture (e.g. macOS `reportException:` with `NSApplicationCrashOnExceptions` disabled); previously one survived exception silently disabled signal reporting for the process lifetime.
- Hostname is resolved once at configure time on a background queue. `-[NSProcessInfo hostName]` can block on reverse DNS for seconds and previously ran inside the crash handler before the report was persisted.
- The signal handler's own frames (handler + trampoline) are skipped from crash backtraces, so reports group by the faulting frame.
- `bin/upload-dsyms.sh` no longer aborts the whole run (or the enclosing Xcode build) on a transient network error, and exits nonzero when any upload fails so CI can detect it. New `--warn-only` flag preserves exit-0 behavior for build phases. Missing `curl`/`zip`/`python3` fail fast with a clear error.
- Unparseable or stale-format pending crash files are deleted instead of being reprocessed on every launch.
- Thread-safe singleton via `dispatch_once` to prevent potential race conditions.
- Signal handling: replaced non-functional `NSNotificationCenter`-based signal observer with real `sigaction()` handlers for SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP. Previous signal handlers are chained.
- Crash-time persistence: crash reports are written to disk before network transmission, preventing data loss. Pending reports are retried on next launch.
- Exception handler chaining: the previous uncaught exception handler is saved and called after persisting crash data.
- API endpoint corrected from `/v1/notices/js` to `/v1/notices`.
- `details` dictionary (architecture, errorDomain, initialHandler, userInfo) was silently dropped from payloads due to type mismatch in retrieval. Now correctly included.
- Backtrace field names corrected: `line` to `number`, `stack_address` to `address` per API schema.
- JSON serialization uses `NSJSONWritingWithoutEscapingSlashes` instead of manual string replacement. Errors are now captured.
- Removed debug artifact (commented-out ngrok URL).
- HTTP success detection: the SDK now checks the HTTP status code (2xx) rather than just the absence of a transport-level error, preventing crash reports from being deleted when the server returns a 4xx/5xx response.
- Signal crash persistence: signal crash data (`.bin`) is now converted to a JSON report on disk before transmission. If the send fails, the JSON report is retried on next launch rather than lost.
- macOS exception capture: the SDK now hooks `-[NSApplication reportException:]` so that `NSException`s thrown inside AppKit event handlers (e.g. button actions) are captured as proper exception reports. AppKit catches these exceptions in its own event loop, so they never reach `NSUncaughtExceptionHandler` — previously they were missed entirely on macOS. The SDK also registers the `NSApplicationCrashOnExceptions` default (via `registerDefaults:`, so an explicit host-app value still wins) so the app terminates after the crash is recorded rather than continuing in an undefined state.
- Notice payloads are no longer dropped when an `NSError`/`NSException` `userInfo` (carried in `details`) contains values that aren't JSON-serializable — `NSError`, `NSURL`, custom objects, non-finite numbers, etc. Such values are coerced to their string description before serialization, so the report is preserved.
- Signal-handler chaining preserves the original `siginfo_t`/`ucontext_t` for a previously installed `SA_SIGINFO` crash reporter (Crashlytics, Sentry, etc.). Previously the predecessor received a synthetic re-raised signal with no fault address.

## [1.1.0] - 2025-03-24
### Added
- visionOS support

## [1.0.1] - 2023-11-30
### Added
- Added the ability to specify a customer error class.
- Added the ability to specify a custom environment.
- Added the ability to specify a custom fingerprint.

## [0.0.5] - 2023-09-18
### Changed
- Removed unnecessary thread pause.

## [0.0.3] - 2021-07-21
### Changed
- Method signatures have been renamed to be more inline with existing Honeybadger APIs.

## [0.0.2] - 2021-07-21
### Added
- macOS support

## [0.0.1] - 2021-06-20
### Added
- Initial release w/ iOS support only
