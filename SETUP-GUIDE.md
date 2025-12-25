# Catoconsting Environment Setup Guide

Automated setup scripts for configuring development and deployment environments for the Catoconsting Java web application.

## Overview

This repository includes PowerShell scripts to set up:
- **2 Desktop PCs** - Development environments with full Java development toolchain
- **1 Windows Server VM** - Production/staging deployment environment

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Desktop PC Setup](#desktop-pc-setup)
- [Windows Server VM Setup](#windows-server-vm-setup)
- [Script Details](#script-details)
- [Troubleshooting](#troubleshooting)
- [Post-Setup Tasks](#post-setup-tasks)

## Prerequisites

### All Systems
- Windows 10/11 (for desktops) or Windows Server 2016+ (for server)
- Administrator privileges
- Internet connection for downloading packages
- PowerShell 5.1 or higher

### Recommended
- At least 8 GB RAM
- 20 GB free disk space
- Antivirus temporarily disabled during installation (to prevent blocking package installations)

## Quick Start

### For Desktop PCs (Development Environment)

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

### For Windows Server VM (Deployment Environment)

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

## Troubleshooting

### Common Issues

#### 1. "Execution Policy" Error

**Error:**
```
.\setup-environment.ps1 : File cannot be loaded because running scripts is disabled
```

**Solution:**
Run as Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### 2. Chocolatey Installation Fails

**Symptoms:** Script hangs or fails during Chocolatey installation

**Solutions:**
- Check your internet connection
- Temporarily disable antivirus
- Run PowerShell as Administrator
- Manually install Chocolatey first: https://chocolatey.org/install

#### 3. Java Not Found After Installation

**Solution:**
```powershell
# Refresh environment variables
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Or restart your terminal
```

#### 4. Git Configuration Prompts Don't Appear

If Git is already configured, the script won't prompt you. To reconfigure:

```powershell
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

#### 5. Windows Service Won't Start

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

### Getting Help

1. **Check log files** - All operations are logged with timestamps
   - Desktop: `setup-log-<ComputerName>-<timestamp>.txt`
   - Server: Same location plus `C:\Apps\Catoconsting\logs\`

2. **Verify installations manually:**
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
