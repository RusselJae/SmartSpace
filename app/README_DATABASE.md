# SmartSpace AR - MySQL Database Setup

## Prerequisites

1. **Install MySQL Server**
   - Download and install MySQL Server from [mysql.com](https://dev.mysql.com/downloads/mysql/)
   - Remember your root password during installation

2. **Install MySQL Workbench** (Optional but recommended)
   - Download from [mysql.com](https://dev.mysql.com/downloads/workbench/)
   - Provides a GUI for database management

## Database Setup

### Step 1: Create Database and Tables

1. Open MySQL Workbench or connect via command line:
   ```bash
   mysql -u root -p
   ```

2. Run the SQL script to create database and tables:
   ```sql
   source sql/create_database.sql
   ```
   
   Or copy and paste the contents of `sql/create_database.sql` into MySQL Workbench and execute.

### Step 2: Configure Connection

1. Open `lib/config/database_config.dart`
2. Update the connection settings:
   ```dart
   static const String host = 'localhost';        // Your MySQL host
   static const int port = 3306;                  // Your MySQL port
   static const String database = 'smartspace_ar'; // Database name
   static const String username = 'root';         // Your MySQL username
   static const String password = 'your_password'; // Your MySQL password
   ```

### Step 3: Install Dependencies

Run the following command to install MySQL dependencies:
```bash
flutter pub get
```

## Database Schema

### Products Table
- `id` - Unique product identifier
- `name` - Product name
- `description` - Product description
- `price` - Product price
- `category` - Product category (Living Room, Dining, Bedroom, Office, Outdoor, Kids)
- `style` - Design style (Modern, Classic, Minimal, Industrial)
- `material` - Material type (Wood, Metal, Fabric, Leather)
- `color` - Product color
- `size` - Product size (S, M, L)
- `model_path` - Path to 3D model file
- `rating` - Average rating (0-5)
- `review_count` - Number of reviews
- `is_popular` - Popular product flag
- `is_new_arrival` - New arrival flag
- `in_stock` - Stock availability

### Users Table
- `id` - Unique user identifier
- `email` - User email (unique)
- `full_name` - User's full name
- `phone_number` - Phone number
- `addresses` - JSON array of addresses
- `wishlist_product_ids` - JSON array of wishlist product IDs
- `preferred_style` - User's preferred furniture style
- `min_budget` / `max_budget` - Budget range

### Orders Table
- `id` - Unique order identifier
- `user_id` - Reference to user
- `product_ids` - JSON array of ordered product IDs
- `total_amount` - Order total
- `status` - Order status (pending, confirmed, shipped, delivered, cancelled)
- `shipping_address` - JSON delivery address
- `payment_method` - Payment method (card, paypal, cod)

## Sample Data

The database comes pre-loaded with:
- **10 furniture products** (all using chair.glb model)
- **1 sample user** for testing
- **Proper indexes** for optimal performance

## Troubleshooting

### Connection Issues
1. Ensure MySQL server is running
2. Check firewall settings
3. Verify credentials in `database_config.dart`
4. Test connection using MySQL Workbench

### Performance
- Database includes optimized indexes
- Connection pooling is configured
- Queries are optimized for mobile usage

### Fallback Mode
If MySQL connection fails, the app automatically falls back to mock data for development purposes.

## Production Deployment

For production deployment:
1. Use environment variables for database credentials
2. Enable SSL connections
3. Set up database backups
4. Configure proper user permissions
5. Use connection pooling for better performance













