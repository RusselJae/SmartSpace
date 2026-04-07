import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { Product, ProductSetComponent } from '../models/product';
import { generateId } from '../utils/id_generator';
import { parseProductComponentsFromDb } from '../utils/product_components';
import { parseBooleanFlag, parseStringArray } from '../utils/parser';

export type ProductInput = {
  readonly name: string;
  readonly description: string;
  readonly price: number;
  readonly category: string;
  readonly style: string;
  readonly material: string;
  readonly color: string;
  readonly modelPath: string;
  readonly imageUrls: string[];
  readonly components?: ProductSetComponent[];
  readonly realWidthM?: number | null;
  readonly realHeightM?: number | null;
  readonly realDepthM?: number | null;
  readonly modelBaseScale?: number;
  readonly inventoryQty?: number;
  readonly inStock: boolean;
  readonly isArchived?: boolean;
  // Note: isPopular and isNewArrival are now calculated automatically:
  // - isNewArrival: true if created_at is within the last 7 days
  // - isPopular: true if the product has orders (based on order_items count)
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
  readonly model_path: string | null;
  readonly image_urls: string | null;
  /** mysql2 may return string, Buffer, or already-parsed array for JSON columns */
  readonly components_json: unknown;
  readonly real_width_m: number | null;
  readonly real_height_m: number | null;
  readonly real_depth_m: number | null;
  readonly model_base_scale: number | null;
  readonly rating: number | null;
  readonly review_count: number | null;
  readonly inventory_qty: number | null;
  readonly is_popular: number | boolean | null;
  readonly is_new_arrival: number | boolean | null;
  readonly in_stock: number | boolean | null;
  readonly is_archived?: number | boolean | null;
  readonly created_at: Date;
};

type ProductRowWithOrderCount = ProductRow & {
  readonly order_count: number | null;
};

/**
 * Check if a product is a "new arrival" (created within the last 7 days).
 */
const isNewArrival = (createdAt: Date): boolean => {
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  return createdAt >= sevenDaysAgo;
};

const mapProduct = (row: ProductRowWithOrderCount): Product => {
  // NOTE:
  // MySQL may return DECIMAL columns as strings (e.g. "1.00"). If we pass those
  // through directly, the Flutter client will see string values for fields that
  // are typed as numbers and will throw errors like:
  //
  //   TypeError: "1.00": type 'String' is not a subtype of type 'num?'
  //
  // To keep the API contract clean (and the Flutter models happy), we eagerly
  // coerce all numeric-like fields to real numbers here using Number(...).
  
  const createdAt = row.created_at ?? new Date();
  const orderCount = Number(row.order_count ?? 0);
  
  const components = parseProductComponentsFromDb(row.components_json);

  return {
    id: row.id,
    name: row.name,
    description: row.description ?? '',
    // Price is stored as DECIMAL in MySQL -> always coerce to number
    price: Number(row.price),
    category: row.category,
    style: row.style ?? '',
    material: row.material ?? '',
    color: row.color ?? '',
    modelPath: row.model_path ?? 'assets/chair.glb',
    components,
    // Dimension + scale fields may come back as strings from MySQL; normalize
    realWidthM: row.real_width_m != null ? Number(row.real_width_m) : null,
    realHeightM: row.real_height_m != null ? Number(row.real_height_m) : null,
    realDepthM: row.real_depth_m != null ? Number(row.real_depth_m) : null,
    modelBaseScale: row.model_base_scale != null ? Number(row.model_base_scale) : 1,
    imageUrls: parseStringArray(row.image_urls),
    // Aggregate numeric fields should also always be numbers
    rating: Number(row.rating ?? 0),
    reviewCount: Number(row.review_count ?? 0),
    orderCount: orderCount, // Expose order count for best seller sorting
    inventoryQty: Number(row.inventory_qty ?? 0),
    // Calculate popular and new arrival dynamically
    isPopular: orderCount > 0, // Product is popular if it has any orders
    isNewArrival: isNewArrival(createdAt), // New arrival if created within last 7 days
    inStock: parseBooleanFlag(row.in_stock),
    isArchived: parseBooleanFlag(row.is_archived),
    createdAt,
  };
};

type ColumnCheckRow = RowDataPacket & { readonly count: number };

const columnExists = async (tableName: string, columnName: string): Promise<boolean> => {
  const pool = getPool();
  const [rows] = await pool.query<ColumnCheckRow[]>(
    `
    SELECT COUNT(*) as count
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = ?
      AND column_name = ?
    `,
    [tableName, columnName],
  );
  return (rows[0]?.count ?? 0) > 0;
};

let _productSchemaEnsured = false;

/**
 * Ensures the database has the columns the current app depends on.
 *
 * We keep this lightweight schema guard in the backend so local/dev/prod
 * don't silently drift when migrations weren't run.
 */
const ensureProductSchema = async (): Promise<void> => {
  if (_productSchemaEnsured) return;

  const pool = getPool();

  // The original schema predates "archive" support. Add the column lazily.
  if (!(await columnExists('products', 'is_archived'))) {
    await pool.query(`ALTER TABLE products ADD COLUMN is_archived BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`CREATE INDEX idx_products_is_archived ON products (is_archived)`);
  }
  if (!(await columnExists('products', 'components_json'))) {
    await pool.query(`ALTER TABLE products ADD COLUMN components_json JSON NULL AFTER image_urls`);
  }

  _productSchemaEnsured = true;
};

export const listProducts = async (): Promise<Product[]> => {
  await ensureProductSchema();
  const pool = getPool();
  // Use LEFT JOIN to get order counts for each product in a single query
  const [rows] = await pool.query<ProductRowWithOrderCount[]>(
    `SELECT p.*, COALESCE(COUNT(oi.id), 0) as order_count
     FROM products p
     LEFT JOIN order_items oi ON p.id = oi.product_id
     GROUP BY p.id
     ORDER BY p.created_at DESC`
  );
  return rows.map(mapProduct);
};

export const findProductById = async (id: string): Promise<Product | null> => {
  await ensureProductSchema();
  const pool = getPool();
  // Use LEFT JOIN to get order count for the product
  const [rows] = await pool.query<ProductRowWithOrderCount[]>(
    `SELECT p.*, COALESCE(COUNT(oi.id), 0) as order_count
     FROM products p
     LEFT JOIN order_items oi ON p.id = oi.product_id
     WHERE p.id = ?
     GROUP BY p.id`,
    [id]
  );
  if (rows.length === 0) return null;
  return mapProduct(rows[0]);
};

export const createProduct = async (input: ProductInput): Promise<Product> => {
  await ensureProductSchema();
  const pool = getPool();
  const inventoryQty = input.inventoryQty ?? 0;
  const components = input.components ?? [];
  const realWidthM = input.realWidthM ?? null;
  const realHeightM = input.realHeightM ?? null;
  const realDepthM = input.realDepthM ?? null;
  const modelBaseScale = input.modelBaseScale ?? 1;
  const productId = generateId('p');
  const isArchived = input.isArchived ?? false;
  
  // Note: isPopular and isNewArrival are calculated dynamically, but we still
  // need to insert default values (0) into the database for backward compatibility
  // The actual values will be calculated when products are fetched

  await pool.query(
    `
    INSERT INTO products (
      id, name, description, price, category, style, material, color,
      size, model_path, real_width_m, real_height_m, real_depth_m, model_base_scale,
      image_urls, components_json, rating, review_count, inventory_qty, is_popular, is_new_arrival, in_stock, is_archived
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `,
    [
      productId,
      input.name,
      input.description,
      input.price,
      input.category,
      input.style,
      input.material,
      input.color,
      // DB currently requires `size` (NOT NULL) but the admin payload doesn't send it yet.
      // Use a safe placeholder to keep product creation working until the client sends a real value.
      '',
      input.modelPath,
      realWidthM,
      realHeightM,
      realDepthM,
      modelBaseScale,
      JSON.stringify(input.imageUrls),
      JSON.stringify(components),
      0, // rating
      0, // review_count
      inventoryQty,
      0, // is_popular (calculated dynamically)
      0, // is_new_arrival (calculated dynamically)
      input.inStock ? 1 : 0,
      isArchived ? 1 : 0,
    ],
  );

  // Fetch the created product to return it with calculated fields
  return (await findProductById(productId)) as Product;
};

export const updateProduct = async (id: string, input: ProductInput): Promise<Product> => {
  await ensureProductSchema();
  const pool = getPool();
  const existing = await findProductById(id);
  if (existing == null) {
    throw new Error('Product not found');
  }

  const inventoryQty = input.inventoryQty ?? existing.inventoryQty;
  const components = input.components ?? existing.components;
  const isArchived = input.isArchived ?? existing.isArchived;

  // Note: isPopular and isNewArrival are calculated dynamically, so we don't update them
  // They will be recalculated when the product is fetched

  await pool.query(
    `
    UPDATE products SET
      name = ?, description = ?, price = ?, category = ?, style = ?, material = ?,
      color = ?, model_path = ?, real_width_m = ?, real_height_m = ?, real_depth_m = ?, model_base_scale = ?,
      image_urls = ?, components_json = ?, inventory_qty = ?, in_stock = ?, is_archived = ?
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
      input.modelPath,
      input.realWidthM ?? existing.realWidthM,
      input.realHeightM ?? existing.realHeightM,
      input.realDepthM ?? existing.realDepthM,
      input.modelBaseScale ?? existing.modelBaseScale,
      JSON.stringify(input.imageUrls),
      JSON.stringify(components),
      inventoryQty,
      input.inStock ? 1 : 0,
      isArchived ? 1 : 0,
      id,
    ],
  );

  return (await findProductById(id)) as Product;
};

export const deleteProduct = async (id: string): Promise<void> => {
  await ensureProductSchema();
  const pool = getPool();
  await pool.query('DELETE FROM products WHERE id = ?', [id]);
};




