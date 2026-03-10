import { deleteUnverifiedUsers } from '../services/user_service';

/**
 * Cleanup job for unverified user accounts
 * 
 * This job should be run periodically (every minute) to delete accounts
 * that haven't been verified within 5 minutes of creation.
 * 
 * In production, set up a cron job or use a task scheduler like:
 * - node-cron (npm install node-cron)
 * - PM2 cron jobs
 * - AWS Lambda scheduled events
 * - Kubernetes CronJob
 */
export const runCleanupUnverifiedUsersJob = async (): Promise<void> => {
  try {
    const deletedCount = await deleteUnverifiedUsers();
    if (deletedCount > 0) {
      console.log(`🧹 Cleanup job: Deleted ${deletedCount} unverified user account(s) older than 5 minutes`);
    }
  } catch (error) {
    console.error('❌ Cleanup unverified users job failed:', error);
  }
};

/**
 * Start the cleanup job scheduler
 * Runs every minute to ensure accounts are deleted promptly after 5 minutes
 */
export const startCleanupUnverifiedUsersScheduler = (): void => {
  // Check if node-cron is available
  try {
    const cron = require('node-cron');
    
    // Run every minute to ensure prompt cleanup
    // This ensures accounts are deleted within 5-6 minutes of creation
    cron.schedule('* * * * *', async () => {
      await runCleanupUnverifiedUsersJob();
    });
    
    console.log('✅ Unverified users cleanup scheduler started (runs every minute)');
    
    // Also run immediately on startup to clean up any existing unverified accounts
    runCleanupUnverifiedUsersJob().catch((error) => {
      console.error('❌ Initial cleanup of unverified users failed:', error);
    });
  } catch (error) {
    console.warn('⚠️ node-cron not installed. Unverified users cleanup scheduler not started.');
    console.warn('   Install with: npm install node-cron');
    console.warn('   Or manually call the cleanup function periodically');
    
    // Still run once on startup even without cron
    runCleanupUnverifiedUsersJob().catch((error) => {
      console.error('❌ Initial cleanup of unverified users failed:', error);
    });
  }
};











