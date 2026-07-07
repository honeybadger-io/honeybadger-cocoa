#!/bin/bash
#
# upload-dsyms.sh
#
# Uploads dSYM bundles to Honeybadger for server-side symbolication.
# Can be used as an Xcode build phase or CI step.
#
# Usage:
#   ./bin/upload-dsyms.sh --api-key <key> [--dsym-path <path>] [--revision <revision>] [--endpoint <url>]
#
# If --dsym-path is not provided, falls back to Xcode's DWARF_DSYM_FOLDER_PATH.
#
# --revision is optional. If provided, it must match the revision configured in
# the SDK (configure(apiKey:environment:revision:)) so uploaded dSYMs and the
# errors they symbolicate share the same revision for release tracking.
#

set -uo pipefail
# Deliberately NOT set -e: a per-bundle failure must warn and continue to the
# next bundle (an Xcode archive should never die mid-loop on a network blip).
# Failures are counted explicitly and reported via the exit status instead.

API_KEY=""
DSYM_PATH=""
REVISION=""
ENDPOINT=""
# Endpoint precedence: --endpoint flag, then HONEYBADGER_API_BASE (kept for
# CI/e2e compatibility), then the production default. Resolved after the
# option loop below.
WARN_ONLY=0

usage() {
    echo "Usage: $0 --api-key <key> [--dsym-path <path>] [--revision <revision>] [--endpoint <url>] [--warn-only]"
    echo ""
    echo "Options:"
    echo "  --api-key    Honeybadger API key (required)"
    echo "  --dsym-path  Path to directory containing .dSYM bundles"
    echo "               (defaults to Xcode's DWARF_DSYM_FOLDER_PATH)"
    echo "  --revision   Optional revision/release identifier. Must match the"
    echo "               revision configured in the SDK."
    echo "  --endpoint   Base URL of the Honeybadger API. Use"
    echo "               https://eu-api.honeybadger.io for the EU stack."
    echo "               (defaults to \$HONEYBADGER_API_BASE or https://api.honeybadger.io)"
    echo "  --warn-only  Always exit 0, even if uploads fail (for build phases"
    echo "               that should not fail the build)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --dsym-path)
            DSYM_PATH="$2"
            shift 2
            ;;
        --revision)
            REVISION="$2"
            shift 2
            ;;
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        --warn-only)
            WARN_ONLY=1
            shift 1
            ;;
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
done

API_BASE="${ENDPOINT:-${HONEYBADGER_API_BASE:-https://api.honeybadger.io}}"
while [[ "$API_BASE" == */ ]]; do API_BASE="${API_BASE%/}"; done

if [[ -z "$API_KEY" ]]; then
    echo "Error: --api-key is required"
    usage
fi

if [[ -z "$DSYM_PATH" ]]; then
    if [[ -n "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
        DSYM_PATH="$DWARF_DSYM_FOLDER_PATH"
    else
        echo "Error: --dsym-path is required (or set DWARF_DSYM_FOLDER_PATH via Xcode)"
        usage
    fi
fi

if [[ ! -d "$DSYM_PATH" ]]; then
    echo "Error: dSYM path does not exist: $DSYM_PATH"
    exit 1
fi

for dep in curl zip python3; do
    if ! command -v "$dep" > /dev/null 2>&1; then
        echo "Error: required tool '$dep' not found in PATH"
        exit 2
    fi
done

DSYM_BUNDLES=$(find "$DSYM_PATH" -name "*.dSYM" -type d 2>/dev/null)

if [[ -z "$DSYM_BUNDLES" ]]; then
    echo "No .dSYM bundles found in $DSYM_PATH"
    exit 0
fi

TMPDIR_CLEANUP=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CLEANUP"' EXIT

TOTAL=0
FAILED=0

echo "Found dSYM bundles:"
while IFS= read -r dsym; do
    DSYM_NAME=$(basename "$dsym")
    TOTAL=$((TOTAL+1))
    echo "  $DSYM_NAME"

    # Extract UUID(s) from the dSYM
    UUIDS=$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '{print $2}' || true)

    if [[ -z "$UUIDS" ]]; then
        echo "    Warning: Could not extract UUID, skipping"
        FAILED=$((FAILED+1))
        continue
    fi

    echo "    UUIDs: $UUIDS"

    # Create a zip of the dSYM bundle
    ZIP_PATH="$TMPDIR_CLEANUP/${DSYM_NAME}.zip"
    if ! (cd "$(dirname "$dsym")" && zip -r -q "$ZIP_PATH" "$DSYM_NAME"); then
        echo "    Error: Failed to zip dSYM bundle"
        FAILED=$((FAILED+1))
        continue
    fi

    ZIP_SIZE=$(wc -c < "$ZIP_PATH" | tr -d ' ')
    echo "    Zip size: $ZIP_SIZE bytes"

    # Request a presigned upload URL from the API
    echo "    Requesting upload URL..."
    # Build the JSON body with python3 (already a dependency below) so that
    # filename and revision are properly escaped — a raw revision containing a
    # quote or backslash would otherwise produce malformed JSON. revision is
    # included only when non-empty.
    REQUEST_BODY=$(python3 -c '
import json, sys
body = {"filename": sys.argv[1], "filesize": int(sys.argv[2])}
if len(sys.argv) > 3 and sys.argv[3]:
    body["revision"] = sys.argv[3]
print(json.dumps(body))
' "${DSYM_NAME}.zip" "$ZIP_SIZE" "$REVISION")
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "X-API-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_BODY" \
        "$API_BASE/v1/dsyms") || {
        echo "    Error: Request for upload URL failed (network error)"
        FAILED=$((FAILED+1))
        continue
    }

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
        echo "    Error: Failed to get upload URL (HTTP $HTTP_CODE)"
        echo "    Response: $BODY"
        FAILED=$((FAILED+1))
        continue
    fi

    PRESIGN_BODY_PATH="$TMPDIR_CLEANUP/${DSYM_NAME}.presign.json"
    UPLOAD_HEADERS_PATH="$TMPDIR_CLEANUP/${DSYM_NAME}.headers"
    UPLOAD_FIELDS_PATH="$TMPDIR_CLEANUP/${DSYM_NAME}.fields"
    printf '%s' "$BODY" > "$PRESIGN_BODY_PATH"

    UPLOAD_URL=$(python3 - "$PRESIGN_BODY_PATH" "$UPLOAD_HEADERS_PATH" "$UPLOAD_FIELDS_PATH" <<'PY' 2>/dev/null || echo ""
import json, sys

path, headers_path, fields_path = sys.argv[1:4]
with open(path) as f:
    body = json.load(f)

upload = body.get("upload") if isinstance(body.get("upload"), dict) else {}
url = (
    body.get("upload_url")
    or body.get("url")
    or upload.get("url")
    or upload.get("upload_url")
    or ""
)

headers = {}
for key in ("upload_headers", "headers"):
    value = body.get(key)
    if isinstance(value, dict):
        headers.update(value)
for key in ("upload_headers", "headers"):
    value = upload.get(key)
    if isinstance(value, dict):
        headers.update(value)

fields = {}
for key in ("fields", "form", "form_fields"):
    value = body.get(key)
    if isinstance(value, dict):
        fields.update(value)
for key in ("fields", "form", "form_fields"):
    value = upload.get(key)
    if isinstance(value, dict):
        fields.update(value)

with open(headers_path, "w") as f:
    for name, value in headers.items():
        f.write(f"{name}: {value}\n")

with open(fields_path, "w") as f:
    for name, value in fields.items():
        f.write(f"{name}\t{value}\n")

print(url)
PY
)

    if [[ -z "$UPLOAD_URL" ]]; then
        echo "    Error: No upload URL in response"
        echo "    Response: $BODY"
        FAILED=$((FAILED+1))
        continue
    fi

    CURL_UPLOAD_HEADERS=()
    if [[ -s "$UPLOAD_HEADERS_PATH" ]]; then
        while IFS= read -r header; do
            [[ -n "$header" ]] && CURL_UPLOAD_HEADERS+=("-H" "$header")
        done < "$UPLOAD_HEADERS_PATH"
    fi

    CURL_UPLOAD_FIELDS=()
    if [[ -s "$UPLOAD_FIELDS_PATH" ]]; then
        while IFS=$'\t' read -r field_name field_value; do
            [[ -n "$field_name" ]] && CURL_UPLOAD_FIELDS+=("-F" "${field_name}=${field_value}")
        done < "$UPLOAD_FIELDS_PATH"
    fi

    # Upload the zip. The dSYM API may return either a presigned PUT URL, or a
    # presigned POST target with form fields. In both cases, honor any headers
    # returned by the API because S3 signatures can include exact header values.
    echo "    Uploading..."
    if [[ ${#CURL_UPLOAD_FIELDS[@]} -gt 0 ]]; then
        UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X POST \
            "${CURL_UPLOAD_HEADERS[@]}" \
            "${CURL_UPLOAD_FIELDS[@]}" \
            -F "file=@$ZIP_PATH;type=application/zip" \
            "$UPLOAD_URL") || {
            echo "    Error: Upload failed (network error)"
            FAILED=$((FAILED+1))
            rm -f "$ZIP_PATH"
            continue
        }
    else
        PUT_ARGS=(-X PUT --data-binary "@$ZIP_PATH")
        if [[ ${#CURL_UPLOAD_HEADERS[@]} -gt 0 ]]; then
            PUT_ARGS+=("${CURL_UPLOAD_HEADERS[@]}")
        else
            PUT_ARGS+=("-H" "Content-Type: application/zip")
        fi
        UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
            "${PUT_ARGS[@]}" \
            "$UPLOAD_URL") || {
            echo "    Error: Upload failed (network error)"
            FAILED=$((FAILED+1))
            rm -f "$ZIP_PATH"
            continue
        }
    fi

    UPLOAD_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)
    UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

    if [[ "$UPLOAD_CODE" == "403" && ${#CURL_UPLOAD_FIELDS[@]} -eq 0 && ${#CURL_UPLOAD_HEADERS[@]} -eq 0 ]]; then
        echo "    Upload returned HTTP 403; retrying without Content-Type header..."
        UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
            -X PUT \
            --data-binary "@$ZIP_PATH" \
            "$UPLOAD_URL") || {
            echo "    Error: Upload retry failed (network error)"
            FAILED=$((FAILED+1))
            rm -f "$ZIP_PATH"
            continue
        }
        UPLOAD_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)
        UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')
    fi

    # Clean up zip
    rm -f "$ZIP_PATH"

    if [[ "$UPLOAD_CODE" == "200" || "$UPLOAD_CODE" == "201" ]]; then
        echo "    Upload successful"
    else
        echo "    Error: Upload failed (HTTP $UPLOAD_CODE)"
        if [[ -n "$UPLOAD_BODY" ]]; then
            echo "    Response: $UPLOAD_BODY"
        fi
        FAILED=$((FAILED+1))
        continue
    fi

done <<< "$DSYM_BUNDLES"

if [[ $FAILED -gt 0 ]]; then
    echo "Done: $((TOTAL - FAILED))/$TOTAL dSYM bundle(s) uploaded, $FAILED failed."
    if [[ $WARN_ONLY -eq 1 ]]; then
        echo "(--warn-only: exiting 0 despite failures)"
        exit 0
    fi
    exit 1
fi
echo "Done: $TOTAL dSYM bundle(s) uploaded."
