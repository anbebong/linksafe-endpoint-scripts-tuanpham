#!/bin/bash

INPUT_FILE="${1:-InstallCerts.txt}"
ACTION="${2:-import}"

CERT_SRC_DIR="/tmp"
CERT_LIST_DIR="/tmp"

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-}"
else
    OS_ID="unknown"
fi

case "$OS_ID" in
    ubuntu|debian)
        CERT_DST_DIR="/usr/local/share/ca-certificates"
        UPDATE_CMD="update-ca-certificates"
        ;;
    centos|rhel|fedora|rocky|almalinux)
        CERT_DST_DIR="/etc/pki/ca-trust/source/anchors"
        UPDATE_CMD="update-ca-trust"
        ;;
    sles|opensuse*)
        CERT_DST_DIR="/etc/pki/trust/anchors"
        UPDATE_CMD="update-ca-certificates"
        ;;
    *)
        printf '{"status":"error","data":{"message":"Unsupported OS: %s"}}\n' "$OS_ID"
        exit 2
        ;;
esac

# Check root
if [[ $EUID -ne 0 ]]; then
    printf '{"status":"error","data":{"message":"This script must be run as root"}}\n'
    exit 1
fi

# Resolve cert list file
if [[ "$INPUT_FILE" != /* ]]; then
    CERT_LIST="${CERT_LIST_DIR}/${INPUT_FILE}"
else
    CERT_LIST="$INPUT_FILE"
fi

if [[ ! -f "$CERT_LIST" ]]; then
    printf '{"status":"error","data":{"message":"Certificate list file not found: %s"}}\n' "$CERT_LIST"
    exit 1
fi

# Process certificates
imported_count=0
removed_count=0
skipped_count=0
error_count=0
status="success"

mkdir -p "$CERT_DST_DIR"

while IFS= read -r cert_name || [[ -n "$cert_name" ]]; do
    cert_name=$(echo "$cert_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$cert_name" || "$cert_name" =~ ^# ]] && {
        ((skipped_count++))
        continue
    }

    SRC_CERT="${CERT_SRC_DIR}/${cert_name}"
    DST_CERT="${CERT_DST_DIR}/${cert_name}"

    if [[ "$ACTION" == "import" ]]; then
        if [[ ! -f "$SRC_CERT" ]]; then
            ((error_count++))
            continue
        fi

        if cp -f "$SRC_CERT" "$DST_CERT" 2>/dev/null; then
            ((imported_count++))
        else
            ((error_count++))
        fi

    elif [[ "$ACTION" == "reset" ]]; then
        if [[ -f "$DST_CERT" ]]; then
            if rm -f "$DST_CERT" 2>/dev/null; then
                ((removed_count++))
            else
                ((error_count++))
            fi
        else
            ((skipped_count++))
        fi
    else
        printf '{"status":"error","data":{"message":"Invalid action: %s (use import or reset)"}}\n' "$ACTION"
        exit 1
    fi

done < "$CERT_LIST"

# Update CA certificates
if [[ "$ACTION" == "import" || "$ACTION" == "reset" ]]; then
    if ! $UPDATE_CMD >/dev/null 2>&1; then
        ((error_count++))
    fi
fi

if [[ $error_count -gt 0 ]]; then
    status="error"
fi

# Build result message
if [[ "$ACTION" == "import" ]]; then
    if [[ $imported_count -gt 0 ]]; then
        message="Imported ${imported_count} certificate(s). Skipped ${skipped_count}. Errors: ${error_count}"
    else
        message="No certificates imported. Skipped ${skipped_count}. Errors: ${error_count}"
    fi
else
    if [[ $removed_count -gt 0 ]]; then
        message="Removed ${removed_count} certificate(s). Skipped ${skipped_count}. Errors: ${error_count}"
    else
        message="No certificates removed. Skipped ${skipped_count}. Errors: ${error_count}"
    fi
fi

# Output JSON result
printf '{"status":"%s","data":{"message":"%s"}}\n' "$status" "$message"

if [[ "$status" == "error" ]]; then
    exit 1
else
    exit 0
fi

