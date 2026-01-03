const { spawn } = require('child_process');
const os = require('os');
const path = require('path');
const fs = require('fs');

// Создаем директорию для логов, если нет
const logDir = path.join(process.cwd(), '.mcp');
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir, { recursive: true });
}

const platform = os.platform();
let scriptPath;
let command;
let args = [];

console.log(`\x1b[36m[AI Setup]\x1b[0m Обнаружена платформа: ${platform}`);

if (platform === 'win32') {
    scriptPath = path.join(__dirname, 'setup-ai.ps1');
    command = 'powershell.exe';
    args = ['-ExecutionPolicy', 'Bypass', '-File', scriptPath];
} else if (platform === 'linux' || platform === 'darwin') {
    scriptPath = path.join(__dirname, 'setup-ai.sh');
    // Делаем скрипт исполняемым
    fs.chmodSync(scriptPath, '755');
    command = '/bin/bash';
    args = [scriptPath];
} else {
    console.error('\x1b[31m[Error]\x1b[0m Неподдерживаемая ОС');
    process.exit(1);
}

console.log(`\x1b[36m[AI Setup]\x1b[0m Запуск установочного скрипта...`);

const child = spawn(command, args, { stdio: 'inherit' });

child.on('close', (code) => {
    if (code === 0) {
        console.log(`\n\x1b[32m[Success]\x1b[0m AI окружение (Ollama + Qwen) готово к работе!`);
    } else {
        console.error(`\n\x1b[31m[Error]\x1b[0m Установка завершилась с ошибкой. Код: ${code}`);
        console.log(`Проверьте логи в .mcp/setup-ai.log`);
    }
    process.exit(code);
});