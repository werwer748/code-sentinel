const GATEWAY_URL = process.env.PAYMENT_GATEWAY_URL ?? 'https://payments.internal.example';
const API_KEY = process.env.PAYMENT_GATEWAY_KEY ?? '';

export interface ChargeRequest {
  orderId: number;
  amountCents: number;
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

export async function chargeCard(req: ChargeRequest): Promise<Charge> {
  const res = await fetch(`${GATEWAY_URL}/v1/charges`, {
    method: 'POST',
    headers: { authorization: `Bearer ${API_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      amount: req.amountCents,
      currency: 'usd',
      payment_method: req.paymentMethodId,
      metadata: { order_id: req.orderId },
    }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    throw new PaymentError(`charge failed with status ${res.status}`, res.status);
  }
  return (await res.json()) as Charge;
}
