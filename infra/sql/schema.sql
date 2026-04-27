-- Azure SQL Database schema for PurchaseSample
-- Converted from SampleData.sql for Azure SQL Database compatibility
-- Run this script against the PurchaseSampleDb database after provisioning with main.bicep

-- ============================================================
-- Schema
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dbo')
    EXEC('CREATE SCHEMA dbo');

-- Customers table
IF OBJECT_ID('dbo.Customers', 'U') IS NOT NULL
    DROP TABLE dbo.Customers;

CREATE TABLE dbo.Customers (
    CustomerId   INT           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    CustomerName VARCHAR(50)   NOT NULL,
    Visits       INT           NOT NULL DEFAULT 0
);

-- Products table
IF OBJECT_ID('dbo.Products', 'U') IS NOT NULL
    DROP TABLE dbo.Products;

CREATE TABLE dbo.Products (
    ProductId              INT             NOT NULL IDENTITY(1,1) PRIMARY KEY,
    ProductName            VARCHAR(50)     NOT NULL,
    Availability           INT             NOT NULL DEFAULT 0,
    Price                  DECIMAL(18, 2)  NOT NULL DEFAULT 0,
    MaxDiscountPercentage  DECIMAL(5, 2)   NOT NULL DEFAULT 0
);

-- ============================================================
-- Seed data (matches original SampleData.sql)
-- ============================================================
SET IDENTITY_INSERT dbo.Customers ON;
INSERT INTO dbo.Customers (CustomerId, CustomerName, Visits) VALUES (1, 'Customer1', 10);
INSERT INTO dbo.Customers (CustomerId, CustomerName, Visits) VALUES (2, 'Customer2', 5);
INSERT INTO dbo.Customers (CustomerId, CustomerName, Visits) VALUES (3, 'Customer3', 7);
SET IDENTITY_INSERT dbo.Customers OFF;

SET IDENTITY_INSERT dbo.Products ON;
INSERT INTO dbo.Products (ProductId, ProductName, Availability, Price, MaxDiscountPercentage) VALUES (1, 'Product1', 250, 10.00, 3.00);
INSERT INTO dbo.Products (ProductId, ProductName, Availability, Price, MaxDiscountPercentage) VALUES (2, 'Product2', 300, 2.00, 10.00);
INSERT INTO dbo.Products (ProductId, ProductName, Availability, Price, MaxDiscountPercentage) VALUES (3, 'Product3', 450, 5.00, 12.00);
SET IDENTITY_INSERT dbo.Products OFF;

-- ============================================================
-- Verify
-- ============================================================
SELECT * FROM dbo.Customers;
SELECT * FROM dbo.Products;
