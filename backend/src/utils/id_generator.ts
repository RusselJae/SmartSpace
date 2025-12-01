import { randomInt } from 'crypto';

export const generateId = (prefix: string): string => {
  const millis = Date.now();
  const suffix = randomInt(0, 9999).toString().padStart(4, '0');
  return `${prefix}${millis}${suffix}`;
};




