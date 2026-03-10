import { autoCancelUnpaidOrders } from '../services/order_service';

/**
 * Auto-cancellation job for unpaid orders
 * 
 * This job should be run periodically (every 5-10 minutes) to cancel orders
 * that haven't received payment within 30 minutes.
 * 
 * In production, set up a cron job or use a task scheduler like:
 * - node-cron (npm install node-cron)
 * - PM2 cron jobs
 * - AWS Lambda scheduled events
 * - Kubernetes CronJob
 */
export const runAutoCancelJob = async (): Promise<void> => {
  try {
    const cancelledCount = await autoCancelUnpaidOrders();
    if (cancelledCount > 0) {
      console.log(`⏰ Auto-cancellation job: Cancelled ${cancelledCount} unpaid order(s)`);
    }
  } catch (error) {
    console.error('❌ Auto-cancellation job failed:', error);
  }
};

/**
 * Start the auto-cancellation job scheduler
 * Runs every 5 minutes
 */
export const startAutoCancelScheduler = (): void => {
  // Check if node-cron is available
  try {
    const cron = require('node-cron');
    
    // Run every 5 minutes
    cron.schedule('*/5 * * * *', async () => {
      await runAutoCancelJob();
    });
    
    console.log('✅ Auto-cancellation scheduler started (runs every 5 minutes)');
  } catch (error) {
    console.warn('⚠️ node-cron not installed. Auto-cancellation scheduler not started.');
    console.warn('   Install with: npm install node-cron');
    console.warn('   Or manually call /api/orders/auto-cancel endpoint periodically');
  }
};




















