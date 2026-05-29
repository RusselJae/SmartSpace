import { EmailService } from './email_service';
import { createNotificationForUser } from './user_notification_service';

/** Fire-and-forget: customer submitted a custom furniture request. */
export const notifyAdminsNewMadeToOrderRequest = (params: {
  readonly requestId: string;
  readonly requestRef: string;
  readonly userId: string;
  readonly userName: string;
  readonly itemName: string;
}): void => {
  const shortRef = params.requestRef.length > 8
    ? params.requestRef.substring(0, 8).toUpperCase()
    : params.requestRef.toUpperCase();

  EmailService.sendAdminEventEmail({
    title: 'New made-to-order request',
    message: `${params.userName || 'A customer'} submitted a custom furniture request. Review and send a quote in the admin Orders panel.`,
    details: [
      { label: 'Request ID', value: params.requestId },
      { label: 'Reference', value: shortRef },
      { label: 'Customer', value: params.userName || 'n/a' },
      { label: 'User ID', value: params.userId },
      { label: 'Item / design', value: params.itemName },
    ],
  }).catch((error) => {
    console.error('Failed to send admin MTO request alert email:', error);
  });
};

/** Fire-and-forget: admin quoted — tell the customer in-app and by email. */
export const notifyUserMadeToOrderQuoted = (params: {
  readonly userId: string;
  readonly requestId: string;
  readonly requestRef: string;
  readonly itemName: string;
  readonly quotedTotal: number;
  readonly quotedDownpayment: number;
  readonly quotedRemaining: number;
  readonly adminMessage?: string | null;
}): void => {
  const shortRef = params.requestRef.length > 8
    ? params.requestRef.substring(0, 8).toUpperCase()
    : params.requestRef.toUpperCase();

  createNotificationForUser({
    userId: params.userId,
    type: 'made_to_order_quoted',
    title: 'Your custom quote is ready',
    body: `We quoted ${params.itemName} (ref ${shortRef}). Open Made to Order in the app to review and pay your deposit.`,
    data: {
      requestId: params.requestId,
      requestRef: params.requestRef,
      status: 'quoted',
    },
    push: true,
  }).catch((error) => {
    console.error('Failed to create MTO quote user notification:', error);
  });

  EmailService.sendMadeToOrderQuoteEmail({
    userId: params.userId,
    requestRef: params.requestRef,
    itemName: params.itemName,
    quotedTotal: params.quotedTotal,
    quotedDownpayment: params.quotedDownpayment,
    quotedRemaining: params.quotedRemaining,
    adminMessage: params.adminMessage,
  }).catch((error) => {
    console.error('Failed to send MTO quote email:', error);
  });
};

/** Fire-and-forget: quote sent — keep admin inboxes in sync for the team. */
export const notifyAdminsMadeToOrderQuoted = (params: {
  readonly requestId: string;
  readonly requestRef: string;
  readonly userName: string;
  readonly itemName: string;
  readonly quotedTotal: number;
}): void => {
  const shortRef = params.requestRef.length > 8
    ? params.requestRef.substring(0, 8).toUpperCase()
    : params.requestRef.toUpperCase();

  EmailService.sendAdminEventEmail({
    title: 'Made-to-order quote sent',
    message: `A quote was sent to ${params.userName || 'the customer'} for request #${shortRef}.`,
    details: [
      { label: 'Request ID', value: params.requestId },
      { label: 'Reference', value: shortRef },
      { label: 'Customer', value: params.userName || 'n/a' },
      { label: 'Item / design', value: params.itemName },
      { label: 'Quoted total', value: `₱${params.quotedTotal.toFixed(2)}` },
    ],
  }).catch((error) => {
    console.error('Failed to send admin MTO quote alert email:', error);
  });
};
