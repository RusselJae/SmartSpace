export interface OrderRecord {
  readonly id: string;
  readonly userId: string;
  readonly userName: string;
  readonly productIds: string[];
  readonly totalAmount: number;
  readonly status: string;
  readonly shippingAddress: Record<string, unknown>;
  readonly paymentProofUrl?: string;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}





