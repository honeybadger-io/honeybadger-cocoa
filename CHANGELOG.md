# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-05-12
### Added
- Binary image capture: crash reports include a `binary_images` array with UUID, load address, ASLR slide, and architecture for each loaded Mach-O image, enabling server-side dSYM symbolication.
- Server metadata: payloads include `server.hostname` and `server.pid`.
- dSYM upload script (`bin/upload-dsyms.sh`) for uploading dSYM bundles to Honeybadger. Runs as an Xcode build phase or a manual/CI step. Vendored with the CocoaPods install via `preserve_paths`.
- Configurable `revision` for release tracking: `configure(apiKey:environment:revision:)` reports the value as `server.revision`, and `bin/upload-dsyms.sh` accepts a matching `--revision` option. dSYM-to-crash matching remains UUID-based, so revision is optional.

### Changed
- **Breaking**: `resetContext:(NSDictionary*)` changed to `resetContext` (no arguments). Clears context to empty dictionary. The README already documented parameterless usage.

### Fixed
- Thread-safe singleton via `dispatch_once` to prevent potential race conditions.
- Signal handling: replaced non-functional `NSNotificationCenter`-based signal observer with real `sigaction()` handlers for SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP. Previous signal handlers are chained.
- Crash-time persistence: crash reports are written to disk before network transmission, preventing data loss. Pending reports are retried on next launch.
- Exception handler chaining: the previous uncaught exception handler is saved and called after persisting crash data.
- API endpoint corrected from `/v1/notices/js` to `/v1/notices`.
- `details` dictionary (architecture, errorDomain, initialHandler, userInfo) was silently dropped from payloads due to type mismatch in retrieval. Now correctly included.
- Backtrace field names corrected: `line` to `number`, `stack_address` to `address` per API schema.
- JSON serialization uses `NSJSONWritingWithoutEscapingSlashes` instead of manual string replacement. Errors are now captured.
- Removed unreliable `#elif DEBUG` environment detection branch. Default is now `"production"`.
- Removed debug artifact (commented-out ngrok URL).
- HTTP success detection: the SDK now checks the HTTP status code (2xx) rather than just the absence of a transport-level error, preventing crash reports from being deleted when the server returns a 4xx/5xx response.
- Signal crash persistence: signal crash data (`.bin`) is now converted to a JSON report on disk before transmission. If the send fails, the JSON report is retried on next launch rather than lost.
- macOS exception capture: the SDK now hooks `-[NSApplication reportException:]` so that `NSException`s thrown inside AppKit event handlers (e.g. button actions) are captured as proper exception reports. AppKit catches these exceptions in its own event loop, so they never reach `NSUncaughtExceptionHandler` — previously they were missed entirely on macOS. The SDK also registers the `NSApplicationCrashOnExceptions` default (via `registerDefaults:`, so an explicit host-app value still wins) so the app terminates after the crash is recorded rather than continuing in an undefined state.
- Notice payloads are no longer dropped when an `NSError`/`NSException` `userInfo` (carried in `details`) contains values that aren't JSON-serializable — `NSError`, `NSURL`, custom objects, non-finite numbers, etc. Such values are coerced to their string description before serialization, so the report is preserved.

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
