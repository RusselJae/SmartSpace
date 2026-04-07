export interface ProductSetComponent {
  readonly name: string;
  readonly quantity: number;
  readonly widthM: number;
  readonly heightM: number;
  readonly depthM: number;
  readonly modelPath?: string;
  readonly notes?: string;
}

export interface Product {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly price: number;
  readonly category: string;
  readonly style: string;
  readonly material: string;
  readonly color: string;
  readonly modelPath: string;
  readonly components: ProductSetComponent[];
  readonly realWidthM: number | null;
  readonly realHeightM: number | null;
  readonly realDepthM: number | null;
  readonly modelBaseScale: number;
  readonly imageUrls: string[];
  readonly rating: number;
  readonly reviewCount: number;
  readonly orderCount?: number; // Number of orders for this product (for best seller sorting)
  readonly inventoryQty: number;
  readonly isPopular: boolean;
  readonly isNewArrival: boolean;
  readonly inStock: boolean;
  readonly isArchived: boolean;
  readonly createdAt: Date;
}





