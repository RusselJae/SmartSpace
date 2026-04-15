import admin from 'firebase-admin';
import { config } from '../config/env';

let _initialized = false;

const initFirebaseAdmin = (): boolean => {
  if (_initialized) return true;
  const raw = (config.firebase.serviceAccountJson ?? '').trim();
  if (!raw) {
    return false;
  }
  try {
    const parsed = JSON.parse(raw) as admin.ServiceAccount;
    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert(parsed),
      });
    }
    _initialized = true;
    return true;
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin SDK:', error);
    return false;
  }
};

export const sendPushToTokens = async (
  tokens: readonly string[],
  payload: {
    readonly title: string;
    readonly body: string;
    readonly data?: Record<string, string>;
  },
): Promise<void> => {
  const cleanTokens = tokens.map((t) => t.trim()).filter((t) => t.length > 0);
  if (cleanTokens.length === 0) return;
  if (!initFirebaseAdmin()) return;

  const messaging = admin.messaging();
  const response = await messaging.sendEachForMulticast({
    tokens: cleanTokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'smartspace_general',
      },
    },
  });

  if (response.failureCount > 0) {
    const failed = response.responses.filter((r) => !r.success);
    console.warn(`⚠️ FCM partial failure: ${failed.length}/${cleanTokens.length}`);
  }
};

