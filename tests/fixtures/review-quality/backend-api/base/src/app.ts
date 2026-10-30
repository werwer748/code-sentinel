import express, { type NextFunction, type Request, type Response } from 'express';
import { HttpError } from './errors.js';
import { ordersRouter } from './routes/orders.js';
import { productsRouter } from './routes/products.js';

export function createApp() {
  const app = express();
  app.use(express.json({ limit: '100kb' }));

  app.use('/products', productsRouter);
  app.use('/orders', ordersRouter);

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof HttpError) {
      res.status(err.status).json({ error: err.code });
      return;
    }
    console.error('unhandled error', err);
    res.status(500).json({ error: 'internal_error' });
  });

  return app;
}
