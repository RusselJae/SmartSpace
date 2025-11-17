# 🗄️ Database Setup Guide for SmartSpace AR

## 📋 Prerequisites

1. **MySQL Server** - Install from [mysql.com](https://dev.mysql.com/downloads/mysql/)
2. **Flutter Dependencies** - Run `flutter pub get`

## 🚀 Quick Setup

### Step 1: Create Environment File

1. Copy the example environment file:
   ```bash
   cp env.example .env
   ```

2. Edit `.env` with your MySQL credentials:
   ```env
   DB_HOST=localhost
   DB_PORT=3306
   DB_NAME=smartspace_ar
   DB_USERNAME=root
   DB_PASSWORD=your_actual_mysql_password
   ```

### Step 2: Create Database

1. Open MySQL Workbench or command line:
   ```bash
   mysql -u root -p
   ```

2. Run the database creation script:
   ```sql
   source sql/create_database.sql
   ```

### Step 3: Install Dependencies

```bash
flutter pub get
```

### Step 4: Run the App

```bash
flutter run
```

## 🔧 Configuration Options

### Database Settings
- `DB_HOST` - MySQL server host (default: localhost)
- `DB_PORT` - MySQL server port (default: 3306)
- `DB_NAME` - Database name (default: smartspace_ar)
- `DB_USERNAME` - MySQL username (default: root)
- `DB_PASSWORD` - MySQL password (required)

### Connection Settings
- `DB_TIMEOUT` - Connection timeout in seconds (default: 30)
- `DB_MAX_CONNECTIONS` - Maximum connections (default: 10)
- `DB_MIN_CONNECTIONS` - Minimum connections (default: 2)

### Application Settings
- `APP_ENV` - Environment (development/production)
- `APP_DEBUG` - Enable debug mode (true/false)

## 📊 Database Schema

### Products Table (10 sample products included)
```sql
CREATE TABLE products (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category VARCHAR(100) NOT NULL,
    style VARCHAR(100) NOT NULL,
    material VARCHAR(100) NOT NULL,
    color VARCHAR(100) NOT NULL,
    size VARCHAR(50) NOT NULL,
    model_path VARCHAR(500) NOT NULL,
    rating DECIMAL(3,2) DEFAULT 0,
    review_count INT DEFAULT 0,
    is_popular BOOLEAN DEFAULT FALSE,
    is_new_arrival BOOLEAN DEFAULT FALSE,
    in_stock BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Users Table
```sql
CREATE TABLE users (
    id VARCHAR(50) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20),
    addresses JSON,
    wishlist_product_ids JSON,
    preferred_style VARCHAR(100),
    min_budget DECIMAL(10,2) DEFAULT 0,
    max_budget DECIMAL(10,2) DEFAULT 10000,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Orders Table
```sql
CREATE TABLE orders (
    id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    product_ids JSON NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'confirmed', 'shipped', 'delivered', 'cancelled'),
    shipping_address JSON NOT NULL,
    payment_method ENUM('card', 'paypal', 'cod') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

## 🔍 Troubleshooting

### Connection Failed
1. ✅ Check MySQL server is running
2. ✅ Verify credentials in `.env` file
3. ✅ Test connection with MySQL Workbench
4. ✅ Check firewall settings

### App Falls Back to Mock Data
- This is normal if MySQL connection fails
- Check console for connection error messages
- Verify database exists and credentials are correct

### Performance Issues
- Database includes optimized indexes
- Connection pooling is configured
- Queries are optimized for mobile usage

## 🔒 Security Notes

### Development
- `.env` file is ignored by git (never commit credentials)
- Default credentials are for local development only

### Production
- Use strong passwords and secure connections
- Enable SSL/TLS for database connections
- Use environment variables on server
- Set up proper user permissions and roles

## 📱 Sample Data Included

The database comes with:
- **10 furniture products** (chairs using chair.glb model)
- **1 sample user** for testing
- **Optimized indexes** for performance
- **Proper foreign key relationships**

Categories: Living Room, Dining, Bedroom, Office, Outdoor, Kids
Styles: Modern, Classic, Minimal, Industrial
Materials: Wood, Metal, Fabric, Leather

## 🆘 Need Help?

1. Check the console output for detailed error messages
2. Verify your MySQL installation and credentials
3. Ensure the database and tables are created properly
4. Test the connection using MySQL Workbench first













