# CatoRepository

Automated setup scripts for the Catoconsting Java web application development and deployment environments.

## Quick Start

### Universal Setup Script (Recommended)

Use the universal setup script that automatically detects your platform:

```bash
# For development environment
./setup.sh -e Desktop

# For server environment
sudo ./setup.sh -e Server
```

### Platform-Specific Scripts

#### Windows

```powershell
# Development environment
.\setup-environment.ps1 -Environment Desktop -ComputerName "Dev-PC-01"

# Server environment
.\setup-environment.ps1 -Environment Server -ComputerName "Server-VM"
```

#### Linux/macOS

```bash
# Development environment
./setup-environment.sh -e Desktop -n "Dev-Mac-01"

# Server environment (requires sudo)
sudo ./setup-environment.sh -e Server -n "Ubuntu-Server"
```

## What Gets Installed

### Desktop/Development Environment

- **Java JDK 17** - OpenJDK distribution
- **Apache Maven** - Build and dependency management
- **Git** - Version control system
- **Visual Studio Code** - Code editor with Java extensions
- **Package Manager** - Chocolatey (Windows), Homebrew (macOS), apt/dnf (Linux)

### Server/Deployment Environment

#### Windows Server
- Java JDK 17
- IIS Web Server with URL Rewrite
- NSSM (Service Manager)
- Firewall rules configuration

#### Linux Server
- Java JDK 17
- Nginx Web Server (reverse proxy)
- Systemd service configuration
- Firewall rules (UFW/firewalld)

## Supported Platforms

### Desktop/Development
- Windows 10/11
- macOS 10.15+ (Catalina and newer)
- Ubuntu 20.04+ / Debian 10+
- RHEL/CentOS 8+ / Fedora 34+

### Server/Deployment
- Windows Server 2016+
- Ubuntu 20.04+ / Debian 10+
- RHEL/CentOS 8+ / Fedora 34+

## Documentation

For detailed instructions, troubleshooting, and advanced configuration, see [SETUP-GUIDE.md](SETUP-GUIDE.md).

## Requirements

- Administrator/sudo privileges
- Internet connection
- 8 GB RAM (recommended)
- 20 GB free disk space

## Directory Structure

After setup, workspaces are created at:
- **Windows Desktop**: `C:\Users\<YourName>\CatoWorkspace`
- **Linux/macOS Desktop**: `~/CatoWorkspace`
- **Windows Server**: `C:\Apps\Catoconsting`
- **Linux Server**: `/opt/apps/Catoconsting`

## Post-Setup

### Development Environment

1. Restart your terminal
2. Navigate to workspace
3. Clone repository (if not done during setup)
4. Build project: `mvn clean install`

### Server Environment

1. Build application: `mvn clean package`
2. Deploy JAR file using provided deployment script
3. Set up service (first time only)
4. Access application at `http://localhost` or `http://<server-ip>`

## Troubleshooting

Common issues and solutions are documented in [SETUP-GUIDE.md](SETUP-GUIDE.md#troubleshooting).

Quick checks:
```bash
# Verify Java
java -version

# Verify Maven (desktop only)
mvn -version

# Verify Git
git --version
```

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please ensure all scripts are tested on supported platforms before submitting pull requests.
