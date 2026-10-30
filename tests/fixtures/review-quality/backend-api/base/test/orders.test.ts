import request from 'supertest';
import { beforeAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { resetDatabase, seedUser } from './helpers.js';

const app = createApp();

describe('orders API', () => {
  let token: string;

  beforeAll(async () => {
    await resetDatabase();
    token = await seedUser({ email: 'buyer@example.com' });
  });

  it('creates an order and lists it', async () => {
    const created = await request(app)
      .post('/orders')
      .set('authorization', `Bearer ${token}`)
      .send({ items: [{ productId: 1, quantity: 2 }] })
      .expect(201);
    expect(created.body).toMatchObject({ status: 'pending', totalCents: 2400 });

    const list = await request(app).get('/orders').set('authorization', `Bearer ${token}`).expect(200);
    expect(list.body[0]).toMatchObject({ id: created.body.id, totalCents: 2400 });
  });

  it('rejects duplicate products in one order', async () => {
    await request(app)
      .post('/orders')
      .set('authorization', `Bearer ${token}`)
      .send({ items: [{ productId: 1, quantity: 1 }, { productId: 1, quantity: 2 }] })
      .expect(400);
  });

  it('rejects unauthenticated requests', async () => {
    await request(app).get('/orders').expect(401);
  });
});
