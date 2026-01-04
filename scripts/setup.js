const { spawn } = require('child_process');
const path = require('path');

console.warn('[Deprecated] scripts/setup.js is deprecated. Redirecting to scripts/setup-ai.js...');

const child = spawn(process.execPath, [path.join(__dirname, 'setup-ai.js')], { stdio: 'inherit' });
child.on('close', (code) => process.exit(code));