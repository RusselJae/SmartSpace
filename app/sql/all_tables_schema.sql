-- ============================================================================
-- SmartSpace consolidated table schema
-- ----------------------------------------------------------------------------
-- Purpose:
--   Single SQL file containing all project table definitions (no seed data).
--   Built from existing SQL files + backend runtime schema ensure/alter logic.
--
-- Target:
--   MySQL 8.0+
-- ============================================================================

CREATE DATABASE IF NOT EXISTS smartspace_ar
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE smartspace_ar;

SET FOREIGN_KEY_CHECKS = 0;

-- Drop in dependency-safe order.
DROP TABLE IF EXISTS support_form_requests;
DROP TABLE IF EXISTS support_messages;
DROP TABLE IF EXISTS support_conversations;
DROP TABLE IF EXISTS user_device_tokens;
DROP TABLE IF EXISTS user_notifications;
DROP TABLE IF EXISTS legal_content_history;
DROP TABLE IF EXISTS legal_content;
DROP TABLE IF EXISTS admin_activity_logs;
DROP TABLE IF EXISTS order_late_fee_events;
DROP TABLE IF EXISTS order_payment_events;
DROP TABLE IF EXISTS order_material_deductions;
DROP TABLE IF EXISTS made_to_order_requests;
DROP TABLE IF EXISTS app_settings;
DROP TABLE IF EXISTS order_status_history;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS cart_items;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS wishlist_items;
DROP TABLE IF EXISTS product_media;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS user_addresses;
DROP TABLE IF EXISTS faqs;
DROP TABLE IF EXISTS inventory_materials;
DROP TABLE IF EXISTS product_variant_bom_lines;
DROP TABLE IF EXISTS product_variants;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS admins;
DROP TABLE IF EXISTS users;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE users (
  id                          VARCHAR(50) PRIMARY KEY,
  email                       VARCHAR(255) NOT NULL UNIQUE,
  password_hash               VARCHAR(255) NULL,
  full_name                   VARCHAR(150) NOT NULL,
  username                    VARCHAR(80) NOT NULL UNIQUE,
  gender                      ENUM('male','female','other') DEFAULT 'other',
  date_of_birth               DATE NULL,
  avatar_url                  VARCHAR(500) NULL,
  phone_number                VARCHAR(32) NULL,
  created_at                  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login_at               TIMESTAMP NULL DEFAULT NULL,
  email_verified              TINYINT(1) NOT NULL DEFAULT 0,
  verification_token          VARCHAR(255) NULL,
  verification_token_expires  DATETIME NULL,
  verification_code           VARCHAR(16) NULL,
  terms_version_accepted      INT NULL DEFAULT NULL,
  terms_accepted_at           TIMESTAMP NULL DEFAULT NULL,
  password_reset_token        VARCHAR(255) NULL,
  password_reset_expires      DATETIME NULL,
  KEY idx_verification_token (verification_token),
  KEY idx_verification_code (verification_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE admins (
  id                          VARCHAR(50) PRIMARY KEY,
  email                       VARCHAR(255) NOT NULL UNIQUE,
  password_hash               VARCHAR(255) NOT NULL,
  full_name                   VARCHAR(255) NOT NULL,
  created_at                  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login_at               TIMESTAMP NULL DEFAULT NULL,
  email_verified              TINYINT(1) NOT NULL DEFAULT 1,
  verification_token          VARCHAR(255) NULL,
  verification_token_expires  DATETIME NULL,
  verification_code           VARCHAR(16) NULL,
  password_reset_token        VARCHAR(255) NULL,
  password_reset_expires      DATETIME NULL,
  role                        VARCHAR(32) NOT NULL DEFAULT 'super_admin',
  is_disabled                 TINYINT(1) NOT NULL DEFAULT 0,
  extra_permissions           JSON NULL,
  revoked_permissions         JSON NULL,
  KEY idx_email (email),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE inventory_materials (
  id                VARCHAR(50) PRIMARY KEY,
  name              VARCHAR(255) NOT NULL,
  sku               VARCHAR(80) NULL,
  unit              VARCHAR(32) NOT NULL DEFAULT 'pcs',
  quantity_on_hand  DECIMAL(12,2) NOT NULL DEFAULT 0,
  reorder_level     DECIMAL(12,2) NOT NULL DEFAULT 0,
  supplier          VARCHAR(255) NULL,
  notes             TEXT NULL,
  created_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_material_name (name),
  KEY idx_material_sku (sku)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE products (
  id                VARCHAR(50) PRIMARY KEY,
  name              VARCHAR(255) NOT NULL,
  description       TEXT NULL,
  price             DECIMAL(10,2) NOT NULL,
  category          VARCHAR(100) NOT NULL,
  style             VARCHAR(100) NOT NULL,
  material          VARCHAR(100) NOT NULL,
  color             VARCHAR(100) NOT NULL,
  size              VARCHAR(50) NOT NULL,
  model_path        VARCHAR(500) NOT NULL,
  real_width_m      DECIMAL(6,3) NULL,
  real_height_m     DECIMAL(6,3) NULL,
  real_depth_m      DECIMAL(6,3) NULL,
  model_base_scale  DECIMAL(5,2) NOT NULL DEFAULT 1.00,
  cover_image_url   VARCHAR(500) NULL,
  image_urls        JSON NULL,
  components_json   JSON NULL,
  rating            DECIMAL(3,2) DEFAULT 0.00,
  review_count      INT DEFAULT 0,
  inventory_qty     INT DEFAULT 0,
  is_popular        TINYINT(1) DEFAULT 0,
  is_new_arrival    TINYINT(1) DEFAULT 0,
  in_stock          TINYINT(1) DEFAULT 1,
  is_archived       TINYINT(1) NOT NULL DEFAULT 0,
  created_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_products_category (category),
  KEY idx_products_style (style),
  KEY idx_products_is_popular (is_popular),
  KEY idx_products_is_new_arrival (is_new_arrival),
  KEY idx_products_in_stock (in_stock),
  KEY idx_products_is_archived (is_archived),
  KEY idx_products_category_popular (category, is_popular),
  KEY idx_products_new_arrival_created (is_new_arrival, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE product_variants (
  id                VARCHAR(50) PRIMARY KEY,
  product_id        VARCHAR(50) NOT NULL,
  name              VARCHAR(255) NOT NULL,
  dimensions_label  VARCHAR(255) NULL,
  price_adjustment  DECIMAL(10,2) NOT NULL DEFAULT 0,
  is_default        TINYINT(1) NOT NULL DEFAULT 0,
  created_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_variant_product (product_id),
  CONSTRAINT fk_variant_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE product_variant_bom_lines (
  id                    VARCHAR(50) PRIMARY KEY,
  variant_id            VARCHAR(50) NOT NULL,
  inventory_material_id VARCHAR(50) NOT NULL,
  quantity_required     DECIMAL(12,4) NOT NULL,
  created_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_variant_material (variant_id, inventory_material_id),
  KEY idx_bom_variant (variant_id),
  KEY idx_bom_material (inventory_material_id),
  CONSTRAINT fk_bom_variant FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE,
  CONSTRAINT fk_bom_material FOREIGN KEY (inventory_material_id) REFERENCES inventory_materials(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE faqs (
  id          VARCHAR(50) PRIMARY KEY,
  question    VARCHAR(500) NOT NULL,
  answer      TEXT NOT NULL,
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_faq_sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_addresses (
  id            VARCHAR(50) PRIMARY KEY,
  user_id       VARCHAR(50) NOT NULL,
  full_name     VARCHAR(150) NOT NULL,
  phone_number  VARCHAR(32) NOT NULL,
  region        VARCHAR(255) NOT NULL,
  postal_code   VARCHAR(20) NULL,
  street        VARCHAR(255) NOT NULL,
  label         ENUM('Home','Work','Other') DEFAULT 'Home',
  is_default    TINYINT(1) DEFAULT 0,
  created_at    TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_addresses_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_user_addresses_user (user_id),
  KEY idx_user_addresses_default (is_default)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE orders (
  id                                  VARCHAR(50) PRIMARY KEY,
  user_id                             VARCHAR(50) NOT NULL,
  contact_name                        VARCHAR(150) NOT NULL,
  contact_phone                       VARCHAR(32) NOT NULL,
  shipping_label                      VARCHAR(20) NULL,
  shipping_line1                      VARCHAR(255) NOT NULL,
  shipping_line2                      VARCHAR(255) NULL,
  shipping_region                     VARCHAR(255) NOT NULL,
  shipping_postal                     VARCHAR(20) NULL,
  subtotal_amount                     DECIMAL(10,2) NOT NULL,
  shipping_fee                        DECIMAL(10,2) NOT NULL,
  total_amount                        DECIMAL(10,2) NOT NULL,
  downpayment_amount                  DECIMAL(10,2) DEFAULT 0.00,
  remaining_balance                   DECIMAL(10,2) DEFAULT 0.00,
  status                              ENUM(
                                        'pending',
                                        'pending_payment_verification',
                                        'confirmed',
                                        'shipped',
                                        'delivered',
                                        'cancelled',
                                        'refunded',
                                        'expired'
                                      ) DEFAULT 'pending',
  payment_method                      ENUM('card','paypal','cod','gcash','paymongo') NOT NULL,
  payment_plan                        VARCHAR(32) NULL DEFAULT NULL,
  payment_status                      ENUM(
                                        'pending',
                                        'completed',
                                        'failed',
                                        'refunded',
                                        'downpayment_received'
                                      ) DEFAULT 'pending',
  payment_proof_url                   VARCHAR(500) NULL,
  valid_id_proof_url                  VARCHAR(1024) NULL DEFAULT NULL,
  last_paymongo_event_id              VARCHAR(191) NULL DEFAULT NULL,
  first_installment_paid_at           DATETIME NULL DEFAULT NULL,
  order_option                        VARCHAR(32) NULL DEFAULT NULL,
  estimated_delivery_at               DATETIME NULL DEFAULT NULL,
  materials_deducted_at               TIMESTAMP NULL DEFAULT NULL,
  cancellation_reason                 VARCHAR(120) NULL DEFAULT NULL,
  payment_default_cancelled_at        TIMESTAMP NULL DEFAULT NULL,
  late_fee_accrued_days               INT NOT NULL DEFAULT 0,
  late_fee_last_email_sent_on         DATE NULL DEFAULT NULL,
  payment_default_warn_2m_sent_at     TIMESTAMP NULL DEFAULT NULL,
  payment_default_warn_80d_sent_at    TIMESTAMP NULL DEFAULT NULL,
  payment_default_warn_90d_sent_at    TIMESTAMP NULL DEFAULT NULL,
  terms_version_accepted_at_order     INT NULL DEFAULT NULL,
  checkout_reminder_sent_at           TIMESTAMP NULL DEFAULT NULL,
  created_at                          TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                          TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_orders_user (user_id),
  KEY idx_orders_status (status),
  KEY idx_orders_created (created_at),
  KEY idx_orders_user_status (user_id, status),
  KEY idx_orders_payment_status (payment_status),
  KEY idx_orders_last_paymongo_event_id (last_paymongo_event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE product_media (
  id          VARCHAR(50) PRIMARY KEY,
  product_id  VARCHAR(50) NOT NULL,
  media_url   VARCHAR(500) NOT NULL,
  sort_order  TINYINT UNSIGNED DEFAULT 0,
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_product_media_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
  KEY idx_product_media_product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE wishlist_items (
  user_id     VARCHAR(50) NOT NULL,
  product_id  VARCHAR(50) NOT NULL,
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE cart_items (
  id          VARCHAR(50) PRIMARY KEY,
  user_id     VARCHAR(50) NOT NULL,
  product_id  VARCHAR(50) NOT NULL,
  quantity    INT NOT NULL DEFAULT 1,
  unit_price  DECIMAL(10,2) NOT NULL,
  notes       VARCHAR(255) NULL,
  added_at    TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_cart_items_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_cart_items_product FOREIGN KEY (product_id) REFERENCES products(id),
  KEY idx_cart_items_user (user_id),
  KEY idx_cart_items_product (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reviews (
  id            VARCHAR(50) PRIMARY KEY,
  product_id    VARCHAR(50) NOT NULL,
  product_name  VARCHAR(255) NOT NULL,
  user_id       VARCHAR(50) NOT NULL,
  user_name     VARCHAR(150) NOT NULL,
  rating        TINYINT NOT NULL,
  content       TEXT NULL,
  status        ENUM('pending','published','flagged','archived') NOT NULL DEFAULT 'published',
  created_at    TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_reviews_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
  CONSTRAINT fk_reviews_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT reviews_chk_1 CHECK (rating BETWEEN 1 AND 5),
  KEY idx_reviews_product (product_id),
  KEY idx_reviews_user (user_id),
  KEY idx_reviews_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE order_items (
  id            VARCHAR(50) PRIMARY KEY,
  order_id      VARCHAR(50) NOT NULL,
  product_id    VARCHAR(50) NOT NULL,
  variant_id    VARCHAR(50) NULL DEFAULT NULL,
  product_name  VARCHAR(255) NOT NULL,
  quantity      INT NOT NULL,
  unit_price    DECIMAL(10,2) NOT NULL,
  line_total    DECIMAL(10,2) NOT NULL,
  CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES products(id),
  KEY idx_order_items_order (order_id),
  KEY fk_order_items_product (product_id),
  KEY idx_order_items_variant (variant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE order_material_deductions (
  id                    VARCHAR(50) PRIMARY KEY,
  order_id              VARCHAR(50) NOT NULL,
  inventory_material_id VARCHAR(50) NOT NULL,
  quantity_deducted     DECIMAL(12,4) NOT NULL,
  created_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_order_material (order_id, inventory_material_id),
  KEY idx_omd_order (order_id),
  CONSTRAINT fk_omd_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_omd_material FOREIGN KEY (inventory_material_id) REFERENCES inventory_materials(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE order_status_history (
  id          VARCHAR(50) PRIMARY KEY,
  order_id    VARCHAR(50) NOT NULL,
  status      VARCHAR(30) NOT NULL,
  note        VARCHAR(255) NULL,
  created_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_status_history_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  KEY idx_status_history_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE app_settings (
  id           TINYINT NOT NULL PRIMARY KEY,
  payload_json LONGTEXT NOT NULL,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE made_to_order_requests (
  id                 VARCHAR(32) NOT NULL PRIMARY KEY,
  request_ref        VARCHAR(64) NOT NULL UNIQUE,
  user_id            VARCHAR(64) NOT NULL,
  user_name          VARCHAR(255) NOT NULL,
  item_name          VARCHAR(255) NOT NULL,
  preferred_size     VARCHAR(255) NULL,
  materials          VARCHAR(255) NULL,
  notes              TEXT NULL,
  down_payment_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
  valid_id_url       TEXT NULL,
  reference_urls_json JSON NULL,
  status             VARCHAR(32) NOT NULL DEFAULT 'pending_review',
  quoted_total       DECIMAL(12,2) NULL,
  quoted_downpayment DECIMAL(12,2) NULL,
  quoted_remaining   DECIMAL(12,2) NULL,
  admin_message      TEXT NULL,
  order_id           VARCHAR(50) NULL,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE order_payment_events (
  id                VARCHAR(64) PRIMARY KEY,
  order_id          VARCHAR(50) NOT NULL,
  event_type        VARCHAR(40) NOT NULL,
  amount            DECIMAL(12,2) NOT NULL,
  event_time        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paymongo_event_id VARCHAR(120) NULL,
  source            VARCHAR(30) NOT NULL DEFAULT 'paymongo',
  KEY idx_payment_events_order_time (order_id, event_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE order_late_fee_events (
  id          VARCHAR(64) PRIMARY KEY,
  order_id    VARCHAR(50) NOT NULL,
  fee_date    DATE NOT NULL,
  amount      DECIMAL(12,2) NOT NULL DEFAULT 100.00,
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_late_fee_order_date (order_id, fee_date),
  KEY idx_late_fee_events_order_date (order_id, fee_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE admin_activity_logs (
  id           VARCHAR(64) PRIMARY KEY,
  admin_id     VARCHAR(64) NULL,
  action       VARCHAR(80) NOT NULL,
  entity_type  VARCHAR(80) NOT NULL,
  entity_id    VARCHAR(80) NULL,
  details_json JSON NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_admin_activity_created (created_at),
  KEY idx_admin_activity_admin (admin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE legal_content (
  `key`       VARCHAR(50) PRIMARY KEY,
  content     LONGTEXT NULL,
  version     INT NOT NULL DEFAULT 1,
  updated_at  TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE legal_content_history (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  legal_key  VARCHAR(50) NOT NULL,
  version    INT NOT NULL,
  content    LONGTEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_legal_key_version (legal_key, version DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_notifications (
  id         VARCHAR(64) PRIMARY KEY,
  user_id    VARCHAR(64) NOT NULL,
  type       VARCHAR(64) NOT NULL,
  title      VARCHAR(255) NOT NULL,
  body       TEXT NOT NULL,
  data_json  JSON NULL,
  is_read    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_notifications_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_user_notifications_user_created (user_id, created_at),
  KEY idx_user_notifications_user_read (user_id, is_read)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE user_device_tokens (
  id         VARCHAR(64) PRIMARY KEY,
  user_id    VARCHAR(64) NOT NULL,
  token      VARCHAR(512) NOT NULL UNIQUE,
  platform   VARCHAR(32) NOT NULL DEFAULT 'unknown',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_device_tokens_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  KEY idx_user_device_tokens_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE support_conversations (
  id                         VARCHAR(50) PRIMARY KEY,
  user_id                    VARCHAR(50) NOT NULL,
  status                     ENUM('open','closed') NOT NULL DEFAULT 'open',
  created_at                 TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                 TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_message_at            TIMESTAMP NULL,
  last_message_preview       VARCHAR(255) NULL,
  last_message_sender_type   ENUM('user','admin') NULL,
  CONSTRAINT fk_support_conv_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE KEY uniq_support_user (user_id),
  KEY idx_support_status (status),
  KEY idx_support_last_message (last_message_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE support_messages (
  id                    VARCHAR(50) PRIMARY KEY,
  conversation_id       VARCHAR(50) NOT NULL,
  sender_type           ENUM('user','admin') NOT NULL,
  sender_user_id        VARCHAR(50) NULL,
  sender_admin_id       VARCHAR(50) NULL,
  body                  TEXT NOT NULL,
  attachment_url        VARCHAR(500) NULL,
  attachment_type       ENUM('image','file') NULL,
  attachment_mime       VARCHAR(255) NULL,
  attachment_filename   VARCHAR(255) NULL,
  created_at            TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_support_msg_conv FOREIGN KEY (conversation_id) REFERENCES support_conversations(id) ON DELETE CASCADE,
  CONSTRAINT fk_support_msg_user FOREIGN KEY (sender_user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_support_msg_admin FOREIGN KEY (sender_admin_id) REFERENCES admins(id) ON DELETE SET NULL,
  KEY idx_support_msg_conv_created (conversation_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE support_form_requests (
  id                  VARCHAR(50) PRIMARY KEY,
  conversation_id     VARCHAR(50) NOT NULL,
  user_id             VARCHAR(50) NOT NULL,
  form_type           VARCHAR(64) NOT NULL,
  status              ENUM('pending','submitted') NOT NULL DEFAULT 'pending',
  payload_json        JSON NULL,
  created_by_admin_id VARCHAR(50) NULL,
  created_at          TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  submitted_at        TIMESTAMP NULL,
  CONSTRAINT fk_sfr_conv FOREIGN KEY (conversation_id) REFERENCES support_conversations(id) ON DELETE CASCADE,
  CONSTRAINT fk_sfr_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_sfr_admin FOREIGN KEY (created_by_admin_id) REFERENCES admins(id) ON DELETE SET NULL,
  KEY idx_sfr_conversation (conversation_id),
  KEY idx_sfr_user (user_id),
  KEY idx_sfr_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

