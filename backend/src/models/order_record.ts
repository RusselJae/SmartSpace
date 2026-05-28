export interface OrderRecord {
  readonly id: string;
  readonly userId: string;
  readonly userName: string;
  readonly productIds: string[];
  readonly totalAmount: number;
  readonly status: string;
  readonly shippingAddress: Record<string, unknown>;
  readonly paymentProofUrl?: string;
  /**
   * Snapshot: Terms & Conditions version accepted by the customer at the moment
   * the order was created. Optional for backward compatibility.
   */
  readonly termsVersionAcceptedAtOrder?: number;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}





