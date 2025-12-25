#!/bin/bash
#
# Desktop setup script for Catoconsting development environment
# Sets up a development environment on Linux/macOS including:
# - Package manager (Homebrew for macOS, apt/yum/dnf for Linux)
# - Java JDK 17
# - Apache Maven
# - Git
# - Visual Studio Code (optional)
# - Project repository clone and configuration
#
# Usage: Called by setup-environment.sh
#   ./setup-desktop.sh [computer-name] [log-file]

set -e

# Parameters
COMPUTER_NAME=${1:-$(hostname)}
LOG_FILE=${2:-"setup-log-$COMPUTER_NAME-$(date +%Y%m%d-%H%M%S).txt"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Detect OS
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

# Logging function
log() {
    local level=${2:-INFO}
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    echo -e "$message"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Install package manager (Homebrew for macOS)
install_package_manager() {
    if [[ "$OS" == "macos" ]]; then
        log "Checking for Homebrew package manager..."
        if ! command_exists brew; then
            log "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            
            # Add Homebrew to PATH
            if [[ -f /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            
            log "Homebrew installed successfully" "SUCCESS"
        else
            log "Homebrew is already installed" "SUCCESS"
        fi
    elif [[ "$OS" == "debian" ]]; then
        log "Updating apt package index..."
        sudo apt-get update -qq
        log "Package manager ready" "SUCCESS"
    elif [[ "$OS" == "redhat" ]]; then
        log "Package manager ($PKG_MGR) ready" "SUCCESS"
    fi
}

# Install Java JDK 17
install_java() {
    log "Checking for Java JDK 17..."
    
    local java_version=""
    if command_exists java; then
        java_version=$(java -version 2>&1 | grep -oE '\"[0-9]+' | tr -d '"')
    fi
    
    if [[ -z "$java_version" ]] || [[ "$java_version" != "17" ]]; then
        log "Installing Java JDK 17..."
        
        case "$OS" in
            macos)
                brew install openjdk@17
                # Link JDK
                sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk 2>/dev/null || true
                ;;
            debian)
                sudo apt-get install -y openjdk-17-jdk
                ;;
            redhat)
                sudo $PKG_MGR install -y java-17-openjdk java-17-openjdk-devel
                ;;
        esac
        
        log "Java JDK 17 installed successfully" "SUCCESS"
    else
        log "Java JDK 17 is already installed" "SUCCESS"
    fi
    
    # Set JAVA_HOME
    if [[ -z "$JAVA_HOME" ]]; then
        log "Setting JAVA_HOME environment variable..."
        
        case "$OS" in
            macos)
                # Try java_home utility first, then check common Homebrew locations
                if command -v /usr/libexec/java_home &> /dev/null; then
                    export JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null)
                fi
                
                # Fallback to Homebrew locations (ARM and Intel)
                if [[ -z "$JAVA_HOME" ]] || [[ ! -d "$JAVA_HOME" ]]; then
                    if [[ -d "/opt/homebrew/opt/openjdk@17" ]]; then
                        export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
                    elif [[ -d "/usr/local/opt/openjdk@17" ]]; then
                        export JAVA_HOME="/usr/local/opt/openjdk@17"
                    fi
                fi
                ;;
            debian|redhat)
                export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
                ;;
        esac
        
        log "JAVA_HOME set to: $JAVA_HOME" "SUCCESS"
        
        # Add to shell profile
        local shell_profile=""
        if [[ -n "$BASH_VERSION" ]]; then
            shell_profile="$HOME/.bashrc"
        elif [[ -n "$ZSH_VERSION" ]]; then
            shell_profile="$HOME/.zshrc"
        fi
        
        if [[ -n "$shell_profile" ]] && [[ -f "$shell_profile" ]]; then
            if ! grep -q "JAVA_HOME" "$shell_profile"; then
                echo "export JAVA_HOME=$JAVA_HOME" >> "$shell_profile"
                echo 'export PATH=$JAVA_HOME/bin:$PATH' >> "$shell_profile"
                log "Added JAVA_HOME to $shell_profile" "SUCCESS"
            fi
        fi
    fi
}

# Install Apache Maven
install_maven() {
    log "Checking for Apache Maven..."
    
    if ! command_exists mvn; then
        log "Installing Apache Maven..."
        
        case "$OS" in
            macos)
                brew install maven
                ;;
            debian)
                sudo apt-get install -y maven
                ;;
            redhat)
                sudo $PKG_MGR install -y maven
                ;;
        esac
        
        log "Maven installed successfully" "SUCCESS"
    else
        local mvn_version=$(mvn -version 2>&1 | head -n 1)
        log "Maven is already installed: $mvn_version" "SUCCESS"
    fi
}

# Install Git
install_git() {
    log "Checking for Git..."
    
    if ! command_exists git; then
        log "Installing Git..."
        
        case "$OS" in
            macos)
                brew install git
                ;;
            debian)
                sudo apt-get install -y git
                ;;
            redhat)
                sudo $PKG_MGR install -y git
                ;;
        esac
        
        log "Git installed successfully" "SUCCESS"
    else
        local git_version=$(git --version)
        log "Git is already installed: $git_version" "SUCCESS"
    fi
}

# Install Visual Studio Code (optional)
install_vscode() {
    log "Checking for Visual Studio Code..."
    
    if ! command_exists code; then
        log "Installing Visual Studio Code..."
        
        case "$OS" in
            macos)
                brew install --cask visual-studio-code
                ;;
            debian)
                wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
                sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
                sudo sh -c 'echo "deb [arch=amd64,arm64,armhf] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
                sudo apt-get update -qq
                sudo apt-get install -y code
                rm -f packages.microsoft.gpg
                ;;
            redhat)
                sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
                sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
                sudo $PKG_MGR install -y code
                ;;
        esac
        
        log "VS Code installed successfully" "SUCCESS"
        
        # Install extensions
        if command_exists code; then
            log "Installing VS Code extensions for Java development..."
            code --install-extension vscjava.vscode-java-pack --force &> /dev/null || true
            code --install-extension vscjava.vscode-maven --force &> /dev/null || true
            log "VS Code Java extensions installed" "SUCCESS"
        fi
    else
        log "VS Code is already installed" "SUCCESS"
    fi
}

# Configure Git
configure_git() {
    log "Configuring Git..."
    
    local git_user=$(git config --global user.name 2>/dev/null || echo "")
    
    if [[ -z "$git_user" ]]; then
        echo ""
        echo -e "${YELLOW}Git configuration needed:${NC}"
        read -p "Enter your Git user name: " user_name
        read -p "Enter your Git email: " user_email
        
        git config --global user.name "$user_name"
        git config --global user.email "$user_email"
        log "Git configured with user: $user_name <$user_email>" "SUCCESS"
    else
        log "Git already configured for user: $git_user" "SUCCESS"
    fi
}

# Create workspace directory
create_workspace() {
    local workspace_dir="$HOME/CatoWorkspace"
    log "Setting up workspace directory: $workspace_dir"
    
    if [[ ! -d "$workspace_dir" ]]; then
        mkdir -p "$workspace_dir"
        log "Workspace directory created" "SUCCESS"
    else
        log "Workspace directory already exists" "SUCCESS"
    fi
    
    echo "$workspace_dir"
}

# Clone repository (optional)
clone_repository() {
    local workspace_dir=$1
    local repo_dir="$workspace_dir/CatoRepository"
    
    if [[ ! -d "$repo_dir" ]]; then
        echo ""
        read -p "Do you want to clone the Catoconsting repository now? (y/n): " clone_response
        
        if [[ "$clone_response" == "y" || "$clone_response" == "Y" ]]; then
            read -p "Enter the repository URL (e.g., https://github.com/username/CatoRepository.git): " repo_url
            
            log "Cloning repository from: $repo_url"
            cd "$workspace_dir"
            git clone "$repo_url" || log "Failed to clone repository" "WARNING"
            
            if [[ -d "$repo_dir" ]]; then
                log "Repository cloned successfully" "SUCCESS"
            fi
        fi
    else
        log "Repository already exists at: $repo_dir" "SUCCESS"
    fi
}

# Verify installations
verify_installations() {
    log ""
    log "=== Verification of Installed Components ===" "INFO"
    
    log "Verifying Java..."
    if command_exists java; then
        java -version 2>&1 | head -n 1 | sed 's/^/  /'
        log "Java: OK" "SUCCESS"
    else
        log "Java: FAILED" "ERROR"
    fi
    
    log "Verifying Maven..."
    if command_exists mvn; then
        mvn -version 2>&1 | head -n 1 | sed 's/^/  /'
        log "Maven: OK" "SUCCESS"
    else
        log "Maven: FAILED" "ERROR"
    fi
    
    log "Verifying Git..."
    if command_exists git; then
        git --version | sed 's/^/  /'
        log "Git: OK" "SUCCESS"
    else
        log "Git: FAILED" "ERROR"
    fi
}

# Main execution
main() {
    log "=== Desktop Setup Started ===" "INFO"
    log "Computer Name: $COMPUTER_NAME"
    
    # Detect OS
    detect_os
    log "Detected OS: $OS (Package manager: $PKG_MGR)"
    
    if [[ "$OS" == "unknown" ]]; then
        log "Unsupported operating system" "ERROR"
        exit 1
    fi
    
    # Install components
    install_package_manager
    install_java
    install_maven
    install_git
    install_vscode
    
    # Configure
    configure_git
    
    # Setup workspace
    workspace_dir=$(create_workspace)
    clone_repository "$workspace_dir"
    
    # Verify
    verify_installations
    
    # Summary
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}   Desktop Setup Complete!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "${CYAN}Installed Components:${NC}"
    echo -e "${WHITE}  - Package Manager ($PKG_MGR)${NC}"
    echo -e "${WHITE}  - Java JDK 17${NC}"
    echo -e "${WHITE}  - Apache Maven${NC}"
    echo -e "${WHITE}  - Git${NC}"
    echo -e "${WHITE}  - Visual Studio Code (with Java extensions)${NC}"
    echo ""
    echo -e "${YELLOW}Workspace: $workspace_dir${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "${WHITE}  1. Restart your terminal to ensure all PATH changes take effect${NC}"
    echo -e "${WHITE}  2. Navigate to your workspace: cd $workspace_dir${NC}"
    echo -e "${WHITE}  3. Clone the repository if you haven't already${NC}"
    echo -e "${WHITE}  4. Build the project: mvn clean install${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    
    log "=== Desktop Setup Completed ===" "SUCCESS"
}

# Run main function
main
