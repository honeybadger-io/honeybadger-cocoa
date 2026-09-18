# Honeybadger Production Smoke Test

This SwiftPM executable sends real reports through the SDK to the production
Honeybadger API (`https://api.honeybadger.io/v1/notices`).

It reads the API key from `HONEYBADGER_API_KEY` by default and never stores it in
the repo. The sample creates a unique marker/fingerprint, sends a notice, then
waits for the SDK's pending-report file to be removed. Removal means the API
returned a 2xx response.

```shell
HONEYBADGER_API_KEY=YOUR_PROJECT_API_KEY \
swift run HoneybadgerProductionSmoke
```

Useful options:

```shell
swift run HoneybadgerProductionSmoke \
  --api-key YOUR_PROJECT_API_KEY \
  --environment production-smoke \
  --revision "$(git rev-parse --short HEAD)" \
  --wait-seconds 20
```

After a successful run, search the Honeybadger project for the printed marker or
fingerprint, for example `production-smoke-...`.

## Signal Crash + dSYM Smoke

To test the crash handler and server-side dSYM symbolication, use the wrapper
script:

```shell
HONEYBADGER_API_KEY=YOUR_PROJECT_API_KEY \
Examples/ProductionSmokeTest/run_signal_smoke.sh
```

The script:

1. Builds `HoneybadgerProductionSmoke`.
2. Creates `HoneybadgerProductionSmoke.dSYM` with `dsymutil`.
3. Uploads the dSYM with `bin/upload-dsyms.sh`.
4. Runs the sample in `crash` mode, which intentionally crashes with `SIGSEGV`.
5. Relaunches in `replay` mode so the SDK converts and sends the pending signal
   report.

The script prints a unique marker/fingerprint. Search Honeybadger for that
marker. With dSYM upload working, frame zero should symbolicate to
`triggerHoneybadgerProductionSmokeSignalCrash`, the function containing the deliberate bad-memory
access. The fault address remains `0x1`, while frame zero comes from the interrupted machine PC.

Useful options:

```shell
Examples/ProductionSmokeTest/run_signal_smoke.sh \
  --environment production-smoke \
  --revision "$(git rev-parse --short HEAD)" \
  --wait-seconds 45
```

To point everything (dSYM upload and crash reports) at a different API base URL —
the EU stack, or a locally-running collector for end-to-end testing:

```shell
HONEYBADGER_API_KEY=YOUR_PROJECT_API_KEY \
Examples/ProductionSmokeTest/run_signal_smoke.sh --endpoint https://eu-api.honeybadger.io
```

To exercise the crash/replay flow without uploading dSYMs:

```shell
HONEYBADGER_API_KEY=YOUR_PROJECT_API_KEY \
Examples/ProductionSmokeTest/run_signal_smoke.sh --skip-dsym-upload
```

If dSYM upload fails but you still want to verify that the crash report itself
is accepted by the notices API:

```shell
HONEYBADGER_API_KEY=YOUR_PROJECT_API_KEY \
Examples/ProductionSmokeTest/run_signal_smoke.sh --continue-without-dsym
```
