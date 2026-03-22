$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverPath = Join-Path $root "prototype/server.py"

if (-not (Test-Path $serverPath)) {
  throw "Cannot find prototype/server.py"
}

Write-Host "Starting Party Pool prototype server..."
Write-Host "Host page:      http://localhost:8000/host.html"
Write-Host "Controller page: http://localhost:8000/controller.html"

wsl python3 "/home/walker/project/party-pool/prototype/server.py"
