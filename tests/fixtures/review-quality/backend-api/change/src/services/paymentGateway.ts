const GATEWAY_URL = process.env.PAYMENT_GATEWAY_URL ?? 'https://payments.internal.example';
const API_KEY = process.env.PAYMENT_GATEWAY_KEY ?? '';
const MAX_ATTEMPTS = 3;

export interface ChargeRequest {
  orderId: number;
  amountCents: number;
  currency: string;
  paymentMethodId: string;
}

export interface Charge {
  id: string;
  status: 'succeeded' | 'pending';
}

export class PaymentError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function chargeCard(req: ChargeRequest): Promise<Charge> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const res = await fetch(`${GATEWAY_URL}/v1/charges`, {
        method: 'POST',
        headers: { authorization: `Bearer ${API_KEY}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          amount: req.amountCents,
          currency: req.currency.toLowerCase(),
          payment_method: req.paymentMethodId,
          metadata: { order_id: req.orderId },
        }),
        signal: AbortSignal.timeout(5_000),
      });
      if (!res.ok) {
        throw new PaymentError(`charge failed with status ${res.status}`, res.status);
      }
      return (await res.json()) as Charge;
    } catch (err) {
      lastError = err;
      if (err instanceof PaymentError && err.status !== undefined && err.status < 500) {
        throw err;
      }
      if (attempt < MAX_ATTEMPTS) {
        await sleep(250 * 2 ** attempt);
      }
    }
  }
  throw lastError;
}
