-- ============================================================================
-- SmartSpace Schema v2
-- ----------------------------------------------------------------------------
-- This script rebuilds the SmartSpace MySQL schema so it mirrors the current
-- Flutter app flow:
--   • Structured profile data (username, gender, DOB, avatar)
--   • First-class user addresses with default flag support
--   • Wishlists captured via a junction table instead of JSON blobs
--   • Normalized orders (contact snapshot, shipping details, line items, history)
--   • Product media separated for multi-image layouts
--   • Compatibility view (order_feed_vw) that emits the legacy JSON payload the
--     existing API returns today so the mobile app/web admin stay functional
--     while the backend migrates to the richer tables.
--
-- Run the script on MySQL 8.0+.
-- ============================================================================

DROP DATABASE IF EXISTS smartspace_ar;
CREATE DATABASE smartspace_ar CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE smartspace_ar;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS order_status_history;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS wishlist_items;
DROP TABLE IF EXISTS user_addresses;
DROP TABLE IF EXISTS product_media;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- Users capture all profile level metadata so we can hydrate My Profile UI
-- without piecing together JSON blobs.
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id              VARCHAR(50)  PRIMARY KEY,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255),
    full_name       VARCHAR(150) NOT NULL,
    username        VARCHAR(80)  NOT NULL UNIQUE,
    gender          ENUM('male','female','other') NULL,
    date_of_birth   DATE NULL,
    avatar_url      LONGTEXT,
    phone_number    VARCHAR(32),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    last_login_at   TIMESTAMP NULL
);

-- ----------------------------------------------------------------------------
-- Structured addresses back the "My Addresses" screen.
-- ----------------------------------------------------------------------------
CREATE TABLE user_addresses (
    id            VARCHAR(50) PRIMARY KEY,
    user_id       VARCHAR(50) NOT NULL,
    full_name     VARCHAR(150) NOT NULL,
    phone_number  VARCHAR(32)  NOT NULL,
    region        VARCHAR(255) NOT NULL,
    postal_code   VARCHAR(20),
    street        VARCHAR(255) NOT NULL,
    label         ENUM('Home','Work','Other') DEFAULT 'Home',
    is_default    BOOLEAN DEFAULT FALSE,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_addresses_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_addresses_user (user_id),
    INDEX idx_user_addresses_default (is_default)
);

-- ----------------------------------------------------------------------------
-- Wishlists are now a simple junction table.
-- ----------------------------------------------------------------------------
CREATE TABLE wishlist_items (
    user_id    VARCHAR(50) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, product_id)
);

-- ----------------------------------------------------------------------------
-- Persist the active cart so every device (web, iOS, Android) stays in sync.
-- ----------------------------------------------------------------------------
CREATE TABLE cart_items (
    id              VARCHAR(50) PRIMARY KEY,
    user_id         VARCHAR(50) NOT NULL,
    product_id      VARCHAR(50) NOT NULL,
    quantity        INT NOT NULL DEFAULT 1,
    unit_price      DECIMAL(10,2) NOT NULL,
    notes           VARCHAR(255),
    added_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_cart_items_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_cart_items_product
        FOREIGN KEY (product_id) REFERENCES products(id),
    INDEX idx_cart_items_user (user_id),
    INDEX idx_cart_items_product (product_id)
);

-- ----------------------------------------------------------------------------
-- Products carry all descriptive metadata for the AR previews and storefront.
-- ----------------------------------------------------------------------------
CREATE TABLE products (
    id              VARCHAR(50)  PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    price           DECIMAL(10,2) NOT NULL,
    category        VARCHAR(100) NOT NULL,
    style           VARCHAR(100) NOT NULL,
    material        VARCHAR(100) NOT NULL,
    color           VARCHAR(100) NOT NULL,
    size            VARCHAR(50)  NOT NULL,
    model_path      VARCHAR(500) NOT NULL,
    cover_image_url VARCHAR(500),
    image_urls      JSON,
    rating          DECIMAL(3,2) DEFAULT 0,
    review_count    INT DEFAULT 0,
    inventory_qty   INT DEFAULT 0,
    is_popular      BOOLEAN DEFAULT FALSE,
    is_new_arrival  BOOLEAN DEFAULT FALSE,
    in_stock        BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_products_category (category),
    INDEX idx_products_style (style),
    INDEX idx_products_is_popular (is_popular),
    INDEX idx_products_is_new_arrival (is_new_arrival),
    INDEX idx_products_in_stock (in_stock)
);

CREATE TABLE product_media (
    id         VARCHAR(50) PRIMARY KEY,
    product_id VARCHAR(50) NOT NULL,
    media_url  VARCHAR(500) NOT NULL,
    sort_order TINYINT UNSIGNED DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_product_media_product
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    INDEX idx_product_media_product (product_id)
);

-- ----------------------------------------------------------------------------
-- Reviews feed both the Ratings UI and admin moderation workflow.
-- ----------------------------------------------------------------------------
CREATE TABLE reviews (
    id         VARCHAR(50) PRIMARY KEY,
    product_id VARCHAR(50) NOT NULL,
    user_id    VARCHAR(50) NOT NULL,
    rating     TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    content    TEXT,
    status     ENUM('pending','published','flagged','archived') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_reviews_product
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    CONSTRAINT fk_reviews_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_reviews_product (product_id),
    INDEX idx_reviews_user (user_id),
    INDEX idx_reviews_status (status)
);

-- ----------------------------------------------------------------------------
-- Orders store a snapshot of the contact + shipping info plus denormalized
-- totals so the checkout confirmation screen matches exactly what was shown.
-- ----------------------------------------------------------------------------
CREATE TABLE orders (
    id               VARCHAR(50) PRIMARY KEY,
    user_id          VARCHAR(50) NOT NULL,
    contact_name     VARCHAR(150) NOT NULL,
    contact_phone    VARCHAR(32)  NOT NULL,
    shipping_label   VARCHAR(20),
    shipping_line1   VARCHAR(255) NOT NULL,
    shipping_line2   VARCHAR(255),
    shipping_region  VARCHAR(255) NOT NULL,
    shipping_postal  VARCHAR(20),
    subtotal_amount  DECIMAL(10,2) NOT NULL,
    shipping_fee     DECIMAL(10,2) NOT NULL,
    total_amount     DECIMAL(10,2) NOT NULL,
    status           ENUM('pending','confirmed','shipped','delivered','cancelled','refunded')
                         DEFAULT 'pending',
    payment_method   ENUM('card','paypal','cod') NOT NULL,
    payment_status   ENUM('pending','completed','failed','refunded') DEFAULT 'pending',
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_orders_user
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_orders_user (user_id),
    INDEX idx_orders_status (status),
    INDEX idx_orders_created (created_at)
);

CREATE TABLE order_items (
    id          VARCHAR(50) PRIMARY KEY,
    order_id    VARCHAR(50) NOT NULL,
    product_id  VARCHAR(50) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    quantity    INT NOT NULL,
    unit_price  DECIMAL(10,2) NOT NULL,
    line_total  DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id) REFERENCES products(id),
    INDEX idx_order_items_order (order_id)
);

CREATE TABLE order_status_history (
    id         VARCHAR(50) PRIMARY KEY,
    order_id   VARCHAR(50) NOT NULL,
    status     VARCHAR(30) NOT NULL,
    note       VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_status_history_order
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    INDEX idx_status_history_order (order_id)
);

-- ----------------------------------------------------------------------------
-- Sample seed data so local dev instances immediately have realistic rows.
-- ----------------------------------------------------------------------------
INSERT INTO users (
    id, email, password_hash, full_name, username, gender, date_of_birth,
    avatar_url, phone_number, created_at, last_login_at
) VALUES
('u_demo', 'russel@example.com', NULL, 'Russel Jae Dahonog', 'jaepogi27', 'male',
 NULL, NULL, '09692353537', NOW(), NOW());

INSERT INTO user_addresses (
    id, user_id, full_name, phone_number, region, postal_code, street,
    label, is_default
) VALUES
('addr_demo', 'u_demo', 'Russel Jae Dahonog', '09692353537',
 'South Luzon, Cavite, Bacoor, Molino VII', '4102',
 'Blk 1, Lot 65, Waling-Waling Street, San Lorenzo Ruiz Homes',
 'Home', TRUE);

INSERT INTO products (
    id, name, description, price, category, style, material, color, size,
    model_path, cover_image_url, image_urls, rating, review_count,
    inventory_qty, is_popular, is_new_arrival, in_stock
) VALUES
('p1', 'Modern Dining Chair', 'Elegant wooden dining chair with comfortable cushioning',
 299.99, 'Dining', 'Modern', 'Wood', 'Brown', 'M',
 'assets/chair.glb', NULL, JSON_ARRAY(), 4.5, 128, 12, TRUE, FALSE, TRUE),
('p2', 'Executive Office Chair', 'Premium leather office chair with ergonomic design',
 599.99, 'Office', 'Classic', 'Leather', 'Black', 'L',
 'assets/chair.glb', NULL, JSON_ARRAY(), 4.8, 89, 8, TRUE, TRUE, TRUE),
('p3', 'Minimalist Lounge Chair', 'Simple yet elegant chair perfect for living rooms',
 449.99, 'Living Room', 'Minimal', 'Fabric', 'Light Brown', 'M',
 'assets/chair.glb', NULL, JSON_ARRAY(), 4.3, 67, 5, FALSE, TRUE, TRUE);

INSERT INTO product_media (id, product_id, media_url, sort_order) VALUES
('pm1', 'p1', 'https://cdn.smartspace.app/products/p1/hero.jpg', 0),
('pm2', 'p1', 'https://cdn.smartspace.app/products/p1/detail.jpg', 1),
('pm3', 'p2', 'https://cdn.smartspace.app/products/p2/hero.jpg', 0);

INSERT INTO wishlist_items (user_id, product_id) VALUES
('u_demo', 'p1'),
('u_demo', 'p3');

INSERT INTO cart_items (id, user_id, product_id, quantity, unit_price, notes) VALUES
('cart1', 'u_demo', 'p1', 1, 299.99, 'Saved from AR preview'),
('cart2', 'u_demo', 'p3', 2, 449.99, 'Duplicate order reminder');

INSERT INTO reviews (
    id, product_id, user_id, rating, content, status
) VALUES
('r1', 'p1', 'u_demo', 5, 'Incredible craftsmanship. The chair elevates my dining nook.', 'published');

INSERT INTO orders (
    id, user_id, contact_name, contact_phone, shipping_label,
    shipping_line1, shipping_line2, shipping_region, shipping_postal,
    subtotal_amount, shipping_fee, total_amount, status,
    payment_method, payment_status
) VALUES
('o1', 'u_demo', 'Russel Jae Dahonog', '09692353537', 'Home',
 'Blk 1, Lot 65, Waling-Waling Street, San Lorenzo Ruiz Homes', NULL,
 'South Luzon, Cavite, Bacoor, Molino VII', '4102',
 949.98, 20.00, 969.98, 'pending', 'card', 'pending');

INSERT INTO order_items (
    id, order_id, product_id, product_name, quantity, unit_price, line_total
) VALUES
('oi1', 'o1', 'p1', 'Modern Dining Chair', 2, 299.99, 599.98),
('oi2', 'o1', 'p3', 'Minimalist Lounge Chair', 1, 349.99, 349.99);

INSERT INTO order_status_history (id, order_id, status, note) VALUES
('osh1', 'o1', 'pending', 'Order submitted from iOS profile checkout');

-- ----------------------------------------------------------------------------
-- Compatibility view: exposes the legacy shape (productIds JSON + shipping JSON)
-- consumed by the current Node service + Flutter models so we can migrate
-- application code incrementally.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW order_feed_vw AS
SELECT
    o.id,
    o.user_id,
    u.full_name AS user_name,
    IFNULL(JSON_ARRAYAGG(oi.product_id), JSON_ARRAY()) AS product_ids,
    o.total_amount,
    o.status,
    JSON_OBJECT(
        'name', o.contact_name,
        'phone', o.contact_phone,
        'label', COALESCE(o.shipping_label, ''),
        'line1', o.shipping_line1,
        'line2', COALESCE(o.shipping_line2, ''),
        'city', o.shipping_region,
        'postalCode', COALESCE(o.shipping_postal, '')
    ) AS shipping_address,
    o.created_at,
    o.updated_at
FROM orders o
LEFT JOIN users u ON u.id = o.user_id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY
    o.id,
    o.user_id,
    u.full_name,
    o.total_amount,
    o.status,
    o.contact_name,
    o.contact_phone,
    o.shipping_label,
    o.shipping_line1,
    o.shipping_line2,
    o.shipping_region,
    o.shipping_postal,
    o.created_at,
    o.updated_at;

-- Example index combo for quick storefront queries.
CREATE INDEX idx_products_category_popular ON products (category, is_popular);
CREATE INDEX idx_products_new_arrival_created ON products (is_new_arrival, created_at);
CREATE INDEX idx_orders_user_status ON orders (user_id, status);

COMMIT;

