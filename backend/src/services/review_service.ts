import { RowDataPacket } from 'mysql2';
import { getPool } from '../config/database';
import { Review } from '../models/review';
import { generateId } from '../utils/id_generator';

type ReviewRow = RowDataPacket & {
  readonly id: string;
  readonly product_id: string;
  readonly product_name: string | null;
  readonly user_id: string;
  readonly user_name: string | null;
  readonly rating: number;
  readonly content: string | null;
  readonly status: string | null;
  readonly created_at: Date;
  readonly updated_at: Date | null;
};

export type ReviewInput = {
  readonly productId: string;
  readonly productName: string;
  readonly userId: string;
  readonly userName: string;
  readonly rating: number;
  readonly content: string;
};

/**
 * Map a raw MySQL row into the strongly-typed Review model.
 *
 * NOTE:
 * - We normalise nullable string fields to empty strings to keep the Flutter
 *   client happy (it expects non-null strings).
 * - We also normalise the status so that reviews with a null status coming
 *   from legacy data are treated as "published" – this lines up with the
 *   new behaviour where reviews are auto‑accepted.
 */
const mapReview = (row: ReviewRow): Review => {
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name ?? '',
    userId: row.user_id,
    userName: row.user_name ?? '',
    rating: Number(row.rating),
    content: row.content ?? '',
    // Treat missing status as published so older rows still show up
    status: row.status ?? 'published',
    createdAt: row.created_at ?? new Date(),
    updatedAt: row.updated_at ?? undefined,
  };
};

/**
 * List all reviews in the system.
 *
 * Reviews are now auto‑published, so this returns everything regardless
 * of status. The admin UI is read‑only, so status is effectively
 * informational at this point.
 */
export const listReviews = async (): Promise<Review[]> => {
  const pool = getPool();
  const [rows] = await pool.query<ReviewRow[]>(
    'SELECT * FROM reviews ORDER BY created_at DESC',
  );
  return rows.map(mapReview);
};

/**
 * Reviews authored by one user (storefront profile — no admin token).
 */
export const listReviewsForUser = async (userId: string): Promise<Review[]> => {
  const pool = getPool();
  const [rows] = await pool.query<ReviewRow[]>(
    'SELECT * FROM reviews WHERE user_id = ? ORDER BY created_at DESC',
    [userId.trim()],
  );
  return rows.map(mapReview);
};

/**
 * Get all reviews for a specific product.
 * Returns all published reviews from ALL users who have reviewed this product.
 * 
 * IMPORTANT: This includes reviews with null status (treated as published for legacy data)
 * to ensure all user reviews are displayed on the product detail page.
 */
export const getReviewsByProductId = async (productId: string, includePending = false): Promise<Review[]> => {
  const pool = getPool();
  // Include null status reviews (legacy data) and published reviews
  // This ensures ALL user reviews are displayed, not just those with explicit 'published' status
  const statusFilter = includePending 
    ? "(status IN ('published', 'pending') OR status IS NULL)"
    : "(status = 'published' OR status IS NULL)";
  
  console.log(`[ReviewService] Fetching reviews for productId: ${productId}`);
  console.log(`[ReviewService] Status filter: ${statusFilter}`);
  
  const [rows] = await pool.query<ReviewRow[]>(
    `SELECT * FROM reviews 
     WHERE product_id = ? AND ${statusFilter}
     ORDER BY created_at DESC`,
    [productId],
  );
  
  console.log(`[ReviewService] Found ${rows.length} reviews for productId: ${productId}`);
  if (rows.length > 0) {
    console.log(`[ReviewService] Review details:`, rows.map(r => ({
      id: r.id,
      productId: r.product_id,
      userId: r.user_id,
      userName: r.user_name,
      rating: r.rating,
      status: r.status,
    })));
  }
  
  const reviews = rows.map(mapReview);
  console.log(`[ReviewService] Returning ${reviews.length} mapped reviews`);
  
  return reviews;
};

/**
 * Check if a user has purchased a specific product.
 * Returns true if the user has at least one order containing this product.
 */
/**
 * Check if a user has purchased a specific product.
 *
 * IMPORTANT:
 * This is the *server‑side* gate that enforces the rule:
 *   "Only users who bought a product can review it."
 *
 * The Flutter client does a similar check for UX, but this function is the
 * real source of truth – clients cannot bypass it.
 */
export const hasUserPurchasedProduct = async (userId: string, productId: string): Promise<boolean> => {
  const pool = getPool();
  const [rows] = await pool.query<RowDataPacket[]>(
    `SELECT COUNT(*) as count 
     FROM order_items oi
     INNER JOIN orders o ON oi.order_id = o.id
     WHERE o.user_id = ? AND oi.product_id = ?
     LIMIT 1`,
    [userId, productId],
  );
  const count = Number(rows[0]?.count ?? 0);
  return count > 0;
};

/**
 * Create a new review.
 *
 * Behaviour:
 * - Only allows reviews from users who have actually purchased the product.
 * - Enforces one review per (user, product) pair.
 * - New reviews are *automatically published* – there is no manual approval
 *   step in the admin UI anymore.
 */
export const createReview = async (input: ReviewInput): Promise<Review> => {
  const pool = getPool();
  
  // Validate that the user has purchased this product
  const hasPurchased = await hasUserPurchasedProduct(input.userId, input.productId);
  if (!hasPurchased) {
    throw new Error('You can only review products you have purchased');
  }

  // Check if user has already reviewed this product
  const [existingRows] = await pool.query<ReviewRow[]>(
    'SELECT id FROM reviews WHERE user_id = ? AND product_id = ? LIMIT 1',
    [input.userId, input.productId],
  );
  if (existingRows.length > 0) {
    throw new Error('You have already reviewed this product');
  }

  const review: Review = {
    id: generateId('r'),
    productId: input.productId,
    productName: input.productName,
    userId: input.userId,
    userName: input.userName,
    rating: input.rating,
    content: input.content,
    // Auto‑accept: reviews are immediately visible as "published"
    status: 'published',
    createdAt: new Date(),
  };

  await pool.query(
    `
    INSERT INTO reviews (id, product_id, product_name, user_id, user_name, rating, content, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `,
    [
      review.id,
      review.productId,
      review.productName,
      review.userId,
      review.userName,
      review.rating,
      review.content,
      review.status,
    ],
  );

  return review;
};

export const updateReviewStatus = async (id: string, status: string): Promise<void> => {
  const pool = getPool();
  await pool.query('UPDATE reviews SET status = ?, updated_at = NOW() WHERE id = ?', [status, id]);
};

export const deleteReview = async (id: string): Promise<void> => {
  const pool = getPool();
  await pool.query('DELETE FROM reviews WHERE id = ?', [id]);
};

