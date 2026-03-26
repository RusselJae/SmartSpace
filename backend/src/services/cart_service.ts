import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { CartItem } from '../models/cart_item';
import { Product } from '../models/product';
import { generateId } from '../utils/id_generator';
import { parseBooleanFlag, parseStringArray } from '../utils/parser';

type CartItemRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly product_id: string;
  readonly quantity: number;
  readonly unit_price: number;
  readonly notes: string | null;
  readonly added_at: Date;
  readonly updated_at: Date;
  readonly product_name: string;
  readonly product_description: string | null;
  readonly product_price: number;
  readonly product_category: string;
  readonly product_style: string | null;
  readonly product_material: string | null;
  readonly product_color: string | null;
  readonly product_model_path: string | null;
  readonly product_image_urls: string | null;
  readonly product_real_width_m: number | null;
  readonly product_real_height_m: number | null;
  readonly product_real_depth_m: number | null;
  readonly product_model_base_scale: number | null;
  readonly product_rating: number | null;
  readonly product_review_count: number | null;
  readonly product_is_popular: number | boolean | null;
  readonly product_is_new_arrival: number | boolean | null;
  readonly product_in_stock: number | boolean | null;
  readonly product_inventory_qty: number | null;
  readonly product_is_archived: number | boolean | null;
  readonly product_created_at: Date;
};

type CartRow = RowDataPacket & {
  readonly id: string;
  readonly user_id: string;
  readonly product_id: string;
  readonly quantity: number;
  readonly unit_price: number;
  readonly notes: string | null;
};

type ProductRow = RowDataPacket & {
  readonly id: string;
  readonly price: number;
};

const CART_SELECT = `
  SELECT
    ci.id,
    ci.user_id,
    ci.product_id,
    ci.quantity,
    ci.unit_price,
    ci.notes,
    ci.added_at,
    ci.updated_at,
    p.name AS product_name,
    p.description AS product_description,
    p.price AS product_price,
    p.category AS product_category,
    p.style AS product_style,
    p.material AS product_material,
    p.color AS product_color,
    p.model_path AS product_model_path,
    p.image_urls AS product_image_urls,
    p.real_width_m AS product_real_width_m,
    p.real_height_m AS product_real_height_m,
    p.real_depth_m AS product_real_depth_m,
    p.model_base_scale AS product_model_base_scale,
    p.rating AS product_rating,
    p.review_count AS product_review_count,
    p.is_popular AS product_is_popular,
    p.is_new_arrival AS product_is_new_arrival,
    p.in_stock AS product_in_stock,
    p.inventory_qty AS product_inventory_qty,
    p.is_archived AS product_is_archived,
    p.created_at AS product_created_at
  FROM cart_items ci
  INNER JOIN products p ON p.id = ci.product_id
`;

const mapProduct = (row: CartItemRow): Product => ({
  id: row.product_id,
  name: row.product_name,
  description: row.product_description ?? '',
  price: Number(row.product_price),
  category: row.product_category,
  style: row.product_style ?? '',
  material: row.product_material ?? '',
  color: row.product_color ?? '',
  modelPath: row.product_model_path ?? 'assets/chair.glb',
  realWidthM: row.product_real_width_m ?? null,
  realHeightM: row.product_real_height_m ?? null,
  realDepthM: row.product_real_depth_m ?? null,
  modelBaseScale: row.product_model_base_scale ?? 1,
  imageUrls: parseStringArray(row.product_image_urls),
  rating: Number(row.product_rating ?? 0),
  reviewCount: Number(row.product_review_count ?? 0),
  isPopular: parseBooleanFlag(row.product_is_popular),
  isNewArrival: parseBooleanFlag(row.product_is_new_arrival),
  inStock: parseBooleanFlag(row.product_in_stock),
  inventoryQty: Number(row.product_inventory_qty ?? 0),
  isArchived: parseBooleanFlag(row.product_is_archived),
  createdAt: row.product_created_at ?? new Date(),
});

const mapCartItem = (row: CartItemRow): CartItem => ({
  id: row.id,
  userId: row.user_id,
  productId: row.product_id,
  quantity: row.quantity,
  unitPrice: Number(row.unit_price),
  notes: row.notes ?? undefined,
  addedAt: row.added_at ?? new Date(),
  updatedAt: row.updated_at ?? row.added_at ?? new Date(),
  product: mapProduct(row),
});

const fetchCartItemById = async (id: string): Promise<CartItem> => {
  const pool = getPool();
  const [rows] = await pool.query<CartItemRow[]>(`${CART_SELECT} WHERE ci.id = ? LIMIT 1`, [id]);
  if (rows.length === 0) {
    throw new Error('Cart item not found');
  }
  return mapCartItem(rows[0]);
};

const fetchProductPrice = async (productId: string): Promise<number> => {
  const pool = getPool();
  const [rows] = await pool.query<ProductRow[]>('SELECT id, price FROM products WHERE id = ? LIMIT 1', [
    productId,
  ]);
  if (rows.length === 0) {
    throw new Error('Product not found');
  }
  return Number(rows[0].price);
};

const fetchCartRow = async (userId: string, productId: string): Promise<CartRow | null> => {
  const pool = getPool();
  const [rows] = await pool.query<CartRow[]>(
    'SELECT id, user_id, product_id, quantity, unit_price, notes FROM cart_items WHERE user_id = ? AND product_id = ? LIMIT 1',
    [userId, productId],
  );
  if (rows.length === 0) {
    return null;
  }
  return rows[0];
};

export const listCartItemsByUser = async (userId: string): Promise<CartItem[]> => {
  const pool = getPool();
  const [rows] = await pool.query<CartItemRow[]>(`${CART_SELECT} WHERE ci.user_id = ? ORDER BY ci.added_at DESC`, [
    userId,
  ]);
  return rows.map(mapCartItem);
};

export interface AddCartItemInput {
  readonly userId: string;
  readonly productId: string;
  readonly quantity?: number;
  readonly notes?: string;
}

export const addCartItem = async (input: AddCartItemInput): Promise<CartItem> => {
  const pool = getPool();
  const quantity = Math.max(1, Math.floor(input.quantity ?? 1));
  const existing = await fetchCartRow(input.userId, input.productId);
  const unitPrice = await fetchProductPrice(input.productId);

  if (existing != null) {
    const newQuantity = existing.quantity + quantity;
    await pool.query(
      `UPDATE cart_items
       SET quantity = ?, unit_price = ?, notes = IFNULL(?, notes), updated_at = NOW()
       WHERE id = ?`,
      [newQuantity, unitPrice, input.notes ?? existing.notes, existing.id],
    );
    return fetchCartItemById(existing.id);
  }

  const id = generateId('cart');
  await pool.query(
    `INSERT INTO cart_items (id, user_id, product_id, quantity, unit_price, notes)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [id, input.userId, input.productId, quantity, unitPrice, input.notes ?? null],
  );
  return fetchCartItemById(id);
};

export interface SetCartItemQuantityInput {
  readonly userId: string;
  readonly productId: string;
  readonly quantity: number;
  readonly notes?: string | null;
}

export const setCartItemQuantity = async (
  input: SetCartItemQuantityInput,
): Promise<CartItem | null> => {
  const pool = getPool();
  const quantity = Math.floor(input.quantity);
  const existing = await fetchCartRow(input.userId, input.productId);
  if (existing == null) {
    return null;
  }
  if (quantity <= 0) {
    await pool.query('DELETE FROM cart_items WHERE id = ?', [existing.id]);
    return null;
  }
  await pool.query(
    `UPDATE cart_items
     SET quantity = ?, notes = IFNULL(?, notes), updated_at = NOW()
     WHERE id = ?`,
    [quantity, input.notes ?? existing.notes, existing.id],
  );
  return fetchCartItemById(existing.id);
};

export const removeCartItem = async (userId: string, productId: string): Promise<void> => {
  const pool = getPool();
  await pool.query('DELETE FROM cart_items WHERE user_id = ? AND product_id = ?', [userId, productId]);
};

export const clearCart = async (userId: string): Promise<void> => {
  const pool = getPool();
  await pool.query('DELETE FROM cart_items WHERE user_id = ?', [userId]);
};
















