#!/usr/bin/env bash

# Setup AI stack (Ollama + Qwen) for Linux/macOS
# Logs to .mcp/setup-ai.log

LOG_FILE=".mcp/setup-ai.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Starting AI Setup (Unix) : $(date)"
echo "=========================================="

# 1. Check requirements
echo "[Check] Checking system requirements..."

# RAM >= 8GB
if [[ "$OSTYPE" == "darwin"* ]]; then
    TOTAL_RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
else
    TOTAL_RAM_GB=$(( ( $(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) ) / 1024 / 1024 / 1024 ))
fi

if [ "$TOTAL_RAM_GB" -lt 8 ]; then
    echo "[Error] Need at least 8GB RAM. Found: ${TOTAL_RAM_GB}GB"
    exit 1
fi
echo "[OK] RAM: ${TOTAL_RAM_GB}GB"

# Disk >= 10GB available in current mount
FREE_DISK_GB=$(df -Pk . | awk 'NR==2 {printf("%d", $4/1024/1024)}')
if [ "$FREE_DISK_GB" -lt 10 ]; then
    echo "[Error] Need at least 10GB free disk space. Found: ${FREE_DISK_GB}GB"
    exit 1
fi
echo "[OK] Free Disk: ${FREE_DISK_GB}GB"

# Check curl or wget
DOWNLOAD_CMD=""
if command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl"
elif command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget"
else
    echo "[Error] curl or wget is required but not installed."
    exit 1
fi

# helper to fetch URL
fetch() {
    URL="$1"
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        curl -fsSL "$URL"
    else
        wget -qO- "$URL"
    fi
}

# 2. Install Ollama if missing (robust detection)
DO_INSTALL=0
# Prefer to run 'ollama --version' to verify a working CLI
if command -v ollama &> /dev/null; then
    if ollama --version >/dev/null 2>&1; then
        VERS=$(ollama --version 2>/dev/null | head -n1)
        echo "[Skip] Ollama CLI is available: ${VERS}"
    else
        echo "[Warning] 'ollama' detected but '--version' failed; will attempt install."
        DO_INSTALL=1
    fi
else
    # Search common install locations and add to PATH if found
    FOUND_PATH=""
    for p in /usr/local/bin /opt/homebrew/bin /usr/bin /snap/bin /home/linuxbrew/.linuxbrew/bin; do
        if [ -x "$p/ollama" ]; then
            FOUND_PATH="$p"
            break
        fi
    done

    if [ -n "$FOUND_PATH" ]; then
        echo "[Info] Found Ollama binary in $FOUND_PATH, adding to PATH for this session"
        export PATH="$FOUND_PATH:$PATH"
        if ollama --version >/dev/null 2>&1; then
            VERS=$(ollama --version 2>/dev/null | head -n1)
            echo "[Skip] Ollama CLI is available after adding $FOUND_PATH: ${VERS}"
        else
            echo "[Warning] Found binary but '--version' failed; will attempt install."
            DO_INSTALL=1
        fi
    else
        DO_INSTALL=1
    fi
fi

if [ "$DO_INSTALL" -eq 1 ]; then
    echo "[Install] Installing Ollama..."
    fetch https://ollama.com/install.sh | sh
    if [ $? -ne 0 ]; then
        echo "[Error] Failed to install Ollama."
        exit 1
    fi
fi

# 3. Ensure service is running
echo "[Service] Ensuring Ollama is running..."
if pgrep -x "ollama" > /dev/null; then
    echo "[OK] Ollama is already running."
else
    echo "[Start] Starting Ollama serve..."
    # Start in background
    ollama serve > /dev/null 2>&1 &
    sleep 5
fi

# Check service availability
MAX_RETRIES=10
COUNT=0
echo "[Check] Verifying connection to http://localhost:11434..."
while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ "$DOWNLOAD_CMD" = "curl" ]; then
        if curl -s --head http://localhost:11434 | head -n 1 | grep -q "HTTP"; then
            echo "[OK] Ollama service is reachable."
            break
        fi
    else
        if wget -q --spider http://localhost:11434; then
            echo "[OK] Ollama service is reachable."
            break
        fi
    fi
    echo "Waiting for Ollama..."
    sleep 2
    COUNT=$((COUNT+1))
done

if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "[Error] Could not connect to Ollama."
    exit 1
fi

# 4. Pull model (standardize to qwen:code)
MODEL_NAME="qwen:code"
ALT_MODEL="qwen2.5-coder"

echo "[Model] Checking for model: $MODEL_NAME (or $ALT_MODEL)..."
LIST_OUTPUT=$(ollama list 2>/dev/null || true)
if echo "$LIST_OUTPUT" | grep -q "$MODEL_NAME" || echo "$LIST_OUTPUT" | grep -q "$ALT_MODEL"; then
    echo "[Skip] Model is already available."
else
    echo "[Download] Pulling $MODEL_NAME (this may take a while)..."
    if ! ollama pull $MODEL_NAME; then
        echo "[Warning] Failed to pull $MODEL_NAME, trying $ALT_MODEL..."
        if ! ollama pull $ALT_MODEL; then
            echo "[Error] Failed to pull model ($MODEL_NAME or $ALT_MODEL)."
            exit 1
        fi
    fi
fi

echo "[Success] Setup complete. Log saved to $LOG_FILE"
