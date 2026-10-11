<#
.SYNOPSIS
    Start the http-server web server
.DESCRIPTION
    Convenience script to start http-server with common options.
    Install http-server first with setup-webserver.ps1.
.PARAMETER Port
    Port number (default: 8080)
.PARAMETER Directory
    Directory to serve (default: current directory)
.PARAMETER Address
    Address to listen on (default: 127.0.0.1, this computer only). Use 0.0.0.0
    to share the directory with other machines on the network.
.PARAMETER Open
    Open browser automatically
.EXAMPLE
    .\start-webserver.ps1
.EXAMPLE
    .\start-webserver.ps1 -Port 3000 -Open
.EXAMPLE
    .\start-webserver.ps1 -Directory "C:\path\to\files" -Address 0.0.0.0
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive script')]
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [Parameter(Mandatory=$false)]
    [string]$Directory = (Get-Location).Path,

    [Parameter(Mandatory=$false)]
    [string]$Address = "127.0.0.1",

    [Parameter(Mandatory=$false)]
    [switch]$Open
)

if (-not (Get-Command http-server -ErrorAction SilentlyContinue)) {
    Write-Error "http-server is not installed. Run .\setup-webserver.ps1 first."
    exit 1
}
if (-not (Test-Path -Path $Directory -PathType Container)) {
    Write-Error "Directory not found: $Directory"
    exit 1
}

$browseHost = if ($Address -in '0.0.0.0', '::') { 'localhost' } else { $Address }
Write-Host "Starting web server..." -ForegroundColor Cyan
Write-Host "Directory: $Directory" -ForegroundColor Yellow
Write-Host "Port: $Port" -ForegroundColor Yellow
Write-Host "URL: http://${browseHost}:$Port" -ForegroundColor Green
if ($browseHost -ne $Address) {
    Write-Host "Listening on all networks; other machines can reach this directory" -ForegroundColor Yellow
}
Write-Host "`nPress Ctrl+C to stop the server`n" -ForegroundColor Yellow

# Serve the directory by path rather than changing this shell's location
$serverArgs = @($Directory, "-a", $Address, "-p", $Port)
if ($Open) {
    $serverArgs += "-o"
}

& http-server @serverArgs
exit $LASTEXITCODE
