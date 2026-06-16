export type ProductVariantBomLine = {
  readonly id: string;
  readonly variantId: string;
  readonly inventoryMaterialId: string;
  readonly materialName: string;
  readonly materialSku: string | null;
  readonly materialUnit: string;
  readonly quantityRequired: number;
};

export type ProductVariant = {
  readonly id: string;
  readonly productId: string;
  readonly name: string;
  readonly dimensionsLabel: string | null;
  readonly priceAdjustment: number;
  readonly isDefault: boolean;
  readonly bomLines: ProductVariantBomLine[];
  readonly createdAt: Date;
  readonly updatedAt: Date;
};

export type ProductVariantBomLineInput = {
  readonly inventoryMaterialId: string;
  readonly quantityRequired: number;
};

export type ProductVariantInput = {
  readonly name: string;
  readonly dimensionsLabel?: string | null;
  readonly priceAdjustment?: number;
  readonly isDefault?: boolean;
  readonly bomLines?: readonly ProductVariantBomLineInput[];
};
