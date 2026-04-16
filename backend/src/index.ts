import { createServer, Server } from 'http';
import { createApp } from './app';
import { config } from './config/env';
import { getPool } from './config/database';

const startServer = (): Server => {
  const app = createApp();
  const server = createServer(app);
  // Listen on 0.0.0.0 to accept connections from all network interfaces
  // This allows devices on the same network to connect using your IPv4 address
  server.listen(config.port, '0.0.0.0', () => {
    console.log(`🚀 ${config.appName} listening on port ${config.port}`);
    console.log(`📡 Server accessible at:`);
    console.log(`   - http://localhost:${config.port}`);
    console.log(`   - http://127.0.0.1:${config.port}`);
    console.log(`   - http://[YOUR_IPv4_ADDRESS]:${config.port}`);
    console.log(`💡 To find your IPv4 address, run: ipconfig (Windows) or ifconfig (Mac/Linux)`);
  });
  return server;
};

const checkEmailConfiguration = (): void => {
  // Brevo uses HTTPS API, so it doesn't depend on SMTP egress like Gmail.
  // SendGrid (Single Sender Verification) works without a custom domain too.
  const hasBrevo = Boolean(config.brevo.apiKey);
  const hasSendGrid = Boolean(config.sendgrid.apiKey);

  if (!hasBrevo && !hasSendGrid) {
    console.warn('');
    console.warn('⚠️  EMAIL SERVICE NOT CONFIGURED');
    console.warn('═══════════════════════════════════════════════════════════');
    console.warn('Verification emails will NOT work until Brevo or SendGrid is configured.');
    console.warn('');
    console.warn('Add these to your backend environment:');
    console.warn('  BREVO_API_KEY=... (from Brevo dashboard)');
    console.warn('  BREVO_FROM=Your App <you@gmail.com> (sender identity in Brevo)');
    console.warn('  (or) SENDGRID_API_KEY=... and SENDGRID_FROM=... (verified in SendGrid Sender Identity)');
    console.warn('═══════════════════════════════════════════════════════════');
    console.warn('');
  } else {
    if (hasBrevo) {
      console.log('✅ Email service configured (Brevo)');
      console.log(`   From: ${config.brevo.from}`);
    } else {
      console.log('✅ Email service configured (SendGrid)');
      console.log(`   From: ${config.sendgrid.from}`);
    }
  }
};

const initialize = async (): Promise<void> => {
  try {
    // Log the resolved DB target so Render misconfigurations are obvious.
    // (Never log the password.)
    console.log('🗄️  Database config:');
    console.log(`   Host: ${config.database.host}`);
    console.log(`   Port: ${config.database.port}`);
    console.log(`   Name: ${config.database.name}`);
    console.log(`   User: ${config.database.username}`);
    console.log(`   SSL enabled (DB_SSL): ${process.env.DB_SSL === 'true'}`);

    const pool = getPool();
    await pool.query('SELECT 1');
    
    // Check email configuration before starting server
    checkEmailConfiguration();
    
    startServer();

    // PayMongo unpaid orders: reminder email + timed cancel (inventory release). See order_service.autoCancelUnpaidOrders.
    try {
      const { startAutoCancelScheduler } = await import('./jobs/auto_cancel_job');
      startAutoCancelScheduler();
    } catch (error) {
      console.warn('⚠️ Could not start unpaid-order scheduler:', error);
    }

    // Start cleanup scheduler for unverified user accounts
    try {
      const { startCleanupUnverifiedUsersScheduler } = await import('./jobs/cleanup_unverified_users_job');
      startCleanupUnverifiedUsersScheduler();
    } catch (error) {
      console.warn('⚠️ Could not start unverified users cleanup scheduler:', error);
      console.warn('   Install node-cron: npm install node-cron');
      console.warn('   Or manually call the cleanup function periodically');
    }

    // Installment policy: late fees + 6-month default cancellation + invoice updates.
    try {
      const { startInstallmentPolicyScheduler } = await import('./jobs/auto_installment_policy_job');
      startInstallmentPolicyScheduler();
    } catch (error) {
      console.warn('⚠️ Could not start installment policy scheduler:', error);
    }
  } catch (error) {
    console.error('Failed to initialize database connection', error);
    process.exit(1);
  }
};

void initialize();





