#!/bin/bash

#
# Simple Web Server Setup Script for Linux/macOS
#
# Installs Node.js and http-server for quick local web server setup.
# Useful for testing static websites, HTML files, and web applications.
#
# Usage:
#   ./setup-webserver.sh
#   ./setup-webserver.sh --port 3000 --start
#   ./setup-webserver.sh --port 8080 --directory ./public --start
#

set -e  # Exit on error

# Default values
PORT=8080
DIRECTORY="$(pwd)"
START_SERVER=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)
            echo -e "${NC}[$timestamp] [INFO] $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[$timestamp] [SUCCESS] $message${NC}"
            ;;
        WARNING)
            echo -e "${YELLOW}[$timestamp] [WARNING] $message${NC}"
            ;;
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR] $message${NC}"
            ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -d|--directory)
            DIRECTORY="$2"
            shift 2
            ;;
        -s|--start)
            START_SERVER=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --port PORT         Port number (default: 8080)"
            echo "  -d, --directory DIR     Directory to serve (default: current directory)"
            echo "  -s, --start             Start the server after installation"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --port 3000 --start"
            echo "  $0 --port 8080 --directory ./public --start"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Banner
echo -e "\n${CYAN}================================================${NC}"
echo -e "${CYAN}   Simple Web Server Setup${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "${YELLOW}Port: $PORT${NC}"
echo -e "${YELLOW}Directory: $DIRECTORY${NC}"
echo -e "${CYAN}================================================${NC}\n"

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            echo "$ID"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
log INFO "Detected OS: $OS"

# Check for Node.js
log INFO "Checking for Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    log SUCCESS "Node.js is already installed: $NODE_VERSION"
else
    log INFO "Node.js not found. Installing..."

    case $OS in
        macos)
            # Install using Homebrew
            if ! command -v brew &> /dev/null; then
                log ERROR "Homebrew not found. Please install Homebrew first:"
                log INFO "Visit https://brew.sh for installation instructions"
                exit 1
            fi

            log INFO "Installing Node.js via Homebrew..."
            brew install node
            log SUCCESS "Node.js installed successfully"
            ;;

        ubuntu|debian)
            log INFO "Installing Node.js via apt..."
            sudo apt-get update
            sudo apt-get install -y nodejs npm
            log SUCCESS "Node.js installed successfully"
            ;;

        fedora|rhel|centos)
            log INFO "Installing Node.js via dnf/yum..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y nodejs npm
            else
                sudo yum install -y nodejs npm
            fi
            log SUCCESS "Node.js installed successfully"
            ;;

        *)
            log ERROR "Unsupported OS: $OS"
            log INFO "Please install Node.js manually from https://nodejs.org"
            exit 1
            ;;
    esac

    # Verify installation
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log SUCCESS "Node.js version: $NODE_VERSION"
    else
        log ERROR "Node.js installation failed"
        exit 1
    fi
fi

# Check npm
log INFO "Verifying npm..."
if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm --version)
    log SUCCESS "npm version: $NPM_VERSION"
else
    log ERROR "npm not found. Please reinstall Node.js"
    exit 1
fi

# Install http-server globally
log INFO "Checking for http-server..."
if command -v http-server &> /dev/null; then
    log SUCCESS "http-server is already installed"
else
    log INFO "Installing http-server globally..."

    # Check if we need sudo
    if npm config get prefix | grep -q "/usr/local"; then
        log INFO "Installing with sudo (system-wide installation)..."
        sudo npm install -g http-server
    else
        npm install -g http-server
    fi

    log SUCCESS "http-server installed successfully"
fi

# Verify http-server installation
if command -v http-server &> /dev/null; then
    HTTP_SERVER_VERSION=$(http-server --version 2>&1)
    log SUCCESS "http-server version: $HTTP_SERVER_VERSION"
else
    log ERROR "http-server installation verification failed"
    exit 1
fi

# Create wrapper script for easy server startup
WRAPPER_SCRIPT="$(dirname "$0")/start-webserver.sh"
log INFO "Creating web server wrapper script: $WRAPPER_SCRIPT"

cat > "$WRAPPER_SCRIPT" << 'EOF'
#!/bin/bash

#
# Start the http-server web server
# Convenience script to start http-server with common options
#
# Usage:
#   ./start-webserver.sh
#   ./start-webserver.sh --port 3000 --open
#   ./start-webserver.sh --port 8080 --directory ./public --open
#

PORT=8080
DIRECTORY="$(pwd)"
OPEN=false

# Color codes
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -d|--directory)
            DIRECTORY="$2"
            shift 2
            ;;
        -o|--open)
            OPEN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --port PORT      Port number (default: 8080)"
            echo "  -d, --directory DIR  Directory to serve (default: current directory)"
            echo "  -o, --open           Open browser automatically"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}Starting web server...${NC}"
echo -e "${YELLOW}Directory: $DIRECTORY${NC}"
echo -e "${YELLOW}Port: $PORT${NC}"
echo -e "${GREEN}URL: http://localhost:$PORT${NC}"
echo -e "${YELLOW}\nPress Ctrl+C to stop the server\n${NC}"

# Build arguments
ARGS="-p $PORT"
if [ "$OPEN" = true ]; then
    ARGS="$ARGS -o"
fi

# Change to target directory and start server
cd "$DIRECTORY"
http-server $ARGS
EOF

chmod +x "$WRAPPER_SCRIPT"
log SUCCESS "Wrapper script created and made executable"

# Summary
echo -e "\n${GREEN}================================================${NC}"
echo -e "${GREEN}   Web Server Setup Complete!${NC}"
echo -e "${GREEN}================================================${NC}"
echo -e "\n${CYAN}Installed Components:${NC}"
echo -e "  ${NC}- Node.js (LTS)${NC}"
echo -e "  ${NC}- npm${NC}"
echo -e "  ${NC}- http-server${NC}"
echo -e "\n${CYAN}Usage Options:${NC}"
echo -e "\n  ${YELLOW}Option 1: Use the wrapper script${NC}"
echo -e "    ${NC}./start-webserver.sh${NC}"
echo -e "    ${NC}./start-webserver.sh --port 3000${NC}"
echo -e "    ${NC}./start-webserver.sh --port 8080 --open${NC}"
echo -e "\n  ${YELLOW}Option 2: Use http-server directly${NC}"
echo -e "    ${NC}http-server -p 8080${NC}"
echo -e "    ${NC}http-server -p 8080 -o${NC}"
echo -e "    ${NC}http-server ./public -p 3000${NC}"
echo -e "\n  ${YELLOW}Common Options:${NC}"
echo -e "    ${NC}-p <port>    Port number (default: 8080)${NC}"
echo -e "    ${NC}-o           Open browser automatically${NC}"
echo -e "    ${NC}-c-1         Disable caching${NC}"
echo -e "    ${NC}--cors       Enable CORS${NC}"
echo -e "    ${NC}-g or --gzip Enable gzip compression${NC}"
echo -e "\n${GREEN}================================================${NC}\n"

# Optionally start the server
if [ "$START_SERVER" = true ]; then
    echo -e "${CYAN}Starting web server now...\n${NC}"
    echo -e "${GREEN}Server URL: http://localhost:$PORT${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the server\n${NC}"

    cd "$DIRECTORY"
    http-server -p "$PORT"
else
    echo -e "${YELLOW}To start the server, run:${NC}"
    echo -e "  ${CYAN}./start-webserver.sh${NC}"
    echo -e "${YELLOW}Or:${NC}"
    echo -e "  ${CYAN}http-server -p $PORT${NC}\n"
fi
