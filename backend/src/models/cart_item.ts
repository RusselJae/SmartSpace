import { Product } from './product';

export interface CartItem {
  readonly id: string;
  readonly userId: string;
  readonly productId: string;
  readonly quantity: number;
  readonly unitPrice: number;
  readonly notes?: string;
  readonly addedAt: Date;
  readonly updatedAt: Date;
  readonly product: Product;
}


