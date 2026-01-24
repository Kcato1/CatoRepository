#!/bin/bash
#
# Common library for Catoconsting setup scripts
# Contains shared functions and constants used across setup scripts
#
# Usage: source this file from other scripts
#   source "$(dirname "$0")/lib/common.sh"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Logging function
# Usage: log "message" ["level"]
log() {
    local level=${2:-INFO}
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    echo -e "$message"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

# Check if command exists
# Usage: command_exists "command_name"
command_exists() {
    command -v "$1" &> /dev/null
}

# Detect OS and package manager
# Sets global variables: OS, PKG_MGR
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        PKG_MGR="brew"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        PKG_MGR="apt"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        if command -v dnf &> /dev/null; then
            PKG_MGR="dnf"
        else
            PKG_MGR="yum"
        fi
    else
        OS="unknown"
        PKG_MGR="unknown"
    fi
}
