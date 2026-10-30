import { randomBytes, createHash } from 'node:crypto';
import { pool } from '../src/db.js';

export async function resetDatabase(): Promise<void> {
  await pool.query('TRUNCATE invoices, wallets, order_items, orders, sessions, users, products RESTART IDENTITY CASCADE');
  await pool.query(
    "INSERT INTO products (name, category, price_cents, stock) VALUES ('Desk lamp', 'lighting', 1200, 10), ('Floor lamp', 'lighting', 4500, 3)",
  );
}

export async function seedUser(opts: { email: string; role?: 'customer' | 'admin' }): Promise<string> {
  const { rows } = await pool.query<{ id: number }>(
    'INSERT INTO users (email, role) VALUES ($1, $2) RETURNING id',
    [opts.email, opts.role ?? 'customer'],
  );
  const token = randomBytes(24).toString('hex');
  await pool.query(
    "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES ($1, $2, now() + interval '1 hour')",
    [createHash('sha256').update(token).digest('hex'), rows[0].id],
  );
  return token;
}
