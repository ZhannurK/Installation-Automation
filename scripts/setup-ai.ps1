$ErrorActionPreference = "Stop"
$LogFile = ".mcp\setup-ai.log"

# Log function
function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] $Message"
    Write-Host $Message
    Add-Content -Path $LogFile -Value $LogEntry -Force
}

# Create log file
New-Item -ItemType File -Path $LogFile -Force | Out-Null
# Start transcript to capture all console output (including warnings/prompts)
try {
    Start-Transcript -Path $LogFile -Append -Force | Out-Null
} catch {
    Write-Log "[Warning] Start-Transcript failed: $_"
}
Write-Log "=========================================="
Write-Log "Starting AI Setup (Windows)"
Write-Log "=========================================="

# 1. Check requirements
Write-Log "[Check] Checking system requirements..."

# RAM
$RAM = Get-CimInstance Win32_ComputerSystem
$RAM_GB = [math]::Round($RAM.TotalPhysicalMemory / 1GB)
if ($RAM_GB -lt 8) {
    Write-Log "[Error] Need at least 8GB RAM. Found: $RAM_GB GB"
    exit 1
}
Write-Log "[OK] RAM: $RAM_GB GB"

# Disk
$Drive = Get-PSDrive -Name (Get-Location).Drive.Name
$FreeSpace_GB = [math]::Round($Drive.Free / 1GB)
if ($FreeSpace_GB -lt 10) {
    Write-Log "[Error] Need at least 10GB free disk space. Found: $FreeSpace_GB GB"
    exit 1
}
Write-Log "[OK] Free Disk: $FreeSpace_GB GB"

# 2. Install Ollama (robust detection)
$installed = $false
try {
    $ver = & ollama --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $ver) {
        Write-Log "[Skip] Ollama CLI available: $ver"
        $installed = $true
    }
} catch {
    # ignore
}

if (-not $installed) {
    # Try to locate common install paths
    $candidates = @("$env:ProgramFiles\Ollama","$env:ProgramFiles(x86)\Ollama","$env:LOCALAPPDATA\Programs\Ollama")
    foreach ($cand in $candidates) {
        $exe = Join-Path $cand "ollama.exe"
        if (Test-Path $exe) {
            Write-Log "[Info] Found Ollama at $exe - adding to PATH for session"
            $env:Path = $env:Path + ";" + (Split-Path $exe)
            try {
                $ver = & ollama --version 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "[Skip] Ollama CLI available after adding path: $ver"
                    $installed = $true
                    break
                }
            } catch {
                # ignore
            }
        }
    }
}

if (-not $installed) {
    Write-Log "[Install] Downloading OllamaSetup.exe..."
    $InstallerUrl = "https://ollama.com/download/OllamaSetup.exe"
    $InstallerPath = "$env:TEMP\OllamaSetup.exe"
    try {
        # Use -UseBasicParsing to avoid interactive security prompts on Windows PowerShell
Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
        Write-Log "[Install] Running installer (Silent)..."
        Start-Process -FilePath $InstallerPath -ArgumentList "/silent" -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        try {
            $ver = & ollama --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "[OK] Ollama CLI is now available: $ver"
            } else {
                Write-Log "[Warning] Ollama installed but CLI not detected. A terminal restart may be required."
            }
        } catch {
            Write-Log "[Warning] Ollama installed but could not verify CLI version."
        }
    } catch {
        Write-Log "[Error] Failed to install Ollama: $_"
        exit 1
    }
}

# 3. Ensure service
Write-Log "[Service] Checking connection to localhost:11434..."
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434" -Method Head -UseBasicParsing -ErrorAction SilentlyContinue
    if ($response -and $response.StatusCode -eq 200) {
        Write-Log "[OK] Ollama is running."
    }
} catch {
    Write-Log "[Start] Starting Ollama app..."
    try {
         Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
         Start-Sleep -Seconds 5
    } catch {
         Write-Log "[Warning] Could not auto-start Ollama serve. Please ensure Ollama app is running."
    }
}

# Final check
try {
    Invoke-WebRequest -Uri "http://localhost:11434" -Method Head -UseBasicParsing | Out-Null
    Write-Log "[OK] Service is reachable."
} catch {
    Write-Log "[Error] Ollama service not responding at http://localhost:11434"
    exit 1
}

# Stop transcript if it started
try {
    Stop-Transcript | Out-Null
} catch {
    # ignore
}

# 4. Pull model
$ModelName = "qwen:code"
$AltModel = "qwen2.5-coder"
Write-Log "[Model] Checking for model: $ModelName (or $AltModel)..."
$ListOutput = ollama list | Out-String
if ($ListOutput -match $ModelName -or $ListOutput -match $AltModel) {
    Write-Log "[Skip] Model is already available."
} else {
    Write-Log "[Download] Pulling $ModelName (Please wait)..."
    ollama pull $ModelName
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[Warning] Failed to pull $ModelName, trying $AltModel..."
        ollama pull $AltModel
        if ($LASTEXITCODE -ne 0) {
            Write-Log "[Error] Failed to pull model ($ModelName or $AltModel)."
            exit 1
        }
    }
}

Write-Log "[Success] Setup complete."