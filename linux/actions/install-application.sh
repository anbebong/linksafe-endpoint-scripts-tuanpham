#!/bin/bash
# =============================================================================
# LINKSAFE Patch Management - Install Application Action
# =============================================================================
# Install an application from DEB, RPM, TAR, or SH file
# Usage: install-application.sh <filename> [install_args] [wait_timeout]
# =============================================================================

set -uo pipefail

# Default values
DEFAULT_SEARCH_DIR="/tmp"
DEFAULT_TIMEOUT=3600

# Parse arguments
FILENAME="${1:-}"
INSTALL_ARGS="${2:-}"
WAIT_TIMEOUT="${3:-$DEFAULT_TIMEOUT}"

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
    output_json false "\"message\":\"Requires root privileges\""
    exit 1
fi

# Function to output JSON (compressed, one line)
output_json() {
    local success="$1"
    shift
    local json_data="$*"
    echo "{\"success\":$success,\"data\":{$json_data}}"
}

# Function to get file extension
get_extension() {
    local file="$1"
    echo "${file##*.}" | tr '[:upper:]' '[:lower:]'
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Resolve file path
if [ -z "$FILENAME" ]; then
    output_json false "\"message\":\"Filename is required\""
    exit 1
fi

# If not absolute path, search in default directory
if [[ "$FILENAME" != /* ]]; then
    FILEPATH="$DEFAULT_SEARCH_DIR/$FILENAME"
else
    FILEPATH="$FILENAME"
fi

# Check if file exists
if [ ! -f "$FILEPATH" ]; then
    output_json false "\"message\":\"File not found\",\"file_name\":\"$FILENAME\",\"file_path\":\"$FILEPATH\",\"search_directory\":\"$DEFAULT_SEARCH_DIR\""
    exit 1
fi

# Get file info
FILE_EXT=$(get_extension "$FILEPATH")
FILE_NAME=$(basename "$FILEPATH")
FILE_SIZE=$(stat -c%s "$FILEPATH" 2>/dev/null || echo "0")
FILE_SIZE_MB=$(awk "BEGIN {printf \"%.2f\", $FILE_SIZE/1024/1024}")

START_TIME=$(date +%s)
EXIT_CODE=0
STATUS="success"
MESSAGE="Installation completed successfully"
LOG_FILE=""
REBOOT_REQUIRED=false

# Detect OS
OS_TYPE=$(detect_os)

# Install based on file type
case "$FILE_EXT" in
    deb)
        echo "LOG:$(date -u +%Y-%m-%dT%H:%M:%SZ):INFO:Installing DEB package: $FILE_NAME" >&2
        
        # Install DEB package
        LOG_FILE="/tmp/install_${FILE_NAME%.*}_$(date +%Y%m%d%H%M%S).log"
        if dpkg -i "$FILEPATH" >"$LOG_FILE" 2>&1; then
            EXIT_CODE=0
            # Fix any dependency issues
            apt-get install -f -y >/dev/null 2>&1 || true
        else
            EXIT_CODE=$?
            STATUS="error"
            MESSAGE="DEB installation failed with exit code: $EXIT_CODE"
        fi
        ;;
        
    rpm)
        echo "LOG:$(date -u +%Y-%m-%dT%H:%M:%SZ):INFO:Installing RPM package: $FILE_NAME" >&2
        
        # Install RPM package based on OS
        LOG_FILE="/tmp/install_${FILE_NAME%.*}_$(date +%Y%m%d%H%M%S).log"
        
        if [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ] || [ "$OS_TYPE" = "centos" ]; then
            # Use dnf if available, else yum
            if command -v dnf >/dev/null 2>&1; then
                if dnf install -y "$FILEPATH" >"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
            else
                if yum install -y "$FILEPATH" >"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
            fi
        else
            # Use rpm directly
            if rpm -ivh "$FILEPATH" >"$LOG_FILE" 2>&1; then
                EXIT_CODE=0
            else
                EXIT_CODE=$?
            fi
        fi
        
        if [ $EXIT_CODE -ne 0 ]; then
            STATUS="error"
            MESSAGE="RPM installation failed with exit code: $EXIT_CODE"
        fi
        ;;
        
    tar|gz|bz2|xz)
        echo "LOG:$(date -u +%Y-%m-%dT%H:%M:%SZ):INFO:Extracting archive: $FILE_NAME" >&2
        
        # Extract archive
        EXTRACT_DIR="/tmp/install_${FILE_NAME%.*}_$(date +%Y%m%d%H%M%S)"
        mkdir -p "$EXTRACT_DIR"
        LOG_FILE="/tmp/install_${FILE_NAME%.*}_$(date +%Y%m%d%H%M%S).log"
        
        case "$FILE_EXT" in
            tar)
                if tar -xf "$FILEPATH" -C "$EXTRACT_DIR" >"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
                ;;
            gz)
                if tar -xzf "$FILEPATH" -C "$EXTRACT_DIR" >"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
                ;;
            bz2)
                if tar -xjf "$FILEPATH" -C "$EXTRACT_DIR" >"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
                ;;
            xz)
                if tar -xJf "$FILEPATH" -C "$EXTRACT_DIR" >"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
                ;;
        esac
        
        if [ $EXIT_CODE -eq 0 ]; then
            # Look for install script or setup script
            if [ -f "$EXTRACT_DIR/install.sh" ]; then
                chmod +x "$EXTRACT_DIR/install.sh"
                if "$EXTRACT_DIR/install.sh" $INSTALL_ARGS >>"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
            elif [ -f "$EXTRACT_DIR/setup.sh" ]; then
                chmod +x "$EXTRACT_DIR/setup.sh"
                if "$EXTRACT_DIR/setup.sh" $INSTALL_ARGS >>"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
            elif [ -f "$EXTRACT_DIR/configure" ]; then
                cd "$EXTRACT_DIR"
                ./configure $INSTALL_ARGS >>"$LOG_FILE" 2>&1
                make >>"$LOG_FILE" 2>&1
                if make install >>"$LOG_FILE" 2>&1; then
                    EXIT_CODE=0
                else
                    EXIT_CODE=$?
                fi
            else
                MESSAGE="Archive extracted but no install script found"
            fi
            
            # Cleanup
            rm -rf "$EXTRACT_DIR"
            
            if [ $EXIT_CODE -ne 0 ]; then
                STATUS="error"
                MESSAGE="Installation script failed with exit code: $EXIT_CODE"
            fi
        else
            STATUS="error"
            MESSAGE="Archive extraction failed with exit code: $EXIT_CODE"
        fi
        ;;
        
    sh)
        echo "LOG:$(date -u +%Y-%m-%dT%H:%M:%SZ):INFO:Running shell script: $FILE_NAME" >&2
        
        # Make executable and run
        chmod +x "$FILEPATH"
        LOG_FILE="/tmp/install_${FILE_NAME%.*}_$(date +%Y%m%d%H%M%S).log"
        
        if bash "$FILEPATH" $INSTALL_ARGS >"$LOG_FILE" 2>&1; then
            EXIT_CODE=0
        else
            EXIT_CODE=$?
            STATUS="error"
            MESSAGE="Script execution failed with exit code: $EXIT_CODE"
        fi
        ;;
        
    *)
        output_json false "\"message\":\"Unsupported file type. Supported types: .deb, .rpm, .tar, .gz, .bz2, .xz, .sh\",\"file_name\":\"$FILENAME\",\"file_path\":\"$FILEPATH\",\"file_type\":\".$FILE_EXT\""
        exit 1
        ;;
esac

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Update status if installation failed
if [ $EXIT_CODE -ne 0 ]; then
    STATUS="error"
fi

# Output result
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Escape message and log_file for JSON
ESCAPED_MESSAGE=$(echo "$MESSAGE" | sed 's/"/\\"/g')
ESCAPED_LOG_FILE=$(echo "${LOG_FILE:-}" | sed 's/"/\\"/g')

output_json true "\"hostname\":\"$HOSTNAME\",\"timestamp\":\"$TIMESTAMP\",\"status\":\"$STATUS\",\"file_name\":\"$FILENAME\",\"file_path\":\"$FILEPATH\",\"file_type\":\".$FILE_EXT\",\"exit_code\":$EXIT_CODE,\"duration_seconds\":$DURATION,\"message\":\"$ESCAPED_MESSAGE\",\"log_file\":\"$ESCAPED_LOG_FILE\",\"reboot_required\":$REBOOT_REQUIRED"

if [ "$STATUS" = "error" ]; then
    exit 1
else
    exit 0
fi
