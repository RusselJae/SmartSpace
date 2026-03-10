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
  // Check if email is configured
  if (!config.email.username || !config.email.password) {
    console.warn('');
    console.warn('⚠️  EMAIL SERVICE NOT CONFIGURED');
    console.warn('═══════════════════════════════════════════════════════════');
    console.warn('Email verification will NOT work until SMTP is configured.');
    console.warn('');
    console.warn('Add these to your backend/.env file:');
    console.warn('  SMTP_HOST=smtp.gmail.com');
    console.warn('  SMTP_PORT=587');
    console.warn('  SMTP_SECURE=false');
    console.warn('  SMTP_USERNAME=your_email@gmail.com');
    console.warn('  SMTP_PASSWORD=your_app_password');
    console.warn('  SMTP_FROM=SmartSpace AR <your_email@gmail.com>');
    console.warn('');
    console.warn('For Gmail setup:');
    console.warn('  1. Enable 2-Factor Authentication');
    console.warn('  2. Generate App Password: https://myaccount.google.com/apppasswords');
    console.warn('  3. Use the App Password (not your regular password)');
    console.warn('═══════════════════════════════════════════════════════════');
    console.warn('');
  } else {
    console.log('✅ Email service configured');
    console.log(`   Host: ${config.email.host}:${config.email.port}`);
    console.log(`   From: ${config.email.from}`);
  }
};

const initialize = async (): Promise<void> => {
  try {
    const pool = getPool();
    await pool.query('SELECT 1');
    
    // Check email configuration before starting server
    checkEmailConfiguration();
    
    startServer();
    
    // Start auto-cancellation scheduler for unpaid orders
    try {
      const { startAutoCancelScheduler } = await import('./jobs/auto_cancel_job');
      startAutoCancelScheduler();
    } catch (error) {
      console.warn('⚠️ Could not start auto-cancellation scheduler:', error);
      console.warn('   Install node-cron: npm install node-cron');
      console.warn('   Or manually call POST /api/orders/auto-cancel periodically');
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
  } catch (error) {
    console.error('Failed to initialize database connection', error);
    process.exit(1);
  }
};

void initialize();





