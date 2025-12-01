import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { Product } from '../models/product';
import { generateId } from '../utils/id_generator';
import { parseBooleanFlag, parseStringArray } from '../utils/parser';

export type ProductInput = {
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
  readonly inventoryQty?: number;
  readonly isPopular: boolean;
  readonly isNewArrival: boolean;
  readonly inStock: boolean;
};

type ProductRow = RowDataPacket & {
  readonly id: string;
  readonly name: string;
  readonly description: string | null;
  readonly price: number;
  readonly category: string;
  readonly style: string | null;
  readonly material: string | null;
  readonly color: string | null;
  readonly size: string | null;
  readonly model_path: string | null;
  readonly image_urls: string | null;
  readonly rating: number | null;
  readonly review_count: number | null;
  readonly inventory_qty: number | null;
  readonly is_popular: number | boolean | null;
  readonly is_new_arrival: number | boolean | null;
  readonly in_stock: number | boolean | null;
  readonly created_at: Date;
};

const mapProduct = (row: ProductRow): Product => {
  return {
    id: row.id,
    name: row.name,
    description: row.description ?? '',
    price: Number(row.price),
    category: row.category,
    style: row.style ?? '',
    material: row.material ?? '',
    color: row.color ?? '',
    size: row.size ?? '',
    modelPath: row.model_path ?? 'assets/chair.glb',
    imageUrls: parseStringArray(row.image_urls),
    rating: Number(row.rating ?? 0),
    reviewCount: Number(row.review_count ?? 0),
    inventoryQty: Number(row.inventory_qty ?? 0),
    isPopular: parseBooleanFlag(row.is_popular),
    isNewArrival: parseBooleanFlag(row.is_new_arrival),
    inStock: parseBooleanFlag(row.in_stock),
    createdAt: row.created_at ?? new Date(),
  };
};

export const listProducts = async (): Promise<Product[]> => {
  const pool = getPool();
  const [rows] = await pool.query<ProductRow[]>('SELECT * FROM products ORDER BY created_at DESC');
  return rows.map(mapProduct);
};

export const findProductById = async (id: string): Promise<Product | null> => {
  const pool = getPool();
  const [rows] = await pool.query<ProductRow[]>('SELECT * FROM products WHERE id = ?', [id]);
  if (rows.length === 0) return null;
  return mapProduct(rows[0]);
};

export const createProduct = async (input: ProductInput): Promise<Product> => {
  const pool = getPool();
  const inventoryQty = input.inventoryQty ?? 0;
  const product: Product = {
    id: generateId('p'),
    name: input.name,
    description: input.description,
    price: input.price,
    category: input.category,
    style: input.style,
    material: input.material,
    color: input.color,
    size: input.size,
    modelPath: input.modelPath,
    imageUrls: input.imageUrls,
    rating: 0,
    reviewCount: 0,
    inventoryQty: inventoryQty,
    isPopular: input.isPopular,
    isNewArrival: input.isNewArrival,
    inStock: input.inStock,
    createdAt: new Date(),
  };

  await pool.query(
    `
    INSERT INTO products (
      id, name, description, price, category, style, material, color, size,
      model_path, image_urls, rating, review_count, inventory_qty, is_popular, is_new_arrival, in_stock
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
    [
      product.id,
      product.name,
      product.description,
      product.price,
      product.category,
      product.style,
      product.material,
      product.color,
      product.size,
      product.modelPath,
      JSON.stringify(product.imageUrls),
      product.rating,
      product.reviewCount,
      product.inventoryQty,
      product.isPopular ? 1 : 0,
      product.isNewArrival ? 1 : 0,
      product.inStock ? 1 : 0,
    ],
  );

  return product;
};

export const updateProduct = async (id: string, input: ProductInput): Promise<Product> => {
  const pool = getPool();
  const existing = await findProductById(id);
  if (existing == null) {
    throw new Error('Product not found');
  }

  const inventoryQty = input.inventoryQty ?? existing.inventoryQty;

  await pool.query(
    `
    UPDATE products SET
      name = ?, description = ?, price = ?, category = ?, style = ?, material = ?,
      color = ?, size = ?, model_path = ?, image_urls = ?, inventory_qty = ?, is_popular = ?, is_new_arrival = ?, in_stock = ?
    WHERE id = ?
  `,
    [
      input.name,
      input.description,
      input.price,
      input.category,
      input.style,
      input.material,
      input.color,
      input.size,
      input.modelPath,
      JSON.stringify(input.imageUrls),
      inventoryQty,
      input.isPopular ? 1 : 0,
      input.isNewArrival ? 1 : 0,
      input.inStock ? 1 : 0,
      id,
    ],
  );

  return (await findProductById(id)) as Product;
};

export const deleteProduct = async (id: string): Promise<void> => {
  const pool = getPool();
  await pool.query('DELETE FROM products WHERE id = ?', [id]);
};




