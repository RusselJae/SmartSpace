import { NextFunction, Request, Response } from 'express';

// Express route handlers commonly end by returning `res.json(...)` or `res.status(...).send(...)`.
// Narrowing this to `Promise<void>` forces every route to avoid returning the response, which
// doesn't match the style used across this codebase.
type AsyncRouteHandler = (req: Request, res: Response, next: NextFunction) => Promise<unknown>;

export const asyncHandler =
  (handler: AsyncRouteHandler) => (req: Request, res: Response, next: NextFunction): void => {
    handler(req, res, next).catch(next);
  };




