-- =============================================================================
-- sample_data.sql — MySQL sample data for ecommerce_db
-- =============================================================================
-- Creates database, tables: customers (500 rows), orders (2000 rows).
-- Includes indexes, foreign keys, and realistic-looking data.
-- Safe to re-run: drops tables first (database and data recreated).
-- Requires MySQL 8.0+ (uses recursive CTE for row generation).
-- =============================================================================

SET NAMES utf8mb4;
SET SESSION cte_max_recursion_depth = 10000;
SET FOREIGN_KEY_CHECKS = 0;

-- -----------------------------------------------------------------------------
-- Database
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS ecommerce_db
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE ecommerce_db;

-- -----------------------------------------------------------------------------
-- Drop tables (orders first due to FK)
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

-- =============================================================================
-- Table: customers
-- =============================================================================
CREATE TABLE customers (
  customer_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
  first_name      VARCHAR(50)  NOT NULL,
  last_name       VARCHAR(50)  NOT NULL,
  email           VARCHAR(100) NOT NULL,
  registration_date DATE       NOT NULL,
  country         VARCHAR(50)  NOT NULL,
  status          ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
  total_purchases INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (customer_id),
  UNIQUE KEY uk_customers_email (email),
  KEY ix_customers_country (country),
  KEY ix_customers_status (status),
  KEY ix_customers_registration_date (registration_date),
  KEY ix_customers_name (last_name, first_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Table: orders
-- =============================================================================
CREATE TABLE orders (
  order_id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id     INT UNSIGNED NOT NULL,
  order_date      DATE         NOT NULL,
  product_name    VARCHAR(100) NOT NULL,
  category        VARCHAR(50)  NOT NULL,
  amount          DECIMAL(10,2) NOT NULL,
  status          ENUM('PENDING', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
  shipping_country VARCHAR(50) NOT NULL,
  PRIMARY KEY (order_id),
  KEY ix_orders_customer_id (customer_id),
  KEY ix_orders_order_date (order_date),
  KEY ix_orders_status (status),
  KEY ix_orders_category (category),
  KEY ix_orders_shipping_country (shipping_country),
  CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- Insert 500 customers (realistic names, emails, dates, countries, status)
-- =============================================================================
INSERT INTO customers (first_name, last_name, email, registration_date, country, status, total_purchases)
WITH RECURSIVE n (i) AS (
  SELECT 1
  UNION ALL
  SELECT i + 1 FROM n WHERE i < 500
)
SELECT
  ELT(1 + MOD(n.i, 40),
    'James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda',
    'William','Elizabeth','David','Barbara','Richard','Susan','Joseph','Jessica',
    'Thomas','Sarah','Charles','Karen','Christopher','Lisa','Daniel','Nancy',
    'Matthew','Betty','Anthony','Margaret','Mark','Sandra','Donald','Ashley',
    'Steven','Kimberly','Paul','Emily','Andrew','Donna','Joshua','Michelle'
  ),
  ELT(1 + MOD(n.i, 40),
    'Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis',
    'Rodriguez','Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas',
    'Taylor','Moore','Jackson','Martin','Lee','Perez','Thompson','White',
    'Harris','Sanchez','Clark','Ramirez','Lewis','Robinson','Walker','Young',
    'Allen','King','Wright','Scott','Torres','Nguyen','Hill','Flores','Green'
  ),
  CONCAT('customer', n.i, '@example.com'),
  DATE_SUB(CURDATE(), INTERVAL FLOOR(RAND(n.i) * 1095) DAY),
  ELT(1 + MOD(n.i, 15),
    'USA','UK','Germany','France','Canada','Australia','Japan','India',
    'Brazil','Spain','Italy','Netherlands','Mexico','South Korea','China'
  ),
  ELT(1 + MOD(n.i, 10),
    'ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','ACTIVE','INACTIVE','SUSPENDED'
  ),
  FLOOR(1 + RAND(n.i + 500) * 80)
FROM n;

-- =============================================================================
-- Insert 2000 orders (spread across customers, realistic products/dates/amounts)
-- =============================================================================
INSERT INTO orders (customer_id, order_date, product_name, category, amount, status, shipping_country)
WITH RECURSIVE n (i) AS (
  SELECT 1
  UNION ALL
  SELECT i + 1 FROM n WHERE n.i < 2000
)
SELECT
  1 + MOD(n.i - 1, 500),
  DATE_SUB(CURDATE(), INTERVAL FLOOR(RAND(n.i) * 730) DAY),
  ELT(1 + MOD(n.i, 30),
    'Wireless Mouse','USB-C Hub','Laptop Stand','Mechanical Keyboard','Monitor 27"',
    'Webcam HD','SSD 512GB','Bluetooth Headphones','Desk Lamp','Office Chair',
    'Notebook Set','Coffee Maker','Water Bottle','Backpack','Phone Case',
    'Tablet Stand','Cable Organizer','Desk Mat','Whiteboard','Sticky Notes',
    'Printer Paper','Stapler','Scissors','Pen Pack','Highlighters','Notebook',
    'Binder','File Folders','Calculator','Desk Organizer'
  ),
  ELT(1 + MOD(n.i, 8),
    'Electronics','Furniture','Accessories','Stationery','Home',
    'Office','Electronics','Clothing'
  ),
  ROUND(9.99 + RAND(n.i + 1000) * 240.00, 2),
  ELT(1 + MOD(n.i, 20),
    'DELIVERED','DELIVERED','DELIVERED','SHIPPED','DELIVERED','PROCESSING','PENDING','DELIVERED',
    'SHIPPED','DELIVERED','CANCELLED','DELIVERED','SHIPPED','DELIVERED','DELIVERED',
    'PENDING','DELIVERED','SHIPPED','DELIVERED','PROCESSING'
  ),
  ELT(1 + MOD(n.i, 15),
    'USA','UK','Germany','France','Canada','Australia','Japan','India',
    'Brazil','Spain','Italy','Netherlands','Mexico','South Korea','China'
  )
FROM n;

SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
-- Optional: verify row counts
-- -----------------------------------------------------------------------------
-- SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers
-- UNION ALL
-- SELECT 'orders', COUNT(*) FROM orders;
