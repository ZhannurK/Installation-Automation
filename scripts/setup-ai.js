const { spawn } = require('child_process');
const os = require('os');
const path = require('path');
const fs = require('fs');

// Ensure log directory
const logDir = path.join(process.cwd(), '.mcp');
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
}

const platform = os.platform();
let scriptPath;
let command;
let args = [];

// Create log stream to append Node-level messages
const LOG_FILE = path.join(process.cwd(), '.mcp', 'setup-ai.log');
const logStream = fs.createWriteStream(LOG_FILE, { flags: 'a' });
function writeLog(msg) {
    const line = `${new Date().toISOString()} ${msg}\n`;
    logStream.write(line);
}

console.log(`\x1b[36m[AI Setup]\x1b[0m Detected platform: ${platform}`);
writeLog(`[AI Setup] Detected platform: ${platform}`);

if (platform === 'win32') {
    scriptPath = path.join(__dirname, 'setup-ai.ps1');
    if (!fs.existsSync(scriptPath)) {
        console.error('\x1b[31m[Error]\x1b[0m Missing script: scripts/setup-ai.ps1');
        writeLog('[Error] Missing script: scripts/setup-ai.ps1');
        process.exit(1);
    }
    command = 'powershell.exe';
    args = ['-ExecutionPolicy', 'Bypass', '-File', scriptPath];
} else if (platform === 'linux' || platform === 'darwin') {
    scriptPath = path.join(__dirname, 'setup-ai.sh');
    if (!fs.existsSync(scriptPath)) {
        console.error('\x1b[31m[Error]\x1b[0m Missing script: scripts/setup-ai.sh');
        writeLog('[Error] Missing script: scripts/setup-ai.sh');
        process.exit(1);
    }
    try {
        fs.chmodSync(scriptPath, 0o755);
    } catch (e) {
        console.warn('\x1b[33m[Warning]\x1b[0m Failed to chmod script (continuing):', e.message);
        writeLog(`[Warning] Failed to chmod script: ${e.message}`);
    }
    command = '/bin/bash';
    args = [scriptPath];
} else {
    console.error('\x1b[31m[Error]\x1b[0m Unsupported OS');
    writeLog('[Error] Unsupported OS');
    process.exit(1);
}

console.log(`\x1b[36m[AI Setup]\x1b[0m Running installer script: ${path.basename(scriptPath)}`);
writeLog(`[AI Setup] Running installer script: ${path.basename(scriptPath)}`);

// Spawn child with pipes for stdout/stderr so we can capture everything
const child = spawn(command, args, { stdio: ['inherit', 'pipe', 'pipe'] });

// Pipe child's stdout and stderr to console. On non-Windows we also append to logStream because Unix script already redirects to log.
child.stdout.on('data', (data) => {
    process.stdout.write(data);
    if (platform !== 'win32') {
        logStream.write(data);
    }
});
child.stderr.on('data', (data) => {
    process.stderr.write(data);
    if (platform !== 'win32') {
        logStream.write(data);
    }
});

child.on('close', (code) => {
    if (code === 0) {
        console.log(`\n\x1b[32m[Success]\x1b[0m AI environment (Ollama + Qwen) is ready!`);
        writeLog('[Success] AI environment (Ollama + Qwen) is ready!');
    } else {
        console.error(`\n\x1b[31m[Error]\x1b[0m Installation finished with error code: ${code}`);
        writeLog(`[Error] Installation finished with error code: ${code}`);
        console.log(`Check the logs in .mcp/setup-ai.log`);
        writeLog('Check the logs in .mcp/setup-ai.log');
    }
    logStream.end();
    process.exit(code);
});