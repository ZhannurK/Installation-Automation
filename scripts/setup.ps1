$ErrorActionPreference = "Stop"
$LogFile = ".mcp\setup-ai.log"

# Функция логирования
function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$TimeStamp] $Message"
    Write-Host $Message
    Add-Content -Path $LogFile -Value $LogEntry -Force
}

# Создание лог-файла
New-Item -ItemType File -Path $LogFile -Force | Out-Null
Write-Log "=========================================="
Write-Log "Starting AI Setup (Windows)"
Write-Log "=========================================="

# 1. Проверка системных требований
Write-Log "[Check] Checking system requirements..."

# RAM
$RAM = Get-CimInstance Win32_ComputerSystem
$RAM_GB = [math]::Round($RAM.TotalPhysicalMemory / 1GB)
if ($RAM_GB -lt 8) {
    Write-Log "[Error] Need at least 8GB RAM. Found: $RAM_GB GB"
    exit 1
}
Write-Log "[OK] RAM: $RAM_GB GB"

# Disk (Текущий диск)
$Drive = Get-PSDrive -Name (Get-Location).Drive.Name
$FreeSpace_GB = [math]::Round($Drive.Free / 1GB)
if ($FreeSpace_GB -lt 10) {
    Write-Log "[Error] Need at least 10GB free disk space. Found: $FreeSpace_GB GB"
    exit 1
}
Write-Log "[OK] Free Disk: $FreeSpace_GB GB"

# 2. Установка Ollama
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Log "[Skip] Ollama is already installed."
} else {
    Write-Log "[Install] Downloading OllamaSetup.exe..."
    $InstallerUrl = "https://ollama.com/download/OllamaSetup.exe"
    $InstallerPath = "$env:TEMP\OllamaSetup.exe"
    
    try {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath
        Write-Log "[Install] Running installer (Silent)..."
        # Запуск установки. /silent может не работать идеально на всех версиях,
        # но это стандартный флаг Inno Setup (который использует Ollama)
        Start-Process -FilePath $InstallerPath -ArgumentList "/silent" -Wait
        
        # Обновляем Path в текущей сессии
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
             Write-Log "[Warning] Ollama installed, but might require a terminal restart to be visible."
        }
    } catch {
        Write-Log "[Error] Failed to install Ollama: $_"
        exit 1
    }
}

# 3. Запуск и Проверка сервиса
Write-Log "[Service] Checking connection to localhost:11434..."

# В Windows Ollama устанавливается как приложение в трее.
# Попробуем запустить его, если порт недоступен.
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434" -Method Head -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
        Write-Log "[OK] Ollama is running."
    }
} catch {
    Write-Log "[Start] Starting Ollama app..."
    # Попытка запустить через ярлык или напрямую
    try {
         Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
         Start-Sleep -Seconds 5
    } catch {
         Write-Log "[Warning] Could not auto-start Ollama serve. Please ensure Ollama app is running."
    }
}

# Финальная проверка
try {
    Invoke-WebRequest -Uri "http://localhost:11434" -Method Head | Out-Null
    Write-Log "[OK] Service is reachable."
} catch {
    Write-Log "[Error] Ollama service not responding at http://localhost:11434"
    exit 1
}

# 4. Скачивание модели
$ModelName = "qwen2.5-coder"
Write-Log "[Model] Checking for model: $ModelName..."

$ListOutput = ollama list | Out-String
if ($ListOutput -match $ModelName) {
    Write-Log "[Skip] Model $ModelName is already available."
} else {
    Write-Log "[Download] Pulling $ModelName (Please wait)..."
    ollama pull $ModelName
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[Error] Failed to pull model."
        exit 1
    }
}

Write-Log "[Success] Setup complete."