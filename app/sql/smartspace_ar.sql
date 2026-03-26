-- MySQL dump 10.13  Distrib 8.0.44, for Win64 (x86_64)
--
-- Host: 127.0.0.1    Database: smartspace_ar
-- ------------------------------------------------------
-- Server version	8.0.44

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `admins`
--

DROP TABLE IF EXISTS `admins`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `admins` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `full_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_login_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `idx_email` (`email`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `admins`
--

LOCK TABLES `admins` WRITE;
/*!40000 ALTER TABLE `admins` DISABLE KEYS */;
INSERT INTO `admins` VALUES ('a17645385444171919','dahonogrusseljae@gmail.com','$2b$10$36T30DNEka74iz3PjOQE6.2llK2YjRPtBRCkKsDynxSV.8hqq6.5u','Russel Jae Dahonog','2025-11-30 21:35:44','2026-03-15 20:06:52','2026-03-15 20:06:53');
/*!40000 ALTER TABLE `admins` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `cart_items`
--

DROP TABLE IF EXISTS `cart_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cart_items` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `quantity` int NOT NULL DEFAULT '1',
  `unit_price` decimal(10,2) NOT NULL,
  `notes` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `added_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_cart_items_user` (`user_id`),
  KEY `idx_cart_items_product` (`product_id`),
  CONSTRAINT `fk_cart_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`),
  CONSTRAINT `fk_cart_items_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `cart_items`
--

LOCK TABLES `cart_items` WRITE;
/*!40000 ALTER TABLE `cart_items` DISABLE KEYS */;
INSERT INTO `cart_items` VALUES ('cart17650030790214340','u17650027217026634','p17642148937441720',1,500.00,NULL,'2025-12-06 06:37:59','2025-12-06 06:37:59'),('cart17650047025854631','u17650045541267600','p17642148937441720',9,500.00,NULL,'2025-12-06 07:05:02','2025-12-06 08:28:10'),('cart17651395610551659','u17649649796857307','p17642135349348501',2,500.00,NULL,'2025-12-07 20:32:41','2025-12-08 16:46:06'),('cart17652123803367513','u17649649796857307','p3',1,449.99,NULL,'2025-12-08 16:46:20','2025-12-08 16:46:20'),('cart17684101228389774','u17683991987559294','p2',2,599.99,NULL,'2026-01-14 17:02:02','2026-01-14 17:07:36'),('cart17684580457769457','u17649649796857307','p1',1,15000.00,NULL,'2026-01-15 06:20:45','2026-01-15 06:20:45'),('cart17735993740574840','u17649649796857307','p2',1,15000.00,NULL,'2026-03-15 18:29:34','2026-03-15 18:29:34'),('cart17736618437118291','u17649649796857307','p17642148937441720',1,11000.00,NULL,'2026-03-16 11:50:43','2026-03-16 11:50:43');
/*!40000 ALTER TABLE `cart_items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Temporary view structure for view `order_feed_vw`
--

DROP TABLE IF EXISTS `order_feed_vw`;
/*!50001 DROP VIEW IF EXISTS `order_feed_vw`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `order_feed_vw` AS SELECT 
 1 AS `id`,
 1 AS `user_id`,
 1 AS `user_name`,
 1 AS `product_ids`,
 1 AS `total_amount`,
 1 AS `status`,
 1 AS `shipping_address`,
 1 AS `created_at`,
 1 AS `updated_at`*/;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `order_items`
--

DROP TABLE IF EXISTS `order_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_items` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `order_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `quantity` int NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `line_total` decimal(10,2) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_order_items_product` (`product_id`),
  KEY `idx_order_items_order` (`order_id`),
  CONSTRAINT `fk_order_items_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_order_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `order_items`
--

LOCK TABLES `order_items` WRITE;
/*!40000 ALTER TABLE `order_items` DISABLE KEYS */;
INSERT INTO `order_items` VALUES ('oi17650216492422040','o17650216491585003','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17650250873717283','o17650250873567300','p2','Wooden Dining Table',1,599.99,599.99),('oi17650401593947546','o17650401593828570','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17650912278984974','o17650912278882497','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17650912279046592','o17650912278882497','p17642135349348501','Wooden Drawer',1,500.00,500.00),('oi17651369130386533','o17651369130272977','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17652208173023673','o17652208172922017','p1','Glass Dining Table',1,299.99,299.99),('oi17652268461031380','o17652268460912123','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17652601811820029','o17652601811724402','p1','Glass Dining Table',1,299.99,299.99),('oi17652781253781204','o17652781253522758','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17652781253878404','o17652781253522758','p1','Glass Dining Table',1,299.99,299.99),('oi17683988422009549','o17683988421938705','p17642135349348501','Wooden Drawer',1,500.00,500.00),('oi17683989018998790','o17683989018945339','p17642135349348501','Wooden Drawer',1,500.00,500.00),('oi17684003867958892','o17684003867766772','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17684577542810583','o17684577542745611','p1','Glass Dining Table',1,15000.00,15000.00),('oi17684593366932124','o17684593366870334','p17642148937441720','Loft Bed',1,11000.00,11000.00),('oi17735990395341969','o17735990395184221','p2','Wooden Dining Table',1,15000.00,15000.00);
/*!40000 ALTER TABLE `order_items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `order_status_history`
--

DROP TABLE IF EXISTS `order_status_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_status_history` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `order_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` varchar(30) COLLATE utf8mb4_unicode_ci NOT NULL,
  `note` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_status_history_order` (`order_id`),
  CONSTRAINT `fk_status_history_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `order_status_history`
--

LOCK TABLES `order_status_history` WRITE;
/*!40000 ALTER TABLE `order_status_history` DISABLE KEYS */;
/*!40000 ALTER TABLE `order_status_history` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orders`
--

DROP TABLE IF EXISTS `orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `orders` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contact_name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `contact_phone` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `shipping_label` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `shipping_line1` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `shipping_line2` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `shipping_region` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `shipping_postal` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `subtotal_amount` decimal(10,2) NOT NULL,
  `shipping_fee` decimal(10,2) NOT NULL,
  `total_amount` decimal(10,2) NOT NULL,
  `downpayment_amount` decimal(10,2) DEFAULT '0.00',
  `remaining_balance` decimal(10,2) DEFAULT '0.00',
  `status` enum('pending','pending_payment_verification','confirmed','shipped','delivered','cancelled','refunded','expired') COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  `payment_method` enum('card','paypal','cod','gcash') COLLATE utf8mb4_unicode_ci NOT NULL,
  `payment_status` enum('pending','completed','failed','refunded') COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  `payment_proof_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_orders_user` (`user_id`),
  KEY `idx_orders_status` (`status`),
  KEY `idx_orders_created` (`created_at`),
  KEY `idx_orders_user_status` (`user_id`,`status`),
  KEY `idx_orders_payment_status` (`payment_status`),
  CONSTRAINT `fk_orders_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `orders`
--

LOCK TABLES `orders` WRITE;
/*!40000 ALTER TABLE `orders` DISABLE KEYS */;
INSERT INTO `orders` VALUES ('o17650216491585003','u17649649796857307','Rhianna Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling Street','','Buruanga','4102',1000.00,4600.00,5600.00,1120.00,4480.00,'cancelled','cod','pending',NULL,'2025-12-06 11:47:29','2025-12-06 12:17:29'),('o17650250873567300','u17649649796857307','Rhianna Dahonog','08985928923','Home','Blk 1, Lot 65, Waling-Waling Street','','Buruanga','4102',599.99,4600.00,5199.99,1040.00,4159.99,'cancelled','cod','failed',NULL,'2025-12-06 12:44:47','2025-12-06 13:15:00'),('o17650401593828570','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',500.00,4000.00,4500.00,0.00,0.00,'confirmed','gcash','pending',NULL,'2025-12-06 16:55:59','2025-12-06 17:35:45'),('o17650912278882497','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',4500.00,4000.00,8500.00,0.00,0.00,'cancelled','gcash','failed',NULL,'2025-12-07 07:07:07','2025-12-07 07:40:00'),('o17651369130272977','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Batan','4102',500.00,4000.00,4500.00,0.00,0.00,'cancelled','gcash','pending',NULL,'2025-12-07 19:48:33','2025-12-07 20:07:10'),('o17652208172922017','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',299.99,4000.00,4299.99,860.00,3439.99,'cancelled','cod','failed',NULL,'2025-12-08 19:06:57','2025-12-09 06:01:34'),('o17652268460912123','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Jovellar','4102',500.00,4600.00,5100.00,0.00,0.00,'expired','gcash','failed','/uploads/payment-proofs/o17652268460912123/proof_o1765226_1765260114184.png','2025-12-08 20:47:26','2025-12-09 06:05:00'),('o17652601811724402','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Culasi','4102',299.99,4200.00,4499.99,0.00,0.00,'confirmed','gcash','pending','/uploads/payment-proofs/o17652601811724402/proof_o1765260_1765260188100.png','2025-12-09 06:03:01','2025-12-09 06:06:48'),('o17652781253522758','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',1099.98,4000.00,5099.98,0.00,0.00,'expired','gcash','failed',NULL,'2025-12-09 11:02:05','2026-03-15 18:28:42'),('o17683988421938705','u17650027217026634','Russel Jae Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling St., Molino VII, Bacoor City, Cavite','','New Corella','4102',1000.00,5000.00,6000.00,0.00,0.00,'expired','gcash','failed',NULL,'2026-01-14 13:54:02','2026-01-14 14:25:00'),('o17683989018945339','u17650027217026634','Russel Jae Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling St., Molino VII, Bacoor City, Cavite','','New Corella','4102',500.00,5000.00,5500.00,0.00,0.00,'expired','gcash','failed',NULL,'2026-01-14 13:55:01','2026-01-14 14:30:00'),('o17684003867766772','u17683991987559294','Reshie Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling Street','','Bacoor','4102',500.00,1800.00,2300.00,0.00,0.00,'expired','gcash','failed',NULL,'2026-01-14 14:19:46','2026-01-14 14:50:00'),('o17684577542745611','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',45000.00,4000.00,49000.00,0.00,0.00,'cancelled','gcash','pending',NULL,'2026-01-15 06:15:54','2026-01-15 06:33:27'),('o17684593366870334','u17683991987559294','Reshie Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling Street','','Bacoor','4102',11000.00,1800.00,12800.00,0.00,0.00,'confirmed','gcash','pending',NULL,'2026-01-15 06:42:16','2026-01-15 06:43:14'),('o17735990395184221','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',15000.00,4000.00,19000.00,0.00,0.00,'expired','gcash','failed',NULL,'2026-03-15 18:23:59','2026-03-15 18:55:00');
/*!40000 ALTER TABLE `orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `product_media`
--

DROP TABLE IF EXISTS `product_media`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `product_media` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `media_url` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `sort_order` tinyint unsigned DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_product_media_product` (`product_id`),
  CONSTRAINT `fk_product_media_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `product_media`
--

LOCK TABLES `product_media` WRITE;
/*!40000 ALTER TABLE `product_media` DISABLE KEYS */;
INSERT INTO `product_media` VALUES ('pm1','p1','https://cdn.smartspace.app/products/p1/hero.jpg',0,'2025-11-24 15:24:44'),('pm2','p1','https://cdn.smartspace.app/products/p1/detail.jpg',1,'2025-11-24 15:24:44'),('pm3','p2','https://cdn.smartspace.app/products/p2/hero.jpg',0,'2025-11-24 15:24:44');
/*!40000 ALTER TABLE `product_media` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `products`
--

DROP TABLE IF EXISTS `products`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `products` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_ci,
  `price` decimal(10,2) NOT NULL,
  `category` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `style` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `material` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `color` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `size` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `model_path` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `real_width_m` decimal(6,3) DEFAULT NULL,
  `real_height_m` decimal(6,3) DEFAULT NULL,
  `real_depth_m` decimal(6,3) DEFAULT NULL,
  `model_base_scale` decimal(5,2) NOT NULL DEFAULT '1.00',
  `cover_image_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `image_urls` json DEFAULT NULL,
  `rating` decimal(3,2) DEFAULT '0.00',
  `review_count` int DEFAULT '0',
  `inventory_qty` int DEFAULT '0',
  `is_popular` tinyint(1) DEFAULT '0',
  `is_new_arrival` tinyint(1) DEFAULT '0',
  `in_stock` tinyint(1) DEFAULT '1',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_products_category` (`category`),
  KEY `idx_products_style` (`style`),
  KEY `idx_products_is_popular` (`is_popular`),
  KEY `idx_products_is_new_arrival` (`is_new_arrival`),
  KEY `idx_products_in_stock` (`in_stock`),
  KEY `idx_products_category_popular` (`category`,`is_popular`),
  KEY `idx_products_new_arrival_created` (`is_new_arrival`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `products`
--

LOCK TABLES `products` WRITE;
/*!40000 ALTER TABLE `products` DISABLE KEYS */;
INSERT INTO `products` VALUES ('p1','Glass Dining Table','Elegant glass dining table',15000.00,'Dining','Modern','Wood','Brown','L','assets/glasss_dining_table.glb',3.000,1.000,2.000,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p1/565946497_3275584819261272_7034598972774518515_n_1768449986655.jpg\", \"http://192.168.43.213:4000/uploads/images/p1/566619713_582179541619410_8088151979157715824_n_1768449986887.jpg\"]',4.50,128,12,1,0,1,'2025-11-24 15:24:44','2026-01-15 04:06:28'),('p17642135349348501','Wooden Drawer','Fancy Drawer',2500.00,'Outdoor','Modern','Wooden','Brown','L','assets/wooden_drawer.glb',NULL,NULL,NULL,1.00,NULL,'[]',0.00,0,3,1,0,1,'2025-11-27 03:18:54','2026-01-15 05:47:02'),('p17642148937441720','Loft Bed','Comfy',11000.00,'Living Room','Modern','Wooden','Red','L','/uploads/models/p17642148937441720/loft_bed_double_1773594438732.glb',2.020,1.820,1.950,1.00,NULL,'[]',0.00,0,5,0,1,1,'2025-11-27 03:41:33','2026-03-15 17:07:25'),('p2','Wooden Dining Table','Premium wooden dining table with ergonomic design',15000.00,'Office','Classic','Wooden','Brown','L','/uploads/models/p2/wooden_dining_table_1773582635084.glb',1.219,0.762,0.914,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p2/564911436_3928322060635429_5295924244856851721_n__1__1768449962237.jpg\", \"http://192.168.43.213:4000/uploads/images/p2/564911436_3928322060635429_5295924244856851721_n_1768449962317.jpg\"]',4.80,89,8,1,0,1,'2025-11-24 15:24:44','2026-03-15 13:50:37'),('p3','Minimalist Lounge Chair','Simple yet elegant chair perfect for living rooms',2000.00,'Living Room','Minimal','Fabric','Light Brown','M','assets/chair.glb',NULL,NULL,NULL,1.00,NULL,'[]',4.30,67,5,0,1,1,'2025-11-24 15:24:44','2026-01-14 18:14:53');
/*!40000 ALTER TABLE `products` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `reviews`
--

DROP TABLE IF EXISTS `reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `reviews` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `rating` tinyint NOT NULL,
  `content` text COLLATE utf8mb4_unicode_ci,
  `status` enum('pending','published','flagged','archived') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'published',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_reviews_product` (`product_id`),
  KEY `idx_reviews_user` (`user_id`),
  KEY `idx_reviews_status` (`status`),
  CONSTRAINT `fk_reviews_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reviews_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `reviews_chk_1` CHECK ((`rating` between 1 and 5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `reviews`
--

LOCK TABLES `reviews` WRITE;
/*!40000 ALTER TABLE `reviews` DISABLE KEYS */;
INSERT INTO `reviews` VALUES ('r17684014244004451','p17642148937441720','Loft Bed','u17683991987559294','Reshie Dahonog',5,'Good Products','published','2026-01-14 14:37:04','2026-01-14 14:37:04'),('r17684110349539491','p17642148937441720','Loft Bed','u17649649796857307','Rhianna Dahonog',5,'Excellent Product','published','2026-01-14 17:17:14','2026-01-14 17:17:14'),('r17736618177910826','p17642135349348501','Wooden Drawer','u17649649796857307','Rhianna Dahonog',5,'dwadawdawdawdaw','published','2026-03-16 11:50:17','2026-03-16 11:50:17');
/*!40000 ALTER TABLE `reviews` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_addresses`
--

DROP TABLE IF EXISTS `user_addresses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_addresses` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `full_name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `phone_number` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `region` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `postal_code` varchar(20) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `street` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `label` enum('Home','Work','Other') COLLATE utf8mb4_unicode_ci DEFAULT 'Home',
  `is_default` tinyint(1) DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_addresses_user` (`user_id`),
  KEY `idx_user_addresses_default` (`is_default`),
  CONSTRAINT `fk_user_addresses_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_addresses`
--

LOCK TABLES `user_addresses` WRITE;
/*!40000 ALTER TABLE `user_addresses` DISABLE KEYS */;
INSERT INTO `user_addresses` VALUES ('addr17650401337524829','u17649649796857307','Rhianna Dahonog','09692353536','Apayao, Flora, Malubibit Norte','4102','BLk 1, Lot 65, Waling-Waling Street','Home',1,'2025-12-06 16:55:33','2025-12-06 16:55:33'),('addr17683987853662429','u17650027217026634','Russel Jae Dahonog','09692353537','Davao Del Norte, New Corella, El Salvador','4102','Blk 1, Lot 65, Waling-Waling St., Molino VII, Bacoor City, Cavite','Home',1,'2026-01-14 13:53:05','2026-01-14 13:53:05'),('addr17684003733507195','u17683991987559294','Reshie Dahonog','09692353537','Cavite, Bacoor, Molino VII','4102','Blk 1, Lot 65, Waling-Waling Street','Home',1,'2026-01-14 14:19:33','2026-01-14 14:19:33');
/*!40000 ALTER TABLE `user_addresses` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `full_name` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `username` varchar(80) COLLATE utf8mb4_unicode_ci NOT NULL,
  `gender` enum('male','female','other') COLLATE utf8mb4_unicode_ci DEFAULT 'other',
  `date_of_birth` date DEFAULT NULL,
  `avatar_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `phone_number` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_login_at` timestamp NULL DEFAULT NULL,
  `email_verified` tinyint(1) DEFAULT '0',
  `verification_token` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `verification_token_expires` timestamp NULL DEFAULT NULL,
  `verification_code` varchar(8) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  UNIQUE KEY `username` (`username`),
  KEY `idx_verification_token` (`verification_token`),
  KEY `idx_verification_code` (`verification_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES ('u17649649796857307','yamadayohan25@gmail.com',NULL,'Rhianna Dahonog','rhiannadahonog','female','2008-05-25','http://192.168.254.104:4000/uploads/avatars/avatar17652210605476815.jpg',NULL,'2025-12-05 20:03:00','2025-12-08 19:11:14','2025-12-05 20:03:00',1,NULL,NULL,NULL),('u17650027217026634','dahonogrusseljae@gmail.com',NULL,'Russel Jae Dahonog','russeljaedahonog',NULL,NULL,NULL,NULL,'2025-12-06 06:32:02','2025-12-06 06:32:54','2025-12-06 06:32:02',1,NULL,NULL,NULL),('u17650045541267600','neroooo27@gmail.com',NULL,'Jae Jae','jaejae',NULL,NULL,NULL,NULL,'2025-12-06 07:02:34','2025-12-06 07:03:41','2025-12-06 07:02:34',1,NULL,NULL,NULL),('u17650922355938756','ysahsindoval@gmail.com',NULL,'Sha Sha','shasha',NULL,NULL,NULL,NULL,'2025-12-07 07:23:56','2025-12-07 07:24:38','2025-12-07 07:23:56',1,NULL,NULL,NULL),('u17683991987559294','coreenzein21@gmail.com',NULL,'Reshie Dahonog','reshiedahonog',NULL,NULL,NULL,NULL,'2026-01-14 13:59:59','2026-01-14 14:00:40','2026-01-14 13:59:59',1,NULL,NULL,NULL),('u17684596967422014','mikaela.arciaga@gmail.com',NULL,'Mikay Arciaga','mikayarciaga',NULL,NULL,NULL,NULL,'2026-01-15 06:48:17','2026-01-15 06:48:46','2026-01-15 06:48:17',1,NULL,NULL,NULL);
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `wishlist_items`
--

DROP TABLE IF EXISTS `wishlist_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `wishlist_items` (
  `user_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `product_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`,`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `wishlist_items`
--

LOCK TABLES `wishlist_items` WRITE;
/*!40000 ALTER TABLE `wishlist_items` DISABLE KEYS */;
INSERT INTO `wishlist_items` VALUES ('u_demo','p1','2025-11-24 15:24:56'),('u_demo','p3','2025-11-24 15:24:56');
/*!40000 ALTER TABLE `wishlist_items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Final view structure for view `order_feed_vw`
--

/*!50001 DROP VIEW IF EXISTS `order_feed_vw`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 DEFINER=`root`@`localhost` SQL SECURITY DEFINER */
/*!50001 VIEW `order_feed_vw` AS select `o`.`id` AS `id`,`o`.`user_id` AS `user_id`,`u`.`full_name` AS `user_name`,ifnull(json_arrayagg(`oi`.`product_id`),json_array()) AS `product_ids`,`o`.`total_amount` AS `total_amount`,`o`.`status` AS `status`,json_object('name',`o`.`contact_name`,'phone',`o`.`contact_phone`,'label',coalesce(`o`.`shipping_label`,''),'line1',`o`.`shipping_line1`,'line2',coalesce(`o`.`shipping_line2`,''),'city',`o`.`shipping_region`,'postalCode',coalesce(`o`.`shipping_postal`,'')) AS `shipping_address`,`o`.`created_at` AS `created_at`,`o`.`updated_at` AS `updated_at` from ((`orders` `o` left join `users` `u` on((`u`.`id` = `o`.`user_id`))) left join `order_items` `oi` on((`oi`.`order_id` = `o`.`id`))) group by `o`.`id`,`o`.`user_id`,`u`.`full_name`,`o`.`total_amount`,`o`.`status`,`o`.`contact_name`,`o`.`contact_phone`,`o`.`shipping_label`,`o`.`shipping_line1`,`o`.`shipping_line2`,`o`.`shipping_region`,`o`.`shipping_postal`,`o`.`created_at`,`o`.`updated_at` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-03-16 22:01:11
