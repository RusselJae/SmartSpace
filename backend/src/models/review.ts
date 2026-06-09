export type ReviewMediaItem = {
  readonly url: string;
  readonly type: 'image' | 'video';
};

export interface Review {
  readonly id: string;
  readonly productId: string;
  readonly productName: string;
  readonly userId: string;
  readonly userName: string;
  readonly rating: number;
  readonly content: string;
  readonly status: string;
  readonly media: readonly ReviewMediaItem[];
  readonly createdAt: Date;
  readonly updatedAt?: Date;
}





