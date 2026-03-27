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
INSERT INTO `admins` VALUES ('a17645385444171919','dahonogrusseljae@gmail.com','$2b$10$36T30DNEka74iz3PjOQE6.2llK2YjRPtBRCkKsDynxSV.8hqq6.5u','Russel Jae Dahonog','2025-11-30 21:35:44','2026-03-27 09:13:03','2026-03-27 09:13:04');
/*!40000 ALTER TABLE `admins` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `app_settings`
--

DROP TABLE IF EXISTS `app_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_settings` (
  `id` tinyint NOT NULL,
  `payload_json` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_settings`
--

LOCK TABLES `app_settings` WRITE;
/*!40000 ALTER TABLE `app_settings` DISABLE KEYS */;
/*!40000 ALTER TABLE `app_settings` ENABLE KEYS */;
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
INSERT INTO `cart_items` VALUES ('cart17650030790214340','u17650027217026634','p17642148937441720',1,500.00,NULL,'2025-12-06 06:37:59','2025-12-06 06:37:59'),('cart17650047025854631','u17650045541267600','p17642148937441720',9,500.00,NULL,'2025-12-06 07:05:02','2025-12-06 08:28:10'),('cart17651395610551659','u17649649796857307','p17642135349348501',4,2500.00,NULL,'2025-12-07 20:32:41','2026-03-17 09:29:56'),('cart17652123803367513','u17649649796857307','p3',1,449.99,NULL,'2025-12-08 16:46:20','2025-12-08 16:46:20'),('cart17684101228389774','u17683991987559294','p2',2,599.99,NULL,'2026-01-14 17:02:02','2026-01-14 17:07:36'),('cart17684580457769457','u17649649796857307','p1',1,15000.00,NULL,'2026-01-15 06:20:45','2026-01-15 06:20:45'),('cart17735993740574840','u17649649796857307','p2',2,15000.00,NULL,'2026-03-15 18:29:34','2026-03-17 09:50:25'),('cart17737397317649373','u17649649796857307','p17642148937441720',1,11000.00,NULL,'2026-03-17 09:28:51','2026-03-17 09:28:51'),('cart17739027169266136','u17739017783860308','p17642148937441720',1,11000.00,NULL,'2026-03-19 06:45:16','2026-03-19 06:45:16'),('cart17739028121156834','u17739017783860308','p2',1,15000.00,NULL,'2026-03-19 06:46:52','2026-03-19 06:46:52'),('cart17742133506300058','u17737701586320542','p1',2,15000.00,NULL,'2026-03-22 21:02:30','2026-03-22 21:02:42'),('cart17743530076030002','u17737701586320542','p17742811115828142',3,45000.00,NULL,'2026-03-24 11:50:07','2026-03-26 16:23:56');
/*!40000 ALTER TABLE `cart_items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `faqs`
--

DROP TABLE IF EXISTS `faqs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `faqs` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `question` varchar(500) COLLATE utf8mb4_unicode_ci NOT NULL,
  `answer` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `sort_order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_faq_sort` (`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `faqs`
--

LOCK TABLES `faqs` WRITE;
/*!40000 ALTER TABLE `faqs` DISABLE KEYS */;
/*!40000 ALTER TABLE `faqs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `legal_content`
--

DROP TABLE IF EXISTS `legal_content`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `legal_content` (
  `key` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `content` longtext COLLATE utf8mb4_unicode_ci,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `legal_content`
--

LOCK TABLES `legal_content` WRITE;
/*!40000 ALTER TABLE `legal_content` DISABLE KEYS */;
/*!40000 ALTER TABLE `legal_content` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `made_to_order_requests`
--

DROP TABLE IF EXISTS `made_to_order_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `made_to_order_requests` (
  `id` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL,
  `request_ref` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` varchar(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `item_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `preferred_size` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `materials` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_ci,
  `down_payment_amount` decimal(12,2) NOT NULL DEFAULT '0.00',
  `valid_id_url` text COLLATE utf8mb4_unicode_ci,
  `reference_urls_json` json DEFAULT NULL,
  `status` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'pending_payment',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `quoted_total` decimal(12,2) DEFAULT NULL,
  `quoted_downpayment` decimal(12,2) DEFAULT NULL,
  `quoted_remaining` decimal(12,2) DEFAULT NULL,
  `admin_message` text COLLATE utf8mb4_unicode_ci,
  `order_id` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `request_ref` (`request_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `made_to_order_requests`
--

LOCK TABLES `made_to_order_requests` WRITE;
/*!40000 ALTER TABLE `made_to_order_requests` DISABLE KEYS */;
INSERT INTO `made_to_order_requests` VALUES ('mto_1774410723223','mto_1774410722388','u17737701586320542','Russel Jae Dahonogs','dwadaw','180 cm x 190 cm x 120 cm','good','dwadawda',3000.00,'/uploads/made-to-order/mto_1774410722388/mto_1774410723278.jpg',NULL,'quoted','2026-03-25 03:52:03','2026-03-26 07:23:37',40000.00,3000.00,37000.00,'wdawd',NULL),('mto_1774509592682_4t47j1yw','mto_1774509592682_4t47j1yw','u17737701586320542','Russel Jae Dahonogs','dwadaw','dwadaw','wada','dwad',0.00,'/uploads/made-to-order/mto_1774509592682_4t47j1yw/mto_1774509592745.jpg',NULL,'declined','2026-03-26 07:19:52','2026-03-26 15:06:47',NULL,NULL,NULL,NULL,NULL);
/*!40000 ALTER TABLE `made_to_order_requests` ENABLE KEYS */;
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
INSERT INTO `order_items` VALUES ('oi17650216492422040','o17650216491585003','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17650250873717283','o17650250873567300','p2','Wooden Dining Table',1,599.99,599.99),('oi17650401593947546','o17650401593828570','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17650912278984974','o17650912278882497','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17650912279046592','o17650912278882497','p17642135349348501','Wooden Drawer',1,500.00,500.00),('oi17651369130386533','o17651369130272977','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17652208173023673','o17652208172922017','p1','Glass Dining Table',1,299.99,299.99),('oi17652268461031380','o17652268460912123','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17652601811820029','o17652601811724402','p1','Glass Dining Table',1,299.99,299.99),('oi17652781253781204','o17652781253522758','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17652781253878404','o17652781253522758','p1','Glass Dining Table',1,299.99,299.99),('oi17683988422009549','o17683988421938705','p17642135349348501','Wooden Drawer',1,500.00,500.00),('oi17683989018998790','o17683989018945339','p17642135349348501','Wooden Drawer',1,500.00,500.00),('oi17684003867958892','o17684003867766772','p17642148937441720','Loft Bed',1,500.00,500.00),('oi17684577542810583','o17684577542745611','p1','Glass Dining Table',1,15000.00,15000.00),('oi17684593366932124','o17684593366870334','p17642148937441720','Loft Bed',1,11000.00,11000.00),('oi17735990395341969','o17735990395184221','p2','Wooden Dining Table',1,15000.00,15000.00),('oi17739022681128837','o17739022680965369','p2','Wooden Dining Table',1,15000.00,15000.00),('oi17740332065435973','o17740332065345394','p2','Wooden Dining Table',1,15000.00,15000.00),('oi17742016891951930','o17742016891173214','p17738821198855137','Wooden Sideboard',1,9500.00,9500.00),('oi17742024988512857','o17742024988405658','p17738821198855137','Wooden Sideboard',1,9500.00,9500.00),('oi17742028014043831','o17742028013905107','p17738821198855137','Wooden Sideboard',1,9500.00,9500.00),('oi17742083948928733','o17742083948375852','p2','Wooden Dining Table',1,15000.00,15000.00),('oi17742131864950538','o17742131864774953','p17738821198855137','Wooden Sideboard',1,9500.00,9500.00),('oi17742154380751120','o17742154380662871','p17642148937441720','Loft Bed',1,11000.00,11000.00),('oi17742563064123710','o17742563063641455','p1','Glass Dining Table',1,15000.00,15000.00),('oi17742563064166837','o17742563063641455','p2','Wooden Dining Table',1,15000.00,15000.00),('oi17742563064269652','o17742563063641455','p17738821198855137','Wooden Sideboard',1,9500.00,9500.00),('oi17743308105002226','o17743308102983660','p17742809491213043','Bunk Bed',1,50000.00,50000.00),('oi17743776567399360','o17743776566991111','p17738821198855137','Wooden Sideboard',1,9500.00,9500.00),('oi17743776567455319','o17743776566991111','p2','Wooden Dining Table',1,15000.00,15000.00),('oi17745340055659001','o17745340054981529','p17642135349348501','Wooden Drawer',1,1.00,1.00),('oi17745349686470951','o17745349686357005','p17742802634297877','Wooden Mosaic Lounge',1,1.00,1.00),('oi17745349686514538','o17745349686357005','p17738821198855137','Wooden Sideboard',1,1.00,1.00),('oi17745349686536078','o17745349686357005','p17642135349348501','Wooden Drawer',1,1.00,1.00),('oi17745352273101602','o17745352273008680','p17742805905185679','Narra Living Room Set',1,35000.00,35000.00);
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
  `payment_method` enum('card','paypal','cod','gcash','paymongo') COLLATE utf8mb4_unicode_ci NOT NULL,
  `payment_plan` varchar(32) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'full | downpayment',
  `payment_status` enum('pending','completed','failed','refunded','downpayment_received') COLLATE utf8mb4_unicode_ci DEFAULT 'pending',
  `payment_proof_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `valid_id_proof_url` varchar(1024) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `first_installment_paid_at` datetime DEFAULT NULL COMMENT 'When first PayMongo tranche (down payment) was recorded; 3-month policy window starts here',
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
INSERT INTO `orders` VALUES ('o17650216491585003','u17649649796857307','Rhianna Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling Street','','Buruanga','4102',1000.00,4600.00,5600.00,1120.00,4480.00,'cancelled','cod',NULL,'pending',NULL,NULL,'2025-12-06 11:47:29','2025-12-06 12:17:29',NULL),('o17650250873567300','u17649649796857307','Rhianna Dahonog','08985928923','Home','Blk 1, Lot 65, Waling-Waling Street','','Buruanga','4102',599.99,4600.00,5199.99,1040.00,4159.99,'cancelled','cod',NULL,'failed',NULL,NULL,'2025-12-06 12:44:47','2025-12-06 13:15:00',NULL),('o17650401593828570','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',500.00,4000.00,4500.00,0.00,0.00,'confirmed','gcash',NULL,'pending',NULL,NULL,'2025-12-06 16:55:59','2025-12-06 17:35:45',NULL),('o17650912278882497','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',4500.00,4000.00,8500.00,0.00,0.00,'cancelled','gcash',NULL,'failed',NULL,NULL,'2025-12-07 07:07:07','2025-12-07 07:40:00',NULL),('o17651369130272977','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Batan','4102',500.00,4000.00,4500.00,0.00,0.00,'cancelled','gcash',NULL,'pending',NULL,NULL,'2025-12-07 19:48:33','2025-12-07 20:07:10',NULL),('o17652208172922017','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',299.99,4000.00,4299.99,860.00,3439.99,'cancelled','cod',NULL,'failed',NULL,NULL,'2025-12-08 19:06:57','2025-12-09 06:01:34',NULL),('o17652268460912123','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Jovellar','4102',500.00,4600.00,5100.00,0.00,0.00,'expired','gcash',NULL,'failed','/uploads/payment-proofs/o17652268460912123/proof_o1765226_1765260114184.png',NULL,'2025-12-08 20:47:26','2025-12-09 06:05:00',NULL),('o17652601811724402','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Culasi','4102',299.99,4200.00,4499.99,0.00,0.00,'confirmed','gcash',NULL,'pending','/uploads/payment-proofs/o17652601811724402/proof_o1765260_1765260188100.png',NULL,'2025-12-09 06:03:01','2025-12-09 06:06:48',NULL),('o17652781253522758','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',1099.98,4000.00,5099.98,0.00,0.00,'expired','gcash',NULL,'failed',NULL,NULL,'2025-12-09 11:02:05','2026-03-15 18:28:42',NULL),('o17683988421938705','u17650027217026634','Russel Jae Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling St., Molino VII, Bacoor City, Cavite','','New Corella','4102',1000.00,5000.00,6000.00,0.00,0.00,'expired','gcash',NULL,'failed',NULL,NULL,'2026-01-14 13:54:02','2026-01-14 14:25:00',NULL),('o17683989018945339','u17650027217026634','Russel Jae Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling St., Molino VII, Bacoor City, Cavite','','New Corella','4102',500.00,5000.00,5500.00,0.00,0.00,'expired','gcash',NULL,'failed',NULL,NULL,'2026-01-14 13:55:01','2026-01-14 14:30:00',NULL),('o17684003867766772','u17683991987559294','Reshie Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling Street','','Bacoor','4102',500.00,1800.00,2300.00,0.00,0.00,'expired','gcash',NULL,'failed',NULL,NULL,'2026-01-14 14:19:46','2026-01-14 14:50:00',NULL),('o17684577542745611','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',45000.00,4000.00,49000.00,0.00,0.00,'cancelled','gcash',NULL,'pending',NULL,NULL,'2026-01-15 06:15:54','2026-01-15 06:33:27',NULL),('o17684593366870334','u17683991987559294','Reshie Dahonog','09692353537','Home','Blk 1, Lot 65, Waling-Waling Street','','Bacoor','4102',11000.00,1800.00,12800.00,0.00,0.00,'confirmed','gcash',NULL,'pending',NULL,NULL,'2026-01-15 06:42:16','2026-01-15 06:43:14',NULL),('o17735990395184221','u17649649796857307','Rhianna Dahonog','09692353536','Home','BLk 1, Lot 65, Waling-Waling Street','','Flora','4102',15000.00,4000.00,19000.00,0.00,0.00,'expired','gcash',NULL,'failed',NULL,NULL,'2026-03-15 18:23:59','2026-03-15 18:55:00',NULL),('o17739022680965369','u17739017783860308','Neil Orca','09692353537','Home','656, Santero St.','','Bacoor','4102',15000.00,1800.00,16800.00,0.00,0.00,'expired','gcash',NULL,'failed','/uploads/payment-proofs/o17739022680965369/proof_o1773902_1773902298784.png',NULL,'2026-03-19 06:37:48','2026-03-19 07:10:00',NULL),('o17740332065345394','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Bacoor','4102',15000.00,1800.00,16800.00,0.00,0.00,'expired','gcash',NULL,'failed',NULL,NULL,'2026-03-20 19:00:06','2026-03-20 19:45:00',NULL),('o17742016891173214','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','San Juan','4102',9500.00,4600.00,14100.00,0.00,0.00,'expired','paymongo',NULL,'failed',NULL,NULL,'2026-03-22 17:48:09','2026-03-22 18:20:00',NULL),('o17742024988405658','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Casiguran','4102',9500.00,4800.00,14300.00,0.00,0.00,'expired','paymongo',NULL,'failed',NULL,NULL,'2026-03-22 18:01:38','2026-03-22 18:35:00',NULL),('o17742028013905107','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Dilasag','4102',9500.00,4400.00,13900.00,0.00,0.00,'confirmed','paymongo',NULL,'pending',NULL,NULL,'2026-03-22 18:06:41','2026-03-22 18:09:29',NULL),('o17742083948375852','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Bucay','4102',15000.00,4000.00,19000.00,0.00,0.00,'expired','paymongo',NULL,'failed',NULL,NULL,'2026-03-22 19:39:54','2026-03-22 20:10:00',NULL),('o17742131864774953','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Itbayat','4102',9500.00,4400.00,13900.00,3000.00,10900.00,'pending','paymongo','downpayment','failed',NULL,'/uploads/valid-ids/o17742131864774953/valid_id_o1774213_1774213186591.jpg','2026-03-22 20:59:46','2026-03-22 22:04:48',NULL),('o17742154380662871','u17737701586320542','dd','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Dilasag','4102',11000.00,4400.00,15400.00,3500.00,11900.00,'pending','paymongo','downpayment','failed',NULL,'/uploads/valid-ids/o17742154380662871/valid_id_o1774215_1774215438189.jpg','2026-03-22 21:37:18','2026-03-23 11:10:39',NULL),('o17742563063641455','u17742552437203851','wdaw','231231321321','Home','Waling Street','','Casiguran','123',54500.00,0.00,54500.00,3000.00,51500.00,'expired','paymongo','downpayment','failed',NULL,'/uploads/valid-ids/o17742563063641455/valid_id_o1774256_1774256306561.jpg','2026-03-23 08:58:26','2026-03-23 09:30:00',NULL),('o17743308102983660','u17737701586320542','Russel Jae Dahonogs','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Conner','4102',50000.00,4200.00,54200.00,54200.00,0.00,'pending','paymongo','full','pending',NULL,'/uploads/valid-ids/o17743308102983660/valid_id_o1774330_1774330810837.jpg','2026-03-24 05:40:10','2026-03-24 05:40:10',NULL),('o17743776566991111','u17737701586320542','Russel Jae Dahonogs','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Bacoor','4102',49000.00,1800.00,50800.00,50800.00,0.00,'pending','paymongo','full','pending',NULL,'/uploads/valid-ids/o17743776566991111/valid_id_o1774377_1774377656895.png','2026-03-24 18:40:56','2026-03-24 18:40:56',NULL),('o17745340054981529','u17737701586320542','Russel Jae Dahonogs','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Bacoor','4102',4.00,1800.00,1804.00,1804.00,0.00,'cancelled','paymongo','full','pending',NULL,'/uploads/valid-ids/o17745340054981529/valid_id_o1774534_1774534005671.jpg','2026-03-26 14:06:45','2026-03-26 14:18:00',NULL),('o17745349686357005','u17737701586320542','Russel Jae Dahonogs','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Bacoor','4102',3.00,0.00,3.00,3.00,0.00,'cancelled','paymongo','full','failed',NULL,'/uploads/valid-ids/o17745349686357005/valid_id_o1774534_1774534968742.jpg','2026-03-26 14:22:48','2026-03-26 14:26:34',NULL),('o17745352273008680','u17737701586320542','Russel Jae Dahonogs','09692353537','Home','BLk 1, Lot 65, Walig-Waling St.','','Bacoor','4102',35000.00,1800.00,36800.00,36800.00,0.00,'pending','paymongo','full','pending',NULL,'/uploads/valid-ids/o17745352273008680/valid_id_o1774535_1774535227385.jpg','2026-03-26 14:27:07','2026-03-26 14:27:07',NULL);
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
  `is_archived` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_products_category` (`category`),
  KEY `idx_products_style` (`style`),
  KEY `idx_products_is_popular` (`is_popular`),
  KEY `idx_products_is_new_arrival` (`is_new_arrival`),
  KEY `idx_products_in_stock` (`in_stock`),
  KEY `idx_products_category_popular` (`category`,`is_popular`),
  KEY `idx_products_new_arrival_created` (`is_new_arrival`,`created_at`),
  KEY `idx_products_is_archived` (`is_archived`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `products`
--

LOCK TABLES `products` WRITE;
/*!40000 ALTER TABLE `products` DISABLE KEYS */;
INSERT INTO `products` VALUES ('p1','Glass Top Dining Table','Elegant glass dining table',15000.00,'Dining','Modern','Wood','Brown','L','assets/glasss_dining_table.glb',3.000,1.000,2.000,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p1/565946497_3275584819261272_7034598972774518515_n_1768449986655.jpg\", \"http://192.168.43.213:4000/uploads/images/p1/566619713_582179541619410_8088151979157715824_n_1768449986887.jpg\"]',4.50,128,2,1,0,1,'2025-11-24 15:24:44','2026-03-23 15:53:44',0),('p17642135349348501','Wooden Drawer','Solid Drawer',1.00,'Outdoor','Modern','Wooden','Brown','L','/uploads/models/p17642135349348501/wooden_drawer_1774533851669.glb',1.200,1.200,1.200,1.00,NULL,'[\"http://192.168.254.111:4000/uploads/images/p17642135349348501/cabinet_w_1774281310590.jpg\"]',0.00,0,5,1,0,1,'2025-11-27 03:18:54','2026-03-26 14:26:34',0),('p17642148937441720','Loft Bed','Comfy',11000.00,'Bedroom','Modern','Wooden','Black','L','/uploads/models/p17642148937441720/loft_bed_1774527431086.glb',2.020,1.820,1.950,1.00,NULL,'[\"http://192.168.254.111:4000/uploads/images/p17642148937441720/model__1__1774527617442.png\"]',0.00,0,1,0,1,1,'2025-11-27 03:41:33','2026-03-26 12:20:19',0),('p17738796743771649','__size_fix_test__','size fix',123.45,'Dining','Modern','Wood','Brown','','assets/chair.glb',NULL,NULL,NULL,1.00,NULL,'[]',0.00,0,2,0,0,1,'2026-03-19 00:21:14','2026-03-19 00:59:14',1),('p17738821198855137','Wooden Sideboard','Solid Wood',1.00,'Living Room','Traditional','Mahogany','Brown','','/uploads/models/p17738821198855137/wooden_sideboard_1774426219249.glb',1.500,0.350,0.450,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p17738821198855137/model__2__1774426265835.png\"]',0.00,0,3,0,0,1,'2026-03-19 01:01:59','2026-03-26 14:26:34',0),('p17742802634297877','Wooden Mosaic Lounge','Solid mosaic',1.00,'Living Room','Classic','Mahogany','Light Brown','','/uploads/models/p17742802634297877/Meshy_AI_Wooden_Lattice_Lounge_0323134110_texture_1774426160565.glb',1.100,1.100,1.100,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p17742802634297877/diningset_w_1774426188742.jpg\"]',0.00,0,2,0,0,1,'2026-03-23 15:37:43','2026-03-26 14:26:34',0),('p17742805905185679','Narra Living Room Set','Solid',35000.00,'Living Room','Traditional','Mahogany','Brown','','/uploads/models/p17742805905185679/Meshy_AI_Parquet_Inlay_Wood_Li_0323131640_texture_1774426082928.glb',1.100,1.100,1.100,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p17742805905185679/Narra_Mosaic_Living_Room_Set_1774426130273.jpg\"]',0.00,0,3,0,0,1,'2026-03-23 15:43:10','2026-03-26 14:27:07',0),('p17742807405204937','L-Shaped Dark Wooden Lounge Set','Solid',25000.00,'Living Room','Traditional','Mahogany','Dark Brown','','/uploads/models/p17742807405204937/Meshy_AI_L_Shaped_Wooden_Corne_0323133101_texture_1774426004187.glb',1.100,1.100,1.100,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p17742807405204937/table_set_123_1774426053098.jpg\"]',0.00,0,2,0,0,1,'2026-03-23 15:45:40','2026-03-25 08:07:35',0),('p17742809491213043','Bunk Bed','Clean and Neat',50000.00,'Bedroom','Modern','Acacia','Gray','','/uploads/models/p17742809491213043/bunk_bed_3d_model4_1774527411854.glb',1.100,1.100,1.100,1.00,NULL,'[\"http://192.168.254.111:4000/uploads/images/p17742809491213043/Screenshot_2026-03-23_234829_1774527525586.png\"]',0.00,0,0,0,0,0,'2026-03-23 15:49:09','2026-03-26 12:18:46',0),('p17742811115828142','Wooden Bunk Bed','Solid',45000.00,'Bedroom','Minimal','Acacia','Light Brown','','/uploads/models/p17742811115828142/wooden_bunk_bed_3d_model__1__1774527402076.glb',1.100,1.100,1.100,1.00,NULL,'[\"http://192.168.254.111:4000/uploads/images/p17742811115828142/loftbed3_w_1774527483143.jpg\"]',0.00,0,1,0,0,1,'2026-03-23 15:51:51','2026-03-26 12:18:04',0),('p2','Wooden Dining Table','Premium wooden dining table with ergonomic design',15000.00,'Dining','Classic','Wooden','Brown','L','/uploads/models/p2/wooden_dining_table_double_1773885059820.glb',1.219,0.762,0.914,1.00,NULL,'[\"http://192.168.43.213:4000/uploads/images/p2/564911436_3928322060635429_5295924244856851721_n__1__1768449962237.jpg\", \"http://192.168.43.213:4000/uploads/images/p2/564911436_3928322060635429_5295924244856851721_n_1768449962317.jpg\"]',4.80,89,2,1,0,1,'2025-11-24 15:24:44','2026-03-24 18:40:56',0),('p3','Minimalist Lounge Chair','Simple yet elegant chair perfect for living rooms',2000.00,'Living Room','Minimal','Fabric','Light Brown','M','assets/chair.glb',NULL,NULL,NULL,1.00,NULL,'[]',4.30,67,5,0,1,1,'2025-11-24 15:24:44','2026-03-17 11:12:25',1);
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
INSERT INTO `reviews` VALUES ('r17684014244004451','p17642148937441720','Loft Bed','u17683991987559294','Reshie Dahonog',5,'Good Products','published','2026-01-14 14:37:04','2026-01-14 14:37:04'),('r17684110349539491','p17642148937441720','Loft Bed','u17649649796857307','Rhianna Dahonog',5,'Excellent Product','published','2026-01-14 17:17:14','2026-01-14 17:17:14'),('r17736618177910826','p17642135349348501','Wooden Drawer','u17649649796857307','Rhianna Dahonog',5,'dwadawdawdawdaw','published','2026-03-16 11:50:17','2026-03-16 11:50:17'),('r17739086211756997','p2','Wooden Dining Table','u17739017783860308','Neil Orca',5,'5 star review ......','published','2026-03-19 08:23:41','2026-03-19 08:23:41'),('r17740332427681705','p2','Wooden Dining Table','u17737701586320542','Russel Jae Dahonogs',5,'dwadwwadwawdawdawdaw','published','2026-03-20 19:00:42','2026-03-20 19:00:42');
/*!40000 ALTER TABLE `reviews` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `support_conversations`
--

DROP TABLE IF EXISTS `support_conversations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `support_conversations` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `user_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `status` enum('open','closed') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_message_at` timestamp NULL DEFAULT NULL,
  `last_message_preview` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `last_message_sender_type` enum('user','admin') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_support_user` (`user_id`),
  KEY `idx_support_status` (`status`),
  KEY `idx_support_last_message` (`last_message_at`),
  CONSTRAINT `fk_support_conv_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `support_conversations`
--

LOCK TABLES `support_conversations` WRITE;
/*!40000 ALTER TABLE `support_conversations` DISABLE KEYS */;
INSERT INTO `support_conversations` VALUES ('sc17736778576464229','u17649649796857307','open','2026-03-16 16:17:37','2026-03-17 09:05:31','2026-03-17 09:05:31','bruh',NULL),('sc17737709119430339','u17737701586320542','open','2026-03-17 18:08:31','2026-03-19 09:02:41','2026-03-19 09:02:41','hi','user'),('sc17739023161947305','u17739017783860308','open','2026-03-19 06:38:36','2026-03-19 06:44:26','2026-03-19 06:44:26','hshsh','user'),('sc17742556001804381','u17742552437203851','open','2026-03-23 08:46:40','2026-03-23 09:03:34','2026-03-23 09:03:34',':)','user');
/*!40000 ALTER TABLE `support_conversations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `support_messages`
--

DROP TABLE IF EXISTS `support_messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `support_messages` (
  `id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `conversation_id` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL,
  `sender_type` enum('user','admin') COLLATE utf8mb4_unicode_ci NOT NULL,
  `sender_user_id` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `sender_admin_id` varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `body` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `attachment_url` varchar(500) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `attachment_type` enum('image','file') COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `attachment_mime` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `attachment_filename` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_support_msg_user` (`sender_user_id`),
  KEY `fk_support_msg_admin` (`sender_admin_id`),
  KEY `idx_support_msg_conv_created` (`conversation_id`,`created_at`),
  CONSTRAINT `fk_support_msg_admin` FOREIGN KEY (`sender_admin_id`) REFERENCES `admins` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_support_msg_conv` FOREIGN KEY (`conversation_id`) REFERENCES `support_conversations` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_support_msg_user` FOREIGN KEY (`sender_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `support_messages`
--

LOCK TABLES `support_messages` WRITE;
/*!40000 ALTER TABLE `support_messages` DISABLE KEYS */;
INSERT INTO `support_messages` VALUES ('sm17736778660071120','sc17736778576464229','user','u17649649796857307',NULL,'hello','2026-03-16 16:17:46',NULL,NULL,NULL,NULL),('sm17736779122844139','sc17736778576464229','admin',NULL,'a17645385444171919','hi','2026-03-16 16:18:32',NULL,NULL,NULL,NULL),('sm17737383317546666','sc17736778576464229','admin',NULL,'a17645385444171919','bruh','2026-03-17 09:05:31',NULL,NULL,NULL,NULL),('sm17738143335346775','sc17737709119430339','user','u17737701586320542',NULL,'hello','2026-03-18 06:12:13',NULL,NULL,NULL,NULL),('sm17739023360048971','sc17739023161947305','user','u17739017783860308',NULL,'hi','2026-03-19 06:38:56',NULL,NULL,NULL,NULL),('sm17739026166747874','sc17739023161947305','user','u17739017783860308',NULL,'hey','2026-03-19 06:43:36',NULL,NULL,NULL,NULL),('sm17739026605208529','sc17739023161947305','admin',NULL,'a17645385444171919','hello, how can i help you?','2026-03-19 06:44:20',NULL,NULL,NULL,NULL),('sm17739026668159092','sc17739023161947305','user','u17739017783860308',NULL,'hshsh','2026-03-19 06:44:26',NULL,NULL,NULL,NULL),('sm17739109618199609','sc17737709119430339','user','u17737701586320542',NULL,'hi','2026-03-19 09:02:41',NULL,NULL,NULL,NULL),('sm17742565854164745','sc17742556001804381','user','u17742552437203851',NULL,'hello po','2026-03-23 09:03:05',NULL,NULL,NULL,NULL),('sm17742566143842002','sc17742556001804381','user','u17742552437203851',NULL,':)','2026-03-23 09:03:34',NULL,NULL,NULL,NULL);
/*!40000 ALTER TABLE `support_messages` ENABLE KEYS */;
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
INSERT INTO `user_addresses` VALUES ('addr17650401337524829','u17649649796857307','Rhianna Dahonog','09692353536','Apayao, Flora, Malubibit Norte','4102','BLk 1, Lot 65, Waling-Waling Street','Home',1,'2025-12-06 16:55:33','2025-12-06 16:55:33'),('addr17683987853662429','u17650027217026634','Russel Jae Dahonog','09692353537','Davao Del Norte, New Corella, El Salvador','4102','Blk 1, Lot 65, Waling-Waling St., Molino VII, Bacoor City, Cavite','Home',1,'2026-01-14 13:53:05','2026-01-14 13:53:05'),('addr17684003733507195','u17683991987559294','Reshie Dahonog','09692353537','Cavite, Bacoor, Molino VII','4102','Blk 1, Lot 65, Waling-Waling Street','Home',1,'2026-01-14 14:19:33','2026-01-14 14:19:33'),('addr17738143209827599','u17737701586320542','dd','09692353537','Cavite, Bacoor, Molino VII','4102','BLk 1, Lot 65, Walig-Waling St.','Home',1,'2026-03-18 06:12:00','2026-03-18 06:12:00'),('addr17742560769976981','u17742552437203851','iyib','09089068824','Nueva Ecija, Carranglan, D. L. Maglanoc Pob. (Bgy.III)','1744','Jasmine Street, 123 Blk','Home',0,'2026-03-23 08:54:37','2026-03-23 08:56:13'),('addr17742561263587983','u17742552437203851','wdaw','231231321321','Aurora, Casiguran, Barangay 5 (Pob.)','123','Waling Street','Home',1,'2026-03-23 08:55:26','2026-03-23 08:56:13');
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
INSERT INTO `users` VALUES ('u17649649796857307','yamadayohan25@gmail.com',NULL,'Rhianna Dahonog','rhiannadahonog','female','2008-05-25','http://192.168.254.104:4000/uploads/avatars/avatar17652210605476815.jpg',NULL,'2025-12-05 20:03:00','2025-12-08 19:11:14','2025-12-05 20:03:00',1,NULL,NULL,NULL),('u17650027217026634','dahonogrusseljae@gmail.com',NULL,'Russel Jae Dahonog','russeljaedahonog',NULL,NULL,NULL,NULL,'2025-12-06 06:32:02','2025-12-06 06:32:54','2025-12-06 06:32:02',1,NULL,NULL,NULL),('u17650045541267600','neroooo27@gmail.com',NULL,'Jae Jae','jaejae',NULL,NULL,NULL,NULL,'2025-12-06 07:02:34','2025-12-06 07:03:41','2025-12-06 07:02:34',1,NULL,NULL,NULL),('u17650922355938756','ysahsindoval@gmail.com',NULL,'Sha Sha','shasha',NULL,NULL,NULL,NULL,'2025-12-07 07:23:56','2025-12-07 07:24:38','2025-12-07 07:23:56',1,NULL,NULL,NULL),('u17683991987559294','coreenzein21@gmail.com',NULL,'Reshie Dahonog','reshiedahonog',NULL,NULL,NULL,NULL,'2026-01-14 13:59:59','2026-01-14 14:00:40','2026-01-14 13:59:59',1,NULL,NULL,NULL),('u17684596967422014','mikaela.arciaga@gmail.com',NULL,'Mikay Arciaga','mikayarciaga',NULL,NULL,NULL,NULL,'2026-01-15 06:48:17','2026-01-15 06:48:46','2026-01-15 06:48:17',1,NULL,NULL,NULL),('u17736745964062127','bbeauny22@gmail.com',NULL,'Bea Bigay','beabigay',NULL,NULL,NULL,NULL,'2026-03-16 15:23:16','2026-03-16 15:24:34','2026-03-16 15:23:16',1,NULL,NULL,NULL),('u17737701586320542','dahonogmuzan@gmail.com','$2b$10$IS1i0VHrRV/JmhpODNYvzu76s4aUzqeQouTsrfH.9P0IljGcVITGK','Russel Jae Dahonogs','russeljaedahonogs','other','2004-09-27','http://192.168.254.111:4000/uploads/avatars/avatar17743608396373774.jpg','09692353537','2026-03-17 17:55:59','2026-03-27 08:53:00','2026-03-27 08:53:00',1,NULL,NULL,NULL),('u17739017783860308','orcaneil9@gmail.com','$2b$10$Hx/VURp/hznrfBnYUbbsc.hSGuctrqu2OZOPPWIuxI4iFkE.o.z.u','Neil Orca','neilorca',NULL,NULL,NULL,NULL,'2026-03-19 06:29:38','2026-03-19 06:30:21','2026-03-19 06:30:21',1,NULL,NULL,NULL),('u17742552437203851','adriensabangan.hs@gmail.com','$2b$10$M3wJHer.jW.zl15hGFC.e.RZ.R8wTXDX11NXVR/61GAjV2CdkSh/6','AC Sabañgan','aaclzs','female','2003-08-16',NULL,'09089068824','2026-03-23 08:40:44','2026-03-23 08:45:48','2026-03-23 08:45:48',1,NULL,NULL,NULL);
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

-- Dump completed on 2026-03-27 18:45:08
