#!/bin/bash
#
# Main setup script for Catoconsting project environments
# Orchestrates the setup of Linux/macOS environments for the Catoconsting Java web application.
# Supports both Desktop (development) and Server (deployment) environments.
#
# Usage:
#   ./setup-environment.sh -e <Desktop|Server> [-n <computer-name>]
#
# Examples:
#   ./setup-environment.sh -e Desktop -n "Dev-Mac-1"
#   ./setup-environment.sh -e Server -n "Ubuntu-Server"

set -e  # Exit on error

# Default values
ENVIRONMENT=""
COMPUTER_NAME=$(hostname)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/setup-log-$COMPUTER_NAME-$(date +%Y%m%d-%H%M%S).txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=${2:-INFO}
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    echo -e "$message"
    echo "$message" >> "$LOG_FILE"
}

# Check if running as root/sudo
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log "Running as root/sudo" "INFO"
    else
        log "This script may require sudo privileges for some operations" "WARNING"
    fi
}

# Display banner
show_banner() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}   Catoconsting Environment Setup${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
    echo -e "${YELLOW}Computer: $COMPUTER_NAME${NC}"
    echo -e "${YELLOW}Log File: $LOG_FILE${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
}

# Display usage
usage() {
    cat << EOF
Usage: $0 -e <Environment> [-n <ComputerName>]

Required:
    -e    Environment type: Desktop or Server

Optional:
    -n    Computer name identifier (default: hostname)
    -h    Show this help message

Examples:
    $0 -e Desktop -n "Dev-Mac-1"
    $0 -e Server -n "Ubuntu-Server"
EOF
    exit 1
}

# Parse command line arguments
while getopts "e:n:h" opt; do
    case $opt in
        e)
            ENVIRONMENT="$OPTARG"
            ;;
        n)
            COMPUTER_NAME="$OPTARG"
            ;;
        h)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$ENVIRONMENT" ]]; then
    echo -e "${RED}Error: Environment (-e) is required${NC}"
    usage
fi

if [[ "$ENVIRONMENT" != "Desktop" && "$ENVIRONMENT" != "Server" ]]; then
    echo -e "${RED}Error: Environment must be 'Desktop' or 'Server'${NC}"
    usage
fi

# Main execution
main() {
    show_banner
    check_privileges
    log "Starting setup for $ENVIRONMENT environment on $COMPUTER_NAME"

    # Determine which setup script to run
    local setup_script=""
    case "$ENVIRONMENT" in
        Desktop)
            setup_script="$SCRIPT_DIR/setup-desktop.sh"
            ;;
        Server)
            setup_script="$SCRIPT_DIR/setup-server.sh"
            ;;
    esac

    # Verify setup script exists
    if [[ ! -f "$setup_script" ]]; then
        log "Setup script not found: $setup_script" "ERROR"
        exit 1
    fi

    # Make setup script executable
    chmod +x "$setup_script"

    log "Executing setup script: $setup_script"

    # Execute the appropriate setup script
    bash "$setup_script" "$COMPUTER_NAME" "$LOG_FILE"

    log "Setup completed successfully!" "SUCCESS"
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}   Setup Completed Successfully!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "${YELLOW}Review the log file for details: $LOG_FILE${NC}"
    echo ""
}

# Run main function
main
