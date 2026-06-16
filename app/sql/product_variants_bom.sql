-- Product variants, BOM lines, and material deduction tracking for orders.
-- Run after inventory_materials and products exist.

CREATE TABLE IF NOT EXISTS product_variants (
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

CREATE TABLE IF NOT EXISTS product_variant_bom_lines (
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

ALTER TABLE order_items
  ADD COLUMN variant_id VARCHAR(50) NULL DEFAULT NULL AFTER product_id,
  ADD KEY idx_order_items_variant (variant_id);

ALTER TABLE orders
  ADD COLUMN materials_deducted_at TIMESTAMP NULL DEFAULT NULL
  COMMENT 'When raw materials were deducted for this order';

CREATE TABLE IF NOT EXISTS order_material_deductions (
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
