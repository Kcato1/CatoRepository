#!/bin/bash
#
# Server setup script for Catoconsting deployment environment
# Sets up a Linux server for deploying the Catoconsting Java web application including:
# - Java JDK 17 for running the application
# - Nginx web server (reverse proxy)
# - Firewall rules for web traffic
# - Application deployment directory structure
# - Systemd service configuration for Java application
# - Monitoring and logging setup
#
# Usage: Called by setup-environment.sh
#   ./setup-server.sh [computer-name] [log-file]

set -e

# Parameters
COMPUTER_NAME=${1:-$(hostname)}
LOG_FILE=${2:-"setup-log-$COMPUTER_NAME-$(date +%Y%m%d-%H%M%S).txt"}

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Configuration
APP_NAME="Catoconsting"
DEPLOYMENT_ROOT="/opt/apps"
APP_DIR="$DEPLOYMENT_ROOT/$APP_NAME"
LOG_DIR="$APP_DIR/logs"
CONFIG_DIR="$APP_DIR/config"
SERVICE_NAME="catoconsting"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root (use sudo)" "ERROR"
        exit 1
    fi
}

# Install Java JDK 17
install_java() {
    log "Checking for Java JDK 17..."
    
    local java_version=""
    if command_exists java; then
        java_version=$(java -version 2>&1 | grep -oE '\"[0-9]+' | tr -d '"' || echo "")
    fi
    
    if [[ -z "$java_version" ]] || [[ "$java_version" != "17" ]]; then
        log "Installing Java JDK 17..."
        
        case "$OS" in
            debian)
                apt-get update -qq
                apt-get install -y openjdk-17-jdk
                ;;
            redhat)
                $PKG_MGR install -y java-17-openjdk java-17-openjdk-devel
                ;;
        esac
        
        log "Java JDK 17 installed successfully" "SUCCESS"
    else
        log "Java JDK 17 is already installed" "SUCCESS"
    fi
    
    # Set JAVA_HOME
    if [[ -z "$JAVA_HOME" ]]; then
        log "Setting JAVA_HOME environment variable..."
        export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
        
        # Add to system profile
        if ! grep -q "JAVA_HOME" /etc/environment; then
            echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment
            log "Added JAVA_HOME to /etc/environment" "SUCCESS"
        fi
    fi
}

# Install Nginx web server
install_nginx() {
    log "Checking for Nginx..."
    
    if ! command_exists nginx; then
        log "Installing Nginx web server..."
        
        case "$OS" in
            debian)
                apt-get install -y nginx
                ;;
            redhat)
                $PKG_MGR install -y nginx
                ;;
        esac
        
        log "Nginx installed successfully" "SUCCESS"
        
        # Enable and start nginx
        systemctl enable nginx
        systemctl start nginx
        log "Nginx service enabled and started" "SUCCESS"
    else
        log "Nginx is already installed" "SUCCESS"
    fi
}

# Create application directory structure
create_app_directories() {
    log "Creating application directory structure..."
    
    mkdir -p "$DEPLOYMENT_ROOT" "$APP_DIR" "$LOG_DIR" "$CONFIG_DIR"
    
    log "Created directories:" "SUCCESS"
    log "  - $APP_DIR"
    log "  - $LOG_DIR"
    log "  - $CONFIG_DIR"
    
    # Set appropriate permissions
    chown -R root:root "$APP_DIR"
    chmod 755 "$APP_DIR"
    chmod 755 "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    
    log "Set permissions on application directories" "SUCCESS"
}

# Configure firewall rules
configure_firewall() {
    log "Configuring firewall rules..."
    
    if command_exists ufw; then
        # UFW (Ubuntu/Debian)
        log "Configuring UFW firewall..."
        ufw --force enable
        ufw allow 22/tcp comment 'SSH'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        ufw allow 8080/tcp comment 'Java App'
        log "UFW firewall rules configured" "SUCCESS"
    elif command_exists firewall-cmd; then
        # firewalld (RHEL/CentOS)
        log "Configuring firewalld..."
        systemctl enable firewalld
        systemctl start firewalld
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --reload
        log "Firewalld rules configured" "SUCCESS"
    else
        log "No supported firewall found (ufw or firewalld)" "WARNING"
    fi
}

# Create deployment script
create_deploy_script() {
    local deploy_script="$APP_DIR/deploy.sh"
    log "Creating deployment script: $deploy_script"
    
    cat > "$deploy_script" << 'EOF'
#!/bin/bash
# Catoconsting Deployment Script
# This script deploys the JAR file and restarts the application service

set -e

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <path-to-jar-file>"
    exit 1
fi

JAR_PATH="$1"
APP_DIR="/opt/apps/Catoconsting"
SERVICE_NAME="catoconsting"
TARGET_JAR="$APP_DIR/app.jar"

echo "Deploying Catoconsting..."

# Verify JAR file exists
if [[ ! -f "$JAR_PATH" ]]; then
    echo "Error: JAR file not found: $JAR_PATH"
    exit 1
fi

# Stop service if it exists
if systemctl is-active --quiet $SERVICE_NAME; then
    echo "Stopping $SERVICE_NAME service..."
    systemctl stop $SERVICE_NAME
    sleep 2
fi

# Backup old JAR if exists
if [[ -f "$TARGET_JAR" ]]; then
    echo "Backing up old JAR..."
    cp "$TARGET_JAR" "$TARGET_JAR.backup.$(date +%Y%m%d-%H%M%S)"
fi

# Copy new JAR
echo "Copying new JAR to $TARGET_JAR..."
cp "$JAR_PATH" "$TARGET_JAR"
chmod 644 "$TARGET_JAR"

# Start service if it exists
if systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
    echo "Starting $SERVICE_NAME service..."
    systemctl start $SERVICE_NAME
    sleep 2
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo "Deployment completed successfully!"
        echo "Service status:"
        systemctl status $SERVICE_NAME --no-pager -l
    else
        echo "Warning: Service failed to start. Check logs:"
        echo "  journalctl -u $SERVICE_NAME -n 50"
    fi
else
    echo "Service not configured. JAR deployed to: $TARGET_JAR"
    echo "Run setup-service.sh to configure the systemd service"
fi
EOF
    
    chmod +x "$deploy_script"
    log "Deployment script created and made executable" "SUCCESS"
}

# Create service setup script
create_service_script() {
    local service_script="$APP_DIR/setup-service.sh"
    log "Creating service setup script: $service_script"
    
    cat > "$service_script" << 'EOF'
#!/bin/bash
# Catoconsting Systemd Service Setup Script
# Creates a systemd service to run the Java application

set -e

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

APP_NAME="Catoconsting"
SERVICE_NAME="catoconsting"
APP_DIR="/opt/apps/Catoconsting"
JAR_FILE="$APP_DIR/app.jar"
LOG_DIR="$APP_DIR/logs"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Check if JAR exists
if [[ ! -f "$JAR_FILE" ]]; then
    echo "Error: Application JAR not found: $JAR_FILE"
    echo "Please deploy your application first using deploy.sh"
    exit 1
fi

# Check if Java is available
if ! command -v java &> /dev/null; then
    echo "Error: Java is not installed or not in PATH"
    exit 1
fi

# Detect JAVA_HOME dynamically
DETECTED_JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

# Create systemd service file
echo "Creating systemd service file: $SERVICE_FILE..."
cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Catoconsting Java Web Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/java -jar $JAR_FILE
Restart=on-failure
RestartSec=10
StandardOutput=append:$LOG_DIR/service-stdout.log
StandardError=append:$LOG_DIR/service-stderr.log

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Environment
Environment="JAVA_HOME=$DETECTED_JAVA_HOME"

[Install]
WantedBy=multi-user.target
SERVICEEOF

# Reload systemd daemon
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable service
echo "Enabling $SERVICE_NAME service..."
systemctl enable $SERVICE_NAME

# Start service
echo "Starting $SERVICE_NAME service..."
systemctl start $SERVICE_NAME

# Wait a moment for service to start
sleep 3

# Check service status
echo ""
echo "Service Status:"
systemctl status $SERVICE_NAME --no-pager -l || true

echo ""
echo "Service configured successfully!"
echo "Logs location: $LOG_DIR"
echo ""
echo "Useful commands:"
echo "  systemctl start $SERVICE_NAME    - Start service"
echo "  systemctl stop $SERVICE_NAME     - Stop service"
echo "  systemctl restart $SERVICE_NAME  - Restart service"
echo "  systemctl status $SERVICE_NAME   - Check status"
echo "  journalctl -u $SERVICE_NAME -f   - Follow logs"
EOF
    
    chmod +x "$service_script"
    log "Service setup script created and made executable" "SUCCESS"
}

# Create application configuration template
create_config_template() {
    local config_file="$CONFIG_DIR/application.properties.template"
    log "Creating configuration template: $config_file"
    
    cat > "$config_file" << 'EOF'
# Catoconsting Application Configuration Template
# Copy this file to application.properties and customize for your environment

# Server Configuration
server.port=8080
server.address=0.0.0.0

# Logging Configuration
logging.level.root=INFO
logging.level.com.catoconsting=DEBUG
logging.file.name=/opt/apps/Catoconsting/logs/application.log
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} - %msg%n
logging.pattern.file=%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n

# Application Name
spring.application.name=Catoconsting

# Add your application-specific configuration below
EOF
    
    log "Configuration template created" "SUCCESS"
}

# Configure Nginx as reverse proxy (optional)
configure_nginx_proxy() {
    local nginx_config="/etc/nginx/sites-available/catoconsting"
    local nginx_enabled="/etc/nginx/sites-enabled/catoconsting"
    
    log "Creating Nginx reverse proxy configuration..."
    
    cat > "$nginx_config" << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    
    # Create symlink if sites-enabled exists
    if [[ -d "/etc/nginx/sites-enabled" ]]; then
        ln -sf "$nginx_config" "$nginx_enabled"
        log "Nginx configuration created and enabled" "SUCCESS"
    else
        # For RHEL/CentOS, copy to conf.d
        cp "$nginx_config" "/etc/nginx/conf.d/catoconsting.conf"
        log "Nginx configuration created" "SUCCESS"
    fi
    
    # Test and reload nginx
    if nginx -t &>/dev/null; then
        systemctl reload nginx
        log "Nginx reloaded successfully" "SUCCESS"
    else
        log "Nginx configuration test failed" "WARNING"
    fi
}

# Create README
create_readme() {
    local readme_file="$APP_DIR/README.txt"
    log "Creating operations README: $readme_file"
    
    cat > "$readme_file" << EOF
====================================================
  Catoconsting Server - Operational Guide
====================================================

Application Directory: $APP_DIR
Logs Directory: $LOG_DIR
Configuration Directory: $CONFIG_DIR
Service Name: $SERVICE_NAME

DEPLOYMENT STEPS:
-----------------
1. Copy your JAR file to this server
2. Run deployment script:
   sudo $APP_DIR/deploy.sh /path/to/your/app.jar

SYSTEMD SERVICE SETUP:
----------------------
1. Ensure JAR is deployed (see above)
2. Run service setup script:
   sudo $APP_DIR/setup-service.sh

SERVICE MANAGEMENT:
-------------------
Start:   sudo systemctl start $SERVICE_NAME
Stop:    sudo systemctl stop $SERVICE_NAME
Restart: sudo systemctl restart $SERVICE_NAME
Status:  sudo systemctl status $SERVICE_NAME

LOGS LOCATION:
--------------
Application Logs: $LOG_DIR/application.log
Service StdOut:   $LOG_DIR/service-stdout.log
Service StdErr:   $LOG_DIR/service-stderr.log
System Journal:   journalctl -u $SERVICE_NAME

View logs:
  tail -f $LOG_DIR/service-stdout.log
  journalctl -u $SERVICE_NAME -f

FIREWALL RULES:
---------------
HTTP (80):       Enabled
HTTPS (443):     Enabled
Java App (8080): Enabled

NGINX REVERSE PROXY:
--------------------
Nginx is configured as a reverse proxy on port 80
pointing to the Java application on port 8080.

Access your application:
  - Local: http://localhost or http://localhost:8080
  - Remote: http://<server-ip>

TROUBLESHOOTING:
----------------
1. Check service status: sudo systemctl status $SERVICE_NAME
2. Check logs: sudo journalctl -u $SERVICE_NAME -n 50
3. Verify Java: java -version
4. Test JAR manually: java -jar $APP_DIR/app.jar
5. Check if port is in use: sudo netstat -tlnp | grep 8080

IMPORTANT NOTES:
----------------
- Always test deployments in a non-production environment first
- Keep backups of your JAR files
- Monitor logs regularly
- Ensure sufficient disk space for logs
- Consider setting up log rotation

====================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
====================================================
EOF
    
    log "Operations README created" "SUCCESS"
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
    
    log "Verifying Nginx..."
    if command_exists nginx; then
        nginx -v 2>&1 | sed 's/^/  /'
        log "Nginx: OK" "SUCCESS"
    else
        log "Nginx: FAILED" "ERROR"
    fi
    
    log "Verifying systemd..."
    if command_exists systemctl; then
        log "Systemd: OK" "SUCCESS"
    else
        log "Systemd: FAILED" "ERROR"
    fi
}

# Main execution
main() {
    check_root
    
    log "=== Server Setup Started ===" "INFO"
    log "Server Name: $COMPUTER_NAME"
    
    # Detect OS
    detect_os
    log "Detected OS: $OS (Package manager: $PKG_MGR)"
    
    if [[ "$OS" == "unknown" ]]; then
        log "Unsupported operating system" "ERROR"
        exit 1
    fi
    
    # Install components
    install_java
    install_nginx
    
    # Create directories
    create_app_directories
    
    # Configure firewall
    configure_firewall
    
    # Create scripts and configs
    create_deploy_script
    create_service_script
    create_config_template
    configure_nginx_proxy
    create_readme
    
    # Verify
    verify_installations
    
    # Summary
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}   Server Setup Complete!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "${CYAN}Server Configuration:${NC}"
    echo -e "${WHITE}  - Java JDK 17${NC}"
    echo -e "${WHITE}  - Nginx Web Server${NC}"
    echo -e "${WHITE}  - Systemd Service Manager${NC}"
    echo -e "${WHITE}  - Firewall rules configured${NC}"
    echo ""
    echo -e "${YELLOW}Application Directory: $APP_DIR${NC}"
    echo ""
    echo -e "${CYAN}Deployment Scripts Created:${NC}"
    echo -e "${WHITE}  - $APP_DIR/deploy.sh${NC}"
    echo -e "${WHITE}  - $APP_DIR/setup-service.sh${NC}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo -e "${WHITE}  1. Deploy your JAR file: sudo $APP_DIR/deploy.sh /path/to/jar${NC}"
    echo -e "${WHITE}  2. Set up systemd service: sudo $APP_DIR/setup-service.sh${NC}"
    echo -e "${WHITE}  3. Configure application properties in: $CONFIG_DIR${NC}"
    echo -e "${WHITE}  4. Monitor logs in: $LOG_DIR${NC}"
    echo -e "${WHITE}  5. Access application at: http://$COMPUTER_NAME${NC}"
    echo ""
    echo -e "${YELLOW}Refer to: $APP_DIR/README.txt for operational guide${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    
    log "=== Server Setup Completed ===" "SUCCESS"
}

# Run main function
main
