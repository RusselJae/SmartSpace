-- SmartSpace AR Database Schema
-- Run this script in your MySQL server to create the database and tables

-- Create database
CREATE DATABASE IF NOT EXISTS smartspace_ar;
USE smartspace_ar;

-- Create products table
CREATE TABLE IF NOT EXISTS products (
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
    image_urls JSON,
    rating DECIMAL(3,2) DEFAULT 0,
    review_count INT DEFAULT 0,
    is_popular BOOLEAN DEFAULT FALSE,
    is_new_arrival BOOLEAN DEFAULT FALSE,
    in_stock BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_category (category),
    INDEX idx_popular (is_popular),
    INDEX idx_new_arrival (is_new_arrival),
    INDEX idx_in_stock (in_stock),
    INDEX idx_rating (rating),
    INDEX idx_created_at (created_at)
);

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(50) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(20),
    addresses JSON,
    wishlist_product_ids JSON,
    order_ids JSON,
    preferred_style VARCHAR(100),
    min_budget DECIMAL(10,2) DEFAULT 0,
    max_budget DECIMAL(10,2) DEFAULT 10000,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_email (email),
    INDEX idx_created_at (created_at)
);

-- Create orders table
CREATE TABLE IF NOT EXISTS orders (
    id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    product_ids JSON NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'confirmed', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',
    shipping_address JSON NOT NULL,
    delivery_date DATE,
    delivery_time_slot VARCHAR(50),
    payment_method ENUM('card', 'paypal', 'cod') NOT NULL,
    payment_status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
);

-- Create reviews table
CREATE TABLE IF NOT EXISTS reviews (
    id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    INDEX idx_product_id (product_id),
    INDEX idx_user_id (user_id),
    INDEX idx_rating (rating),
    INDEX idx_created_at (created_at)
);

-- Create admins table
CREATE TABLE IF NOT EXISTS admins (
    id VARCHAR(50) PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP NULL,
    
    INDEX idx_email (email),
    INDEX idx_created_at (created_at)
);

-- Insert sample products
INSERT INTO products (
    id, name, description, price, category, style, material, color, size,
    model_path, image_urls, rating, review_count, is_popular, is_new_arrival, in_stock
) VALUES 
('p1', 'Modern Dining Chair', 'Elegant wooden dining chair with comfortable cushioning', 299.99, 'Dining', 'Modern', 'Wood', 'Brown', 'M', 'assets/chair.glb', '[]', 4.5, 128, TRUE, FALSE, TRUE),
('p2', 'Executive Office Chair', 'Premium leather office chair with ergonomic design', 599.99, 'Office', 'Classic', 'Leather', 'Black', 'L', 'assets/chair.glb', '[]', 4.8, 89, TRUE, TRUE, TRUE),
('p3', 'Minimalist Lounge Chair', 'Simple yet elegant chair perfect for living rooms', 449.99, 'Living Room', 'Minimal', 'Fabric', 'Light Brown', 'M', 'assets/chair.glb', '[]', 4.3, 67, FALSE, TRUE, TRUE),
('p4', 'Industrial Bar Stool', 'Sturdy metal and wood bar stool with industrial design', 189.99, 'Dining', 'Industrial', 'Metal', 'Dark Brown', 'S', 'assets/chair.glb', '[]', 4.1, 45, FALSE, FALSE, TRUE),
('p5', 'Kids Study Chair', 'Colorful and comfortable chair designed for children', 129.99, 'Kids', 'Modern', 'Fabric', 'Blue', 'S', 'assets/chair.glb', '[]', 4.6, 156, TRUE, FALSE, TRUE),
('p6', 'Outdoor Patio Chair', 'Weather-resistant chair perfect for outdoor spaces', 249.99, 'Outdoor', 'Modern', 'Metal', 'White', 'M', 'assets/chair.glb', '[]', 4.4, 78, FALSE, TRUE, TRUE),
('p7', 'Vintage Armchair', 'Classic vintage-style armchair with rich leather upholstery', 799.99, 'Living Room', 'Classic', 'Leather', 'Brown', 'L', 'assets/chair.glb', '[]', 4.7, 92, TRUE, FALSE, TRUE),
('p8', 'Bedroom Accent Chair', 'Soft and cozy chair perfect for bedroom corners', 349.99, 'Bedroom', 'Minimal', 'Fabric', 'Light Brown', 'M', 'assets/chair.glb', '[]', 4.2, 54, FALSE, TRUE, TRUE),
('p9', 'Gaming Chair Pro', 'High-performance gaming chair with RGB lighting', 699.99, 'Office', 'Modern', 'Fabric', 'Black', 'L', 'assets/chair.glb', '[]', 4.9, 203, TRUE, TRUE, TRUE),
('p10', 'Scandinavian Dining Chair', 'Clean lines and natural wood in Scandinavian style', 199.99, 'Dining', 'Minimal', 'Wood', 'Natural', 'M', 'assets/chair.glb', '[]', 4.4, 87, FALSE, FALSE, TRUE);

-- Insert sample user
INSERT INTO users (
    id, email, full_name, phone_number, addresses, wishlist_product_ids, order_ids,
    preferred_style, min_budget, max_budget
) VALUES (
    'u1', 'john.doe@example.com', 'John Doe', '+1234567890', 
    '["123 Main St, City, State 12345"]', '["p1", "p3", "p7"]', '[]',
    'Modern', 100, 1000
);

-- Create indexes for better performance
CREATE INDEX idx_products_category_popular ON products(category, is_popular);
CREATE INDEX idx_products_new_arrival_created ON products(is_new_arrival, created_at);
CREATE INDEX idx_orders_user_status ON orders(user_id, status);

COMMIT;













