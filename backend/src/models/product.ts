export interface Product {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly price: number;
  readonly category: string;
  readonly style: string;
  readonly material: string;
  readonly color: string;
  readonly size: string;
  readonly modelPath: string;
  readonly imageUrls: string[];
  readonly rating: number;
  readonly reviewCount: number;
  readonly inventoryQty: number;
  readonly isPopular: boolean;
  readonly isNewArrival: boolean;
  readonly inStock: boolean;
  readonly createdAt: Date;
}





