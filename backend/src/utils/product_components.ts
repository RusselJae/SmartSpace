import { ProductSetComponent } from '../models/product';

/**
 * MySQL JSON columns often come back from mysql2 as a parsed Array/Object, not a string.
 * Calling `.trim()` or `JSON.parse` on those values throws. This normalizes all shapes.
 */
export const parseProductComponentsFromDb = (raw: unknown): ProductSetComponent[] => {
  if (raw == null) {
    return [];
  }

  let array: unknown;
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }
    try {
      array = JSON.parse(trimmed);
    } catch {
      return [];
    }
  } else if (Buffer.isBuffer(raw)) {
    try {
      array = JSON.parse(raw.toString('utf8'));
    } catch {
      return [];
    }
  } else if (Array.isArray(raw)) {
    array = raw;
  } else {
    return [];
  }

  if (!Array.isArray(array)) {
    return [];
  }

  return array
    .filter((item) => item && typeof item === 'object')
    .map((item) => {
      const record = item as Record<string, unknown>;
      return {
        name: String(record.name ?? ''),
        quantity: Number(record.quantity ?? 0),
        widthM: Number(record.widthM ?? 0),
        heightM: Number(record.heightM ?? 0),
        depthM: Number(record.depthM ?? 0),
        modelPath: record.modelPath != null ? String(record.modelPath) : undefined,
        notes: record.notes != null ? String(record.notes) : undefined,
      };
    })
    .filter(
      (item) =>
        item.name.trim().length > 0 &&
        item.quantity > 0 &&
        item.widthM > 0 &&
        item.heightM > 0 &&
        item.depthM > 0,
    );
};
