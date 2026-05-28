#!/bin/bash
#
# upload-dsyms.sh
#
# Uploads dSYM bundles to Honeybadger for server-side symbolication.
# Can be used as an Xcode build phase or CI step.
#
# Usage:
#   ./bin/upload-dsyms.sh --api-key <key> [--dsym-path <path>] [--revision <revision>]
#
# If --dsym-path is not provided, falls back to Xcode's DWARF_DSYM_FOLDER_PATH.
#
# --revision is optional. If provided, it must match the revision configured in
# the SDK (configure(apiKey:environment:revision:)) so uploaded dSYMs and the
# errors they symbolicate share the same revision for release tracking.
#

set -euo pipefail

API_KEY=""
DSYM_PATH=""
REVISION=""
API_BASE="https://api.honeybadger.io"

usage() {
    echo "Usage: $0 --api-key <key> [--dsym-path <path>] [--revision <revision>]"
    echo ""
    echo "Options:"
    echo "  --api-key    Honeybadger API key (required)"
    echo "  --dsym-path  Path to directory containing .dSYM bundles"
    echo "               (defaults to Xcode's DWARF_DSYM_FOLDER_PATH)"
    echo "  --revision   Optional revision/release identifier. Must match the"
    echo "               revision configured in the SDK."
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
        *)
            echo "Error: Unknown option $1"
            usage
            ;;
    esac
done

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

DSYM_BUNDLES=$(find "$DSYM_PATH" -name "*.dSYM" -type d 2>/dev/null)

if [[ -z "$DSYM_BUNDLES" ]]; then
    echo "No .dSYM bundles found in $DSYM_PATH"
    exit 0
fi

TMPDIR_CLEANUP=$(mktemp -d)
trap "rm -rf $TMPDIR_CLEANUP" EXIT

echo "Found dSYM bundles:"
while IFS= read -r dsym; do
    DSYM_NAME=$(basename "$dsym")
    echo "  $DSYM_NAME"

    # Extract UUID(s) from the dSYM
    UUIDS=$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '{print $2}')

    if [[ -z "$UUIDS" ]]; then
        echo "    Warning: Could not extract UUID, skipping"
        continue
    fi

    echo "    UUIDs: $UUIDS"

    # Create a zip of the dSYM bundle
    ZIP_PATH="$TMPDIR_CLEANUP/${DSYM_NAME}.zip"
    (cd "$(dirname "$dsym")" && zip -r -q "$ZIP_PATH" "$DSYM_NAME")

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
        "$API_BASE/v1/dsyms")

    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
        echo "    Error: Failed to get upload URL (HTTP $HTTP_CODE)"
        echo "    Response: $BODY"
        continue
    fi

    UPLOAD_URL=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('upload_url', ''))" 2>/dev/null || echo "")

    if [[ -z "$UPLOAD_URL" ]]; then
        echo "    Error: No upload_url in response"
        echo "    Response: $BODY"
        continue
    fi

    # Upload the zip to the presigned URL
    echo "    Uploading..."
    UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X PUT \
        -H "Content-Type: application/zip" \
        --data-binary "@$ZIP_PATH" \
        "$UPLOAD_URL")

    UPLOAD_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)

    if [[ "$UPLOAD_CODE" == "200" || "$UPLOAD_CODE" == "201" ]]; then
        echo "    Upload successful"
    else
        echo "    Error: Upload failed (HTTP $UPLOAD_CODE)"
    fi

    # Clean up zip
    rm -f "$ZIP_PATH"

done <<< "$DSYM_BUNDLES"

echo "Done."
