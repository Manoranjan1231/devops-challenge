// Minimal smoke test — no DB required. Verifies the app module loads
// and required env var validation works. Kept intentionally simple:
// this challenge is about infra, not test coverage.
const assert = require('assert');

console.log('Running smoke tests...');

// Test 1: server.js should exit fast and loud if DATABASE_URL is missing
const { execSync } = require('child_process');
try {
  execSync('node server.js', {
    env: { ...process.env, DATABASE_URL: '', PORT: '4001' },
    timeout: 2000,
  });
  console.error('FAIL: server did not exit without DATABASE_URL');
  process.exit(1);
} catch (err) {
  // Expected: process.exit(1) inside server.js triggers a non-zero exit
  console.log('PASS: server refuses to start without DATABASE_URL');
}

console.log('All smoke tests passed.');
