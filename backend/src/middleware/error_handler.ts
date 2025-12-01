import { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';

type ErrorResponse = {
  readonly success: boolean;
  readonly message: string;
  readonly details?: unknown;
};

export const errorHandler = (
  error: Error,
  _req: Request,
  res: Response,
  _next: NextFunction,
): void => {
  console.error('Error handler:', error);
  console.error('Stack:', error.stack);
  
  if (error instanceof ZodError) {
    const payload: ErrorResponse = {
      success: false,
      message: 'Validation failed',
      details: error.flatten(),
    };
    res.status(400).json(payload);
    return;
  }

  const payload: ErrorResponse = {
    success: false,
    message: error.message,
    details: process.env.NODE_ENV === 'development' ? error.stack : undefined,
  };
  res.status(500).json(payload);
};


