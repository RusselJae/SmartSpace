import { Router } from 'express';
import { asyncHandler } from '../utils/async_handler';
import {
  listFaqs,
  createFaq,
  updateFaq,
  deleteFaq,
  type CreateFaqInput,
  type UpdateFaqInput,
} from '../services/faq_service';
import { logAdminActivity } from '../services/admin_activity_log_service';

export const faqRouter = Router();

/**
 * GET /api/faqs
 * Public endpoint – returns all FAQs ordered by sort_order.
 */
faqRouter.get(
  '/',
  asyncHandler(async (_req, res) => {
    const faqs = await listFaqs();
    res.json({ success: true, data: faqs });
  }),
);

/**
 * POST /api/faqs/admin
 * Admin-only: create a new FAQ.
 * Body: { adminId: string, question: string, answer: string, sortOrder?: number }
 */
faqRouter.post(
  '/admin',
  asyncHandler(async (req, res) => {
    const { adminId, question, answer, sortOrder } = req.body as {
      adminId?: string;
      question?: string;
      answer?: string;
      sortOrder?: number;
    };

    if (!adminId) {
      return res.status(400).json({ success: false, message: 'adminId is required' });
    }
    if (!question || !question.trim()) {
      return res.status(400).json({ success: false, message: 'question is required' });
    }
    if (!answer || !answer.trim()) {
      return res.status(400).json({ success: false, message: 'answer is required' });
    }

    const input: CreateFaqInput = {
      question: question.trim(),
      answer: answer.trim(),
      sortOrder: sortOrder != null ? Number(sortOrder) : undefined,
    };

    const faq = await createFaq(input);
    await logAdminActivity({
      adminId,
      action: 'faq_created',
      entityType: 'faq',
      entityId: faq.id,
      details: { question: faq.question },
    });
    res.status(201).json({ success: true, data: faq });
  }),
);

/**
 * PUT /api/faqs/admin/:id
 * Admin-only: update an existing FAQ.
 */
faqRouter.put(
  '/admin/:id',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const { adminId, question, answer, sortOrder } = req.body as {
      adminId?: string;
      question?: string;
      answer?: string;
      sortOrder?: number;
    };

    if (!adminId) {
      return res.status(400).json({ success: false, message: 'adminId is required' });
    }

    const input: UpdateFaqInput = {};
    if (question !== undefined) input.question = String(question).trim();
    if (answer !== undefined) input.answer = String(answer).trim();
    if (sortOrder !== undefined) input.sortOrder = Number(sortOrder);

    const faq = await updateFaq(id, input);
    if (faq == null) {
      return res.status(404).json({ success: false, message: 'FAQ not found' });
    }
    await logAdminActivity({
      adminId,
      action: 'faq_updated',
      entityType: 'faq',
      entityId: faq.id,
      details: {
        question: faq.question,
      },
    });
    res.json({ success: true, data: faq });
  }),
);

/**
 * DELETE /api/faqs/admin/:id
 * Admin-only: delete an FAQ.
 * Query: ?adminId=xxx (body not reliable for DELETE in some clients)
 */
faqRouter.delete(
  '/admin/:id',
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const adminId = (req.query.adminId as string) || (req.body?.adminId as string);

    if (!adminId) {
      return res.status(400).json({ success: false, message: 'adminId is required (query or body)' });
    }

    const deleted = await deleteFaq(id);
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'FAQ not found' });
    }
    await logAdminActivity({
      adminId,
      action: 'faq_deleted',
      entityType: 'faq',
      entityId: id,
    });
    res.json({ success: true, message: 'FAQ deleted' });
  }),
);
