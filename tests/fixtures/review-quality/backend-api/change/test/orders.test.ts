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
    expect(created.body).toMatchObject({ status: 'pending', amountCents: 2400, currency: 'USD' });

    const list = await request(app).get('/orders').set('authorization', `Bearer ${token}`).expect(200);
    expect(list.body[0]).toMatchObject({ id: created.body.id, amountCents: 2400 });
    expect(list.body[0].items).toEqual([{ product_id: 1, quantity: 2, unit_price_cents: 1200 }]);
  });

  it('rejects orders that exceed the available stock', async () => {
    await request(app)
      .post('/orders')
      .set('authorization', `Bearer ${token}`)
      .send({ items: [{ productId: 2, quantity: 4 }] })
      .expect(409);
  });

  it('cancels a pending order', async () => {
    const created = await request(app)
      .post('/orders')
      .set('authorization', `Bearer ${token}`)
      .send({ items: [{ productId: 2, quantity: 1 }] })
      .expect(201);
    const cancelled = await request(app)
      .post(`/orders/${created.body.id}/cancel`)
      .set('authorization', `Bearer ${token}`)
      .expect(200);
    expect(cancelled.body).toEqual({ id: created.body.id, status: 'cancelled' });
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
