#!/usr/bin/env node
// Claude Needs You — interactive settings (zero dependencies)

import { readFileSync, writeFileSync, mkdirSync, unlinkSync, renameSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { stdin, stdout } from 'process';

if (!stdin.isTTY) {
  console.error('This script must be run in a terminal (not piped or inside Claude Code).');
  console.error('Open a terminal and run:  ~/.config/claude-needs-you/settings');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// ANSI helpers
// ---------------------------------------------------------------------------
const esc = (code) => `\x1b[${code}m`;
const c = {
  reset: esc(0),
  bold: esc(1),
  dim: esc(2),
  cyan: esc(36),
  green: esc(32),
  yellow: esc(33),
  magenta: esc(35),
  white: esc(37),
  gray: esc(90),
  bgCyan: esc(46),
  bgGreen: esc(42),
  black: esc(30),
};
const hide = '\x1b[?25l';
const show = '\x1b[?25h';
const clearLine = '\x1b[2K';
const moveUp = (n) => n > 0 ? `\x1b[${n}A` : '';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const CONFIG_DIR = join(homedir(), '.config', 'claude-needs-you');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');

function loadConfig() {
  try {
    return JSON.parse(readFileSync(CONFIG_FILE, 'utf8'));
  } catch {
    return {};
  }
}

function saveConfig(cfg) {
  const clean = {};
  if (cfg.mode && cfg.mode !== 'all') clean.mode = cfg.mode;
  if (cfg.sound && cfg.sound !== 'default') clean.sound = cfg.sound;
  if (cfg.delay !== undefined && cfg.delay !== 5) clean.delay = cfg.delay;
  if (cfg.debug === true) clean.debug = true;
  mkdirSync(CONFIG_DIR, { recursive: true });
  if (Object.keys(clean).length === 0) {
    try { unlinkSync(CONFIG_FILE); } catch {}
  } else {
    const tmp = CONFIG_FILE + '.tmp';
    writeFileSync(tmp, JSON.stringify(clean, null, 2) + '\n');
    renameSync(tmp, CONFIG_FILE);
  }
}

// ---------------------------------------------------------------------------
// Keypress reader
// ---------------------------------------------------------------------------
function readKey() {
  return new Promise((resolve) => {
    stdin.setRawMode(true);
    stdin.resume();
    stdin.once('data', (data) => {
      stdin.setRawMode(false);
      stdin.pause();
      const s = data.toString();
      if (s === '\x1b[A') resolve('up');
      else if (s === '\x1b[B') resolve('down');
      else if (s === '\r' || s === '\n') resolve('enter');
      else if (s === '\x1b' || s === 'q' || s === 'Q') resolve('escape');
      else if (s === '\x03') resolve('ctrl-c');
      else resolve(s);
    });
  });
}

// ---------------------------------------------------------------------------
// Interactive select
// ---------------------------------------------------------------------------
async function select(title, options, currentValue) {
  let cursor = options.findIndex((o) => o.value === currentValue);
  if (cursor < 0) cursor = 0;
  let rendered = 0;

  function render() {
    // Clear previous render
    if (rendered > 0) stdout.write(moveUp(rendered) + '\r');
    const lines = [];
    lines.push(`${c.cyan}${c.bold}  ${title}${c.reset}`);
    lines.push('');
    for (let i = 0; i < options.length; i++) {
      const opt = options[i];
      const isCurrent = opt.value === currentValue;
      const isSelected = i === cursor;
      const pointer = isSelected ? `${c.green}  ❯ ` : '    ';
      const label = isSelected ? `${c.white}${c.bold}${opt.label}${c.reset}` : `${c.dim}${opt.label}${c.reset}`;
      const tag = isCurrent ? ` ${c.cyan}(current)${c.reset}` : '';
      const desc = opt.desc ? ` ${c.gray}${opt.desc}${c.reset}` : '';
      lines.push(`${clearLine}${pointer}${label}${tag}${desc}${c.reset}`);
    }
    lines.push('');
    lines.push(`${clearLine}${c.gray}  ↑↓ navigate  enter select  esc back${c.reset}`);
    stdout.write(lines.join('\n') + '\n');
    rendered = lines.length;
  }

  stdout.write(hide);
  render();

  while (true) {
    const key = await readKey();
    if (key === 'ctrl-c') { cleanup(); process.exit(0); }
    if (key === 'up') { cursor = (cursor - 1 + options.length) % options.length; render(); }
    else if (key === 'down') { cursor = (cursor + 1) % options.length; render(); }
    else if (key === 'enter') { stdout.write(show); return options[cursor].value; }
    else if (key === 'escape') { stdout.write(show); return null; }
  }
}

// ---------------------------------------------------------------------------
// Number input
// ---------------------------------------------------------------------------
async function numberInput(title, current, min, max) {
  let value = String(current);
  let rendered = 0;

  function render() {
    if (rendered > 0) stdout.write(moveUp(rendered) + '\r');
    const lines = [];
    lines.push(`${c.cyan}${c.bold}  ${title}${c.reset}`);
    lines.push('');
    lines.push(`${clearLine}  ${c.green}❯${c.reset} ${c.white}${c.bold}${value}${c.reset}${c.dim}s${c.reset}  ${c.gray}(${min}-${max})${c.reset}`);
    lines.push('');
    lines.push(`${clearLine}${c.gray}  type number  enter confirm  esc cancel${c.reset}`);
    stdout.write(lines.join('\n') + '\n');
    rendered = lines.length;
  }

  stdout.write(hide);
  render();
  stdout.write(show);

  while (true) {
    const key = await readKey();
    if (key === 'ctrl-c') { cleanup(); process.exit(0); }
    if (key === 'escape') return null;
    if (key === 'enter') {
      const n = parseInt(value, 10);
      if (!isNaN(n) && n >= min && n <= max) return n;
      render();
      stdout.write(show);
    } else if (key === '\x7f' || key === '\b') {
      // Backspace
      value = value.slice(0, -1);
      render();
      stdout.write(show);
    } else if (/^[0-9]$/.test(key)) {
      if (value.length < 3) { value += key; render(); stdout.write(show); }
    }
  }
}

// ---------------------------------------------------------------------------
// Main menu
// ---------------------------------------------------------------------------
function cleanup() {
  stdout.write(show + c.reset + '\n');
}

async function main() {
  const cfg = loadConfig();
  const state = {
    mode: cfg.mode || 'all',
    sound: cfg.sound || 'default',
    delay: cfg.delay ?? 5,
    debug: cfg.debug || false,
  };

  process.on('SIGINT', () => { cleanup(); process.exit(0); });

  while (true) {
    const modeDesc = { all: 'all events', notification: 'prompts only', stop: 'completion only', off: 'disabled' };
    const mainOptions = [
      { value: 'mode', label: `Mode`, desc: `${c.yellow}${state.mode}${c.gray} — ${modeDesc[state.mode] || state.mode}` },
      { value: 'sound', label: `Sound`, desc: `${c.yellow}${state.sound}${c.gray}` },
      { value: 'delay', label: `Delay`, desc: `${c.yellow}${state.delay}s${c.gray} — grace period before alert` },
      { value: 'debug', label: `Debug`, desc: `${c.yellow}${state.debug ? 'on' : 'off'}${c.gray}` },
      { value: 'save', label: `${c.green}Save and exit${c.reset}`, desc: '' },
      { value: 'quit', label: `Quit without saving`, desc: '' },
    ];

    stdout.write('\n');
    stdout.write(`${c.bold}${c.cyan}  ┌─────────────────────────────────┐${c.reset}\n`);
    stdout.write(`${c.bold}${c.cyan}  │   Claude Needs You — Settings   │${c.reset}\n`);
    stdout.write(`${c.bold}${c.cyan}  └─────────────────────────────────┘${c.reset}\n`);

    const choice = await select('What would you like to change?', mainOptions, null);
    if (choice === null || choice === 'quit') {
      stdout.write(`\n${c.dim}  No changes saved.${c.reset}\n\n`);
      break;
    }
    if (choice === 'save') {
      saveConfig(state);
      stdout.write(`\n${c.green}${c.bold}  ✓ Settings saved${c.reset}${c.dim} → ${CONFIG_FILE}${c.reset}\n\n`);
      break;
    }

    if (choice === 'mode') {
      const result = await select('Notification mode', [
        { value: 'all', label: 'All', desc: 'Stop + Notification + PermissionRequest' },
        { value: 'notification', label: 'Notification', desc: 'only prompts, idle, dialogs' },
        { value: 'stop', label: 'Stop', desc: 'only when Claude finishes' },
        { value: 'off', label: 'Off', desc: 'disable all notifications' },
      ], state.mode);
      if (result !== null) state.mode = result;
    }

    if (choice === 'sound') {
      const result = await select('macOS notification sound', [
        { value: 'default', label: 'Default', desc: 'system default' },
        { value: 'Basso', label: 'Basso' },
        { value: 'Blow', label: 'Blow' },
        { value: 'Bottle', label: 'Bottle' },
        { value: 'Frog', label: 'Frog' },
        { value: 'Funk', label: 'Funk' },
        { value: 'Glass', label: 'Glass' },
        { value: 'Hero', label: 'Hero' },
        { value: 'Morse', label: 'Morse' },
        { value: 'Ping', label: 'Ping' },
        { value: 'Pop', label: 'Pop' },
        { value: 'Purr', label: 'Purr' },
        { value: 'Sosumi', label: 'Sosumi' },
        { value: 'Submarine', label: 'Submarine' },
        { value: 'Tink', label: 'Tink' },
        { value: 'none', label: 'None', desc: 'silent' },
      ], state.sound);
      if (result !== null) state.sound = result;
    }

    if (choice === 'delay') {
      const result = await numberInput('Seconds to wait before alerting (0 = instant)', state.delay, 0, 30);
      if (result !== null) state.delay = result;
    }

    if (choice === 'debug') {
      state.debug = !state.debug;
      stdout.write(`\n${c.dim}  Debug ${state.debug ? 'ON — log at /tmp/claude-needs-you.log' : 'OFF'}${c.reset}\n`);
    }
  }
}

main().catch((e) => { cleanup(); console.error(e); process.exit(1); });
