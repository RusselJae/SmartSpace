export interface User {
  readonly id: string;
  readonly email: string;
  readonly fullName: string;
  readonly username: string;
  readonly phoneNumber?: string;
  readonly gender?: 'male' | 'female' | 'other';
  readonly dateOfBirth?: Date;
  readonly avatarUrl?: string;
  readonly addresses: string[];
  readonly wishlistProductIds: string[];
  readonly orderIds: string[];
  readonly preferredStyle?: string;
  readonly minBudget?: number;
  readonly maxBudget?: number;
  readonly createdAt: Date;
  readonly lastLoginAt?: Date;
  readonly emailVerified: boolean;
  readonly verificationToken?: string;
  readonly verificationTokenExpires?: Date;
  readonly verificationCode?: string;
  readonly termsVersionAccepted?: number;
  readonly termsAcceptedAt?: Date;
}





