const express = require('express');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.error('FATAL: DATABASE_URL environment variable is not set.');
  process.exit(1);
}

const pool = new Pool({
  connectionString: DATABASE_URL,
  connectionTimeoutMillis: 3000,
});

let dbReady = false;

async function initDb() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS items (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT NOW()
      )
    `);
    dbReady = true;
    console.log('Database schema ready.');
  } catch (err) {
    dbReady = false;
    console.error('DB init failed:', err.message);
  }
}

// --- LIVENESS ---
// Answers "is the Node process itself alive and able to serve HTTP?"
// Deliberately does NOT touch the database. If this fails, Kubernetes
// kills and restarts the container. It should only fail if the process
// is truly wedged (deadlocked event loop, out of memory, etc).
app.get('/healthz', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

// --- READINESS ---
// Answers "can this pod currently serve real traffic?"
// This DOES check the database dependency. If the DB is unreachable,
// we return 503 so Kubernetes pulls this pod out of the Service's
// endpoint list (no restart — just stop routing traffic here).
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'ready', db: 'connected' });
  } catch (err) {
    res.status(503).json({ status: 'not_ready', db: 'unreachable', error: err.message });
  }
});

app.get('/', async (req, res) => {
  try {
    const result = await pool.query('SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 50');
    res.json({ service: 'devops-challenge-backend', items: result.rows });
  } catch (err) {
    res.status(500).json({ error: 'db_query_failed', detail: err.message });
  }
});

app.post('/items', async (req, res) => {
  const { name } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  try {
    const result = await pool.query('INSERT INTO items (name) VALUES ($1) RETURNING *', [name]);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'db_insert_failed', detail: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
  initDb();
  // Retry DB init periodically in case DB isn't up yet on first boot
  setInterval(() => {
    if (!dbReady) initDb();
  }, 5000);
});
