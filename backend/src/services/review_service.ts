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

const mapReview = (row: ReviewRow): Review => {
  return {
    id: row.id,
    productId: row.product_id,
    productName: row.product_name ?? '',
    userId: row.user_id,
    userName: row.user_name ?? '',
    rating: Number(row.rating),
    content: row.content ?? '',
    status: row.status ?? 'pending',
    createdAt: row.created_at ?? new Date(),
    updatedAt: row.updated_at ?? undefined,
  };
};

export const listReviews = async (): Promise<Review[]> => {
  const pool = getPool();
  const [rows] = await pool.query<ReviewRow[]>(
    'SELECT * FROM reviews ORDER BY created_at DESC',
  );
  return rows.map(mapReview);
};

export const createReview = async (input: ReviewInput): Promise<Review> => {
  const pool = getPool();
  const review: Review = {
    id: generateId('r'),
    productId: input.productId,
    productName: input.productName,
    userId: input.userId,
    userName: input.userName,
    rating: input.rating,
    content: input.content,
    status: 'pending',
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

