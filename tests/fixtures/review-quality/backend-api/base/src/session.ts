import { createHash } from 'node:crypto';
import { db } from './db.js';
import type { AuthUser } from './auth.js';

export async function verifySession(token: string): Promise<AuthUser | null> {
  const tokenHash = createHash('sha256').update(token).digest('hex');
  const { rows } = await db.query<{ user_id: number; role: AuthUser['role'] }>(
    'SELECT s.user_id, u.role FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = $1 AND s.expires_at > now()',
    [tokenHash],
  );
  return rows[0] ? { id: rows[0].user_id, role: rows[0].role } : null;
}
