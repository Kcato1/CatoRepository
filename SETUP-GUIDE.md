# Catoconsting Environment Setup Guide

Automated setup scripts for configuring development and deployment environments for the Catoconsting Java web application.

## Overview

This repository includes automated setup scripts for multiple platforms:

### Windows (PowerShell)
- **2 Desktop PCs** - Development environments with full Java development toolchain
- **1 Windows Server VM** - Production/staging deployment environment

### Linux/macOS (Bash)
- **Desktop/Laptop** - Development environments with Java development toolchain
- **Linux Server** - Production/staging deployment environment with Nginx and systemd

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Windows](#windows)
  - [Linux/macOS](#linuxmacos)
- [Desktop PC Setup](#desktop-pc-setup)
- [Windows Server VM Setup](#windows-server-vm-setup)
- [Linux/macOS Desktop Setup](#linuxmacos-desktop-setup)
- [Linux Server Setup](#linux-server-setup)
- [Script Details](#script-details)
- [Troubleshooting](#troubleshooting)
- [Post-Setup Tasks](#post-setup-tasks)

## Prerequisites

### Windows Systems
- Windows 10/11 (for desktops) or Windows Server 2016+ (for server)
- Administrator privileges
- Internet connection for downloading packages
- PowerShell 5.1 or higher

### Linux/macOS Systems
- macOS 10.15+ or Linux (Ubuntu 20.04+, RHEL/CentOS 8+, Fedora 34+)
- sudo/root privileges
- Internet connection for downloading packages
- Bash shell

### Recommended (All Systems)
- At least 8 GB RAM
- 20 GB free disk space
- Antivirus temporarily disabled during installation (Windows only)

## Quick Start

### Windows

#### For Desktop PCs (Development Environment)

1. **Download the scripts** to your computer (e.g., `C:\Temp\setup`)

2. **Open PowerShell as Administrator**
   - Press `Win + X` and select "Windows PowerShell (Admin)" or "Terminal (Admin)"

3. **Navigate to the script directory**
   ```powershell
   cd C:\Temp\setup
   ```

4. **Run the setup script**
   ```powershell
   .\setup-environment.ps1 -Environment Desktop -ComputerName "Desktop-1"
   ```

   For the second desktop PC, use:
   ```powershell
   .\setup-environment.ps1 -Environment Desktop -ComputerName "Desktop-2"
   ```

5. **Follow the prompts** during installation

6. **Restart your terminal** when complete to ensure PATH changes take effect

#### For Windows Server VM (Deployment Environment)

1. **Download the scripts** to your server (e.g., `C:\Setup`)

2. **Open PowerShell as Administrator**

3. **Navigate to the script directory**
   ```powershell
   cd C:\Setup
   ```

4. **Run the setup script**
   ```powershell
   .\setup-environment.ps1 -Environment Server -ComputerName "Server-VM"
   ```

5. **Review the post-setup guide** at `C:\Apps\Catoconsting\README.txt`

### Linux/macOS

#### For Desktop/Laptop (Development Environment)

1. **Download the scripts** to your computer (e.g., `~/setup`)

2. **Open a terminal**

3. **Navigate to the script directory**
   ```bash
   cd ~/setup
   ```

4. **Make the script executable** (if not already)
   ```bash
   chmod +x setup-environment.sh
   ```

5. **Run the setup script**
   ```bash
   ./setup-environment.sh -e Desktop -n "Dev-Mac-1"
   ```

   Or simply:
   ```bash
   ./setup-environment.sh -e Desktop
   ```

6. **Follow the prompts** during installation

7. **Restart your terminal** when complete to ensure PATH changes take effect

#### For Linux Server (Deployment Environment)

1. **Download the scripts** to your server (e.g., `/tmp/setup`)

2. **Open a terminal with sudo access**

3. **Navigate to the script directory**
   ```bash
   cd /tmp/setup
   ```

4. **Make the script executable** (if not already)
   ```bash
   chmod +x setup-environment.sh
   ```

5. **Run the setup script as root**
   ```bash
   sudo ./setup-environment.sh -e Server -n "Ubuntu-Server"
   ```

6. **Review the post-setup guide** at `/opt/apps/Catoconsting/README.txt`

## Desktop PC Setup

### What Gets Installed

The desktop setup script (`setup-desktop.ps1`) installs the following:

1. **Chocolatey Package Manager** - Windows package manager for easy software installation
2. **Java JDK 17** - Microsoft OpenJDK distribution
3. **Apache Maven** - Build and dependency management tool
4. **Git for Windows** - Version control system
5. **Visual Studio Code** - Code editor with Java extensions
   - Extension Pack for Java
   - Maven for Java

### Installation Process

The script will:
1. Check for existing installations (won't reinstall if already present)
2. Install missing components
3. Configure environment variables (JAVA_HOME, PATH)
4. Set up Git with your user information
5. Create a workspace directory at `%USERPROFILE%\CatoWorkspace`
6. Optionally clone the repository
7. Verify all installations

### Post-Installation

After setup completes:

1. **Restart your terminal** to load new PATH variables

2. **Verify installations:**
   ```powershell
   java -version
   mvn -version
   git --version
   code --version
   ```

3. **Navigate to your workspace:**
   ```powershell
   cd $env:USERPROFILE\CatoWorkspace
   ```

4. **Clone the repository** (if not done during setup):
   ```powershell
   git clone <repository-url>
   cd CatoRepository
   ```

5. **Build the project:**
   ```powershell
   mvn clean install
   ```

### Workspace Structure

```
C:\Users\<YourName>\CatoWorkspace\
└── CatoRepository\          # Your cloned repository
    ├── src\                 # Source code
    ├── target\              # Build output
    ├── pom.xml              # Maven configuration
    └── ...
```

## Windows Server VM Setup

### What Gets Installed

The server setup script (`setup-server.ps1`) installs and configures:

1. **Chocolatey Package Manager**
2. **Java JDK 17** - Microsoft OpenJDK distribution
3. **IIS Web Server** - With ASP.NET and ISAPI components
4. **URL Rewrite Module** - For IIS reverse proxy capabilities
5. **NSSM** - Service manager to run Java app as Windows Service
6. **Firewall Rules** - For HTTP (80), HTTPS (443), and Java app (8080)

### Directory Structure Created

```
C:\Apps\
└── Catoconsting\
    ├── logs\                    # Application and service logs
    ├── config\                  # Configuration files
    │   └── application.properties.template
    ├── deploy.ps1               # Deployment script
    ├── setup-service.ps1        # Windows Service setup script
    └── README.txt               # Operations guide
```

### Deployment Workflow

After server setup, follow these steps to deploy your application:

1. **Build your application** (on a desktop PC):
   ```powershell
   mvn clean package
   ```
   This creates a JAR file in the `target\` directory.

2. **Copy the JAR file** to the server (e.g., via RDP, network share, or deployment pipeline)

3. **Deploy the application** on the server:
   ```powershell
   cd C:\Apps\Catoconsting
   .\deploy.ps1 -JarPath "C:\path\to\your\app.jar"
   ```

4. **Set up the Windows Service** (first time only):
   ```powershell
   .\setup-service.ps1
   ```

5. **Verify the service is running:**
   ```powershell
   Get-Service CatoconstingService
   ```

6. **Access your application:**
   - Local: `http://localhost:8080`
   - Remote: `http://<server-ip>:8080`

### Service Management

Manage the Catoconsting Windows Service with these commands:

```powershell
# Start the service
Start-Service CatoconstingService

# Stop the service
Stop-Service CatoconstingService

# Restart the service
Restart-Service CatoconstingService

# Check service status
Get-Service CatoconstingService

# View service details
Get-Service CatoconstingService | Format-List *
```

### Log Files

Application logs are stored in `C:\Apps\Catoconsting\logs\`:
- `application.log` - Application logs (if configured in app)
- `service-stdout.log` - Service standard output
- `service-stderr.log` - Service error output

View logs:
```powershell
# View latest log entries
Get-Content C:\Apps\Catoconsting\logs\service-stdout.log -Tail 50

# Monitor logs in real-time
Get-Content C:\Apps\Catoconsting\logs\service-stdout.log -Wait
```

## Linux/macOS Desktop Setup

### What Gets Installed

The desktop setup script (`setup-desktop.sh`) installs the following:

1. **Package Manager**
   - Homebrew (macOS)
   - apt (Debian/Ubuntu)
   - dnf/yum (RHEL/CentOS/Fedora)
2. **Java JDK 17** - OpenJDK distribution
3. **Apache Maven** - Build and dependency management tool
4. **Git** - Version control system
5. **Visual Studio Code** - Code editor with Java extensions
   - Extension Pack for Java
   - Maven for Java

### Installation Process

The script will:
1. Detect your operating system (macOS, Debian-based, or RHEL-based)
2. Install or verify the package manager
3. Install missing components
4. Configure environment variables (JAVA_HOME, PATH)
5. Set up Git with your user information
6. Create a workspace directory at `~/CatoWorkspace`
7. Optionally clone the repository
8. Verify all installations

### Post-Installation

After setup completes:

1. **Restart your terminal** to load new PATH variables

2. **Verify installations:**
   ```bash
   java -version
   mvn -version
   git --version
   code --version
   ```

3. **Navigate to your workspace:**
   ```bash
   cd ~/CatoWorkspace
   ```

4. **Clone the repository** (if not done during setup):
   ```bash
   git clone <repository-url>
   cd CatoRepository
   ```

5. **Build the project:**
   ```bash
   mvn clean install
   ```

### Workspace Structure

```
~/CatoWorkspace/
└── CatoRepository/          # Your cloned repository
    ├── src/                 # Source code
    ├── target/              # Build output
    ├── pom.xml              # Maven configuration
    └── ...
```

## Linux Server Setup

### What Gets Installed

The server setup script (`setup-server.sh`) installs and configures:

1. **Java JDK 17** - OpenJDK distribution
2. **Nginx Web Server** - Reverse proxy and web server
3. **Systemd** - Service manager to run Java app as Linux service
4. **Firewall Rules** - For HTTP (80), HTTPS (443), and Java app (8080)

### Directory Structure Created

```
/opt/apps/
└── Catoconsting/
    ├── logs/                    # Application and service logs
    ├── config/                  # Configuration files
    │   └── application.properties.template
    ├── deploy.sh                # Deployment script
    ├── setup-service.sh         # Systemd service setup script
    └── README.txt               # Operations guide
```

### Deployment Workflow

After server setup, follow these steps to deploy your application:

1. **Build your application** (on a development machine):
   ```bash
   mvn clean package
   ```
   This creates a JAR file in the `target/` directory.

2. **Copy the JAR file** to the server (e.g., via scp, rsync, or deployment pipeline)
   ```bash
   scp target/app.jar user@server:/tmp/app.jar
   ```

3. **Deploy the application** on the server:
   ```bash
   sudo /opt/apps/Catoconsting/deploy.sh /tmp/app.jar
   ```

4. **Set up the systemd service** (first time only):
   ```bash
   sudo /opt/apps/Catoconsting/setup-service.sh
   ```

5. **Verify the service is running:**
   ```bash
   sudo systemctl status catoconsting
   ```

6. **Access your application:**
   - Local: `http://localhost` or `http://localhost:8080`
   - Remote: `http://<server-ip>`

### Service Management

Manage the Catoconsting systemd service with these commands:

```bash
# Start the service
sudo systemctl start catoconsting

# Stop the service
sudo systemctl stop catoconsting

# Restart the service
sudo systemctl restart catoconsting

# Check service status
sudo systemctl status catoconsting

# Enable service on boot
sudo systemctl enable catoconsting

# View service details
systemctl show catoconsting
```

### Log Files

Application logs are stored in `/opt/apps/Catoconsting/logs/`:
- `application.log` - Application logs (if configured in app)
- `service-stdout.log` - Service standard output
- `service-stderr.log` - Service error output

View logs:
```bash
# View latest log entries
tail -f /opt/apps/Catoconsting/logs/service-stdout.log

# View systemd journal logs
sudo journalctl -u catoconsting -f

# View last 50 lines
sudo journalctl -u catoconsting -n 50
```

### Nginx Configuration

Nginx is configured as a reverse proxy on port 80, forwarding requests to the Java application on port 8080.

Configuration file location:
- Debian/Ubuntu: `/etc/nginx/sites-available/catoconsting`
- RHEL/CentOS: `/etc/nginx/conf.d/catoconsting.conf`

Test and reload Nginx:
```bash
# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# Restart Nginx
sudo systemctl restart nginx
```

## Script Details

### setup-environment.ps1

**Main orchestration script** that determines which environment to set up.

**Parameters:**
- `-Environment` (Required) - Type of environment: `Desktop` or `Server`
- `-ComputerName` (Optional) - Identifier for the computer (defaults to hostname)

**Example:**
```powershell
.\setup-environment.ps1 -Environment Desktop -ComputerName "Dev-PC-01"
```

**Output:**
- Log file: `setup-log-<ComputerName>-<timestamp>.txt`

### setup-desktop.ps1

**Desktop development environment setup script.**

Called automatically by `setup-environment.ps1` when `-Environment Desktop` is specified.

**Features:**
- Installs development tools
- Configures Git
- Creates workspace directory
- Interactive prompts for Git configuration and repository cloning

### setup-server.ps1

**Windows Server deployment environment setup script.**

Called automatically by `setup-environment.ps1` when `-Environment Server` is specified.

**Features:**
- Installs server components
- Configures IIS
- Sets up firewall rules
- Creates deployment scripts
- Prepares application directory structure

### setup-environment.sh

**Main orchestration script for Linux/macOS** that determines which environment to set up.

**Parameters:**
- `-e` (Required) - Type of environment: `Desktop` or `Server`
- `-n` (Optional) - Identifier for the computer (defaults to hostname)
- `-h` - Show help message

**Example:**
```bash
./setup-environment.sh -e Desktop -n "Dev-Mac-01"
```

**Output:**
- Log file: `setup-log-<ComputerName>-<timestamp>.txt`

### setup-desktop.sh

**Desktop development environment setup script for Linux/macOS.**

Called automatically by `setup-environment.sh` when `-e Desktop` is specified.

**Features:**
- Detects operating system (macOS, Debian, or RHEL-based)
- Installs development tools
- Configures Git
- Creates workspace directory
- Interactive prompts for Git configuration and repository cloning

**Supported Systems:**
- macOS 10.15+ (Catalina and newer)
- Ubuntu 20.04+ / Debian 10+
- RHEL/CentOS 8+ / Fedora 34+

### setup-server.sh

**Linux server deployment environment setup script.**

Called automatically by `setup-environment.sh` when `-e Server` is specified.

**Features:**
- Installs server components (Java, Nginx)
- Configures Nginx as reverse proxy
- Sets up firewall rules (UFW or firewalld)
- Creates systemd service configuration
- Prepares application directory structure

**Supported Systems:**
- Ubuntu 20.04+ / Debian 10+
- RHEL/CentOS 8+ / Fedora 34+

## Troubleshooting

### Common Issues

#### Windows Issues

##### 1. "Execution Policy" Error

**Error:**
```
.\setup-environment.ps1 : File cannot be loaded because running scripts is disabled
```

**Solution:**
Run as Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

##### 2. Chocolatey Installation Fails

**Symptoms:** Script hangs or fails during Chocolatey installation

**Solutions:**
- Check your internet connection
- Temporarily disable antivirus
- Run PowerShell as Administrator
- Manually install Chocolatey first: https://chocolatey.org/install

##### 3. Java Not Found After Installation

**Solution:**
```powershell
# Refresh environment variables
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Or restart your terminal
```

##### 4. Git Configuration Prompts Don't Appear

If Git is already configured, the script won't prompt you. To reconfigure:

```powershell
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

##### 5. Windows Service Won't Start

**Check the logs:**
```powershell
Get-Content C:\Apps\Catoconsting\logs\service-stderr.log
```

**Common causes:**
- JAR file not found or corrupted
- Port 8080 already in use
- Insufficient permissions
- Java not properly configured

**Solutions:**
```powershell
# Check if port is in use
Get-NetTCPConnection -LocalPort 8080

# Verify JAR file exists
Test-Path C:\Apps\Catoconsting\app.jar

# Test JAR manually
java -jar C:\Apps\Catoconsting\app.jar
```

#### Linux/macOS Issues

##### 1. Permission Denied on Script Execution

**Error:**
```
bash: ./setup-environment.sh: Permission denied
```

**Solution:**
```bash
chmod +x setup-environment.sh setup-desktop.sh setup-server.sh
```

##### 2. Homebrew Installation Fails (macOS)

**Symptoms:** Script hangs or fails during Homebrew installation

**Solutions:**
- Check your internet connection
- Ensure Xcode Command Line Tools are installed: `xcode-select --install`
- Manually install Homebrew first: https://brew.sh

##### 3. Java Not Found After Installation

**Solution:**
```bash
# Source your shell profile
source ~/.bashrc  # For bash
source ~/.zshrc   # For zsh

# Or restart your terminal
```

##### 4. Package Manager Not Supported

**Error:** "Unsupported operating system"

**Solution:**
- Ensure you're running a supported OS (Ubuntu 20.04+, RHEL 8+, macOS 10.15+)
- Manually install Java 17, Maven, and Git using your system's package manager

##### 5. Systemd Service Won't Start (Linux Server)

**Check the logs:**
```bash
sudo journalctl -u catoconsting -n 50
tail -f /opt/apps/Catoconsting/logs/service-stderr.log
```

**Common causes:**
- JAR file not found or corrupted
- Port 8080 already in use
- Insufficient permissions
- Java not properly configured

**Solutions:**
```bash
# Check if port is in use
sudo netstat -tlnp | grep 8080

# Verify JAR file exists
ls -l /opt/apps/Catoconsting/app.jar

# Test JAR manually
java -jar /opt/apps/Catoconsting/app.jar
```

##### 6. Nginx Configuration Errors

**Test Nginx configuration:**
```bash
sudo nginx -t
```

**View Nginx error logs:**
```bash
sudo tail -f /var/log/nginx/error.log
```

### Getting Help

1. **Check log files** - All operations are logged with timestamps
   - Desktop: `setup-log-<ComputerName>-<timestamp>.txt`
   - Windows Server: Same location plus `C:\Apps\Catoconsting\logs\`
   - Linux Server: `/opt/apps/Catoconsting/logs/`

2. **Verify installations manually:**
   
   **Windows:**
   ```powershell
   # Check Java
   java -version

   # Check Maven (desktop only)
   mvn -version

   # Check Git (desktop only)
   git --version

   # Check IIS (server only)
   Get-Service W3SVC
   ```
   
   **Linux/macOS:**
   ```bash
   # Check Java
   java -version

   # Check Maven (desktop only)
   mvn -version

   # Check Git (desktop only)
   git --version

   # Check Nginx (server only)
   sudo systemctl status nginx
   ```

3. **Review Windows Event Viewer** for service-related issues
   - Open Event Viewer: `eventvwr.msc`
   - Check: Windows Logs > Application

## Post-Setup Tasks

### For Desktop PCs

1. **Configure Git SSH keys** (for GitHub access):
   ```powershell
   ssh-keygen -t ed25519 -C "your.email@example.com"
   ```
   Add the public key to your GitHub account.

2. **Install additional development tools** (optional):
   ```powershell
   choco install postman -y          # API testing
   choco install dbeaver -y          # Database client
   choco install docker-desktop -y   # Docker (if needed)
   ```

3. **Configure Maven settings** (if using private repositories):
   Edit `%USERPROFILE%\.m2\settings.xml`

4. **Set up IDE preferences** in Visual Studio Code

### For Windows Server VM

1. **Configure SSL/TLS certificates** (for HTTPS):
   - Obtain SSL certificate
   - Import to Windows certificate store
   - Configure IIS binding

2. **Set up monitoring** (optional):
   ```powershell
   # Install monitoring tools
   choco install datadog-agent -y  # Or your preferred monitoring solution
   ```

3. **Configure backup strategy:**
   - Application directory: `C:\Apps\Catoconsting`
   - Configuration files
   - Log files (or set up log rotation)

4. **Harden server security:**
   - Configure Windows Firewall
   - Set up Windows Updates
   - Enable Windows Defender
   - Implement least-privilege access

5. **Set up reverse proxy** (optional, for production):
   Configure IIS as reverse proxy to Java application using URL Rewrite module

## Architecture Overview

### Development Workflow (Desktop PCs)

```
Developer Workstation (Desktop-1 or Desktop-2)
    ↓
  Clone Repository
    ↓
  Write Code (VS Code)
    ↓
  Build & Test (Maven)
    ↓
  Commit & Push (Git)
    ↓
  CI/CD Pipeline (GitHub Actions)
    ↓
  Deploy to Server
```

### Server Deployment (Windows Server VM)

```
GitHub Actions / Manual Deployment
    ↓
  JAR File → Server
    ↓
  deploy.ps1 script
    ↓
  Windows Service (NSSM)
    ↓
  Java Application (Port 8080)
    ↓
  [Optional] IIS Reverse Proxy
    ↓
  External Access (Port 80/443)
```

## Security Considerations

1. **Keep systems updated:**
   ```powershell
   # Update Chocolatey packages
   choco upgrade all -y
   ```

2. **Use strong passwords** for service accounts

3. **Restrict firewall rules** to only necessary ports

4. **Regular backups** of application and configuration

5. **Monitor logs** for suspicious activity

6. **Use HTTPS** in production environments

7. **Implement proper authentication** in your application

## Additional Resources

- [Maven Documentation](https://maven.apache.org/guides/)
- [Java 17 Documentation](https://docs.oracle.com/en/java/javase/17/)
- [Git Documentation](https://git-scm.com/doc)
- [IIS Documentation](https://docs.microsoft.com/en-us/iis/)
- [NSSM Documentation](https://nssm.cc/usage)

## License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review log files for detailed error messages
3. Consult the application documentation
4. Contact your system administrator

---

**Last Updated:** 2025-12-25
**Script Version:** 1.0.0
