#!/bin/bash

# Настройка логирования
LOG_FILE=".mcp/setup-ai.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Starting AI Setup: $(date)"
echo "=========================================="

# 1. Проверка системных требований
echo "[Check] Checking system requirements..."

# Проверка RAM (минимум 8GB)
if [[ "$OSTYPE" == "darwin"* ]]; then
    TOTAL_RAM_GB=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
else
    TOTAL_RAM_GB=$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / 1024 / 1024 / 1024))
fi

if [ "$TOTAL_RAM_GB" -lt 8 ]; then
    echo "[Error] Need at least 8GB RAM. Found: ${TOTAL_RAM_GB}GB"
    exit 1
fi
echo "[OK] RAM: ${TOTAL_RAM_GB}GB"

# Проверка места на диске (минимум 10GB в текущей директории)
FREE_DISK_GB=$(df -Pk . | awk 'NR==2 {print $4}' | awk '{print int($1/1024/1024)}')
if [ "$FREE_DISK_GB" -lt 10 ]; then
    echo "[Error] Need at least 10GB free disk space. Found: ${FREE_DISK_GB}GB"
    exit 1
fi
echo "[OK] Free Disk: ${FREE_DISK_GB}GB"

# Проверка curl
if ! command -v curl &> /dev/null; then
    echo "[Error] curl is required but not installed."
    exit 1
fi

# 2. Установка Ollama
if command -v ollama &> /dev/null; then
    echo "[Skip] Ollama is already installed."
else
    echo "[Install] Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
    if [ $? -ne 0 ]; then
        echo "[Error] Failed to install Ollama."
        exit 1
    fi
fi

# 3. Запуск сервиса (фоновый процесс)
echo "[Service] Ensuring Ollama is running..."
if pgrep -x "ollama" > /dev/null; then
    echo "[OK] Ollama is already running."
else
    echo "[Start] Starting Ollama serve..."
    ollama serve > /dev/null 2>&1 &
    # Даем время на запуск
    sleep 5
fi

# Проверка доступности API
MAX_RETRIES=5
COUNT=0
echo "[Check] Verifying connection to http://localhost:11434..."
while [ $COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:11434 > /dev/null; then
        echo "[OK] Ollama service is reachable."
        break
    fi
    echo "Waiting for Ollama..."
    sleep 2
    COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "[Error] Could not connect to Ollama."
    exit 1
fi

# 4. Скачивание модели Qwen Code
# Используем qwen2.5-coder, так как это актуальная версия "Qwen Code"
MODEL_NAME="qwen2.5-coder"

echo "[Model] Checking for model: $MODEL_NAME..."
if ollama list | grep -q "$MODEL_NAME"; then
    echo "[Skip] Model $MODEL_NAME is already available."
else
    echo "[Download] Pulling $MODEL_NAME (this may take a while)..."
    ollama pull $MODEL_NAME
    if [ $? -ne 0 ]; then
        echo "[Error] Failed to pull model."
        exit 1
    fi
fi

echo "[Success] Setup complete. Log saved to $LOG_FILE"