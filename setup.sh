#!/usr/bin/env bash
#
# Universal setup script launcher for Catoconsting project
# Automatically detects platform and runs the appropriate setup script
#
# Usage:
#   ./setup.sh -e <Desktop|Server> [-n <computer-name>]
#
# Examples:
#   ./setup.sh -e Desktop
#   ./setup.sh -e Server -n "MyServer"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Display banner
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   Catoconsting Universal Setup Script${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Detect platform
detect_platform() {
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

PLATFORM=$(detect_platform)

echo -e "${YELLOW}Detected platform: $PLATFORM${NC}"
echo ""

# Route to appropriate script based on platform
case "$PLATFORM" in
    windows)
        echo -e "${GREEN}Running Windows PowerShell setup...${NC}"
        echo ""
        if command -v pwsh &> /dev/null; then
            pwsh "$SCRIPT_DIR/setup-environment.ps1" "$@"
        elif command -v powershell &> /dev/null; then
            powershell -File "$SCRIPT_DIR/setup-environment.ps1" "$@"
        else
            echo -e "${RED}Error: PowerShell not found${NC}"
            echo "Please run setup-environment.ps1 directly from PowerShell"
            exit 1
        fi
        ;;
    macos|linux)
        echo -e "${GREEN}Running Linux/macOS bash setup...${NC}"
        echo ""
        # Make scripts executable if not already
        chmod +x "$SCRIPT_DIR/setup-environment.sh" 2>/dev/null || true
        chmod +x "$SCRIPT_DIR/setup-desktop.sh" 2>/dev/null || true
        chmod +x "$SCRIPT_DIR/setup-server.sh" 2>/dev/null || true
        
        # Run the setup script
        bash "$SCRIPT_DIR/setup-environment.sh" "$@"
        ;;
    unknown)
        echo -e "${RED}Error: Unable to detect platform${NC}"
        echo ""
        echo "Please run the appropriate setup script directly:"
        echo "  - Windows: setup-environment.ps1"
        echo "  - Linux/macOS: setup-environment.sh"
        exit 1
        ;;
esac

exit 0
