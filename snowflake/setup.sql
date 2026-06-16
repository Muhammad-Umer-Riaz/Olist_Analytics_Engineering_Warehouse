-- =============================================================================
-- Olist ELT Warehouse — Snowflake Setup (Phase 1 / L2)
-- =============================================================================
-- Run this in a Snowsight worksheet while signed in with access to ACCOUNTADMIN.
--
-- The script switches roles on purpose so each object is created/managed by the
-- role that *should* own it (best-practice RBAC, not everything-as-ACCOUNTADMIN):
--   * SYSADMIN      -> owns infrastructure (warehouse, database, schemas)
--   * ACCOUNTADMIN  -> resource monitor (only ACCOUNTADMIN may create these)
--   * SECURITYADMIN -> roles, grants, and service users (inherits USERADMIN)
--
-- Idempotent where Snowflake allows (IF NOT EXISTS / OR REPLACE). Safe to re-run.
-- =============================================================================


-- =============================================================================
-- 1) INFRASTRUCTURE  — owned by SYSADMIN
-- =============================================================================
USE ROLE SYSADMIN;

-- Compute: smallest size; parks itself after 60s idle to conserve trial credits.
CREATE WAREHOUSE IF NOT EXISTS OLIST_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Olist ELT compute (dlt loads + dbt runs)';

-- Database + the four ELT layers as schemas.
CREATE DATABASE IF NOT EXISTS OLIST
    COMMENT = 'Olist Brazilian e-commerce analytics warehouse';

CREATE SCHEMA IF NOT EXISTS OLIST.RAW
    COMMENT = 'Landing zone — dlt writes here (1:1 with source CSVs + FX rates)';
CREATE SCHEMA IF NOT EXISTS OLIST.STAGING
    COMMENT = 'dbt staging — cleaned 1:1 views';
CREATE SCHEMA IF NOT EXISTS OLIST.INTERMEDIATE
    COMMENT = 'dbt intermediate — business logic';
CREATE SCHEMA IF NOT EXISTS OLIST.MARTS
    COMMENT = 'dbt marts — star schema (facts + dims)';


-- =============================================================================
-- 2) COST BACKSTOP  — resource monitor (ACCOUNTADMIN only)
--    Caps OLIST_WH at 30 credits/month: notify at 75/90%, then suspend.
-- =============================================================================
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE RESOURCE MONITOR OLIST_WH_MONITOR
    WITH
        CREDIT_QUOTA    = 30
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75  PERCENT DO NOTIFY
        ON 90  PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE OLIST_WH SET RESOURCE_MONITOR = OLIST_WH_MONITOR;


-- =============================================================================
-- 3) RBAC  — roles, grants, service users (SECURITYADMIN; inherits USERADMIN)
--    Two scoped roles + two key-pair SERVICE users = enforced least privilege.
-- =============================================================================
USE ROLE SECURITYADMIN;

-- ---- Functional roles ----
CREATE ROLE IF NOT EXISTS OLIST_LOADER
    COMMENT = 'dlt service role — writes RAW only';
CREATE ROLE IF NOT EXISTS OLIST_TRANSFORMER
    COMMENT = 'dbt service role — reads RAW, writes STAGING/INTERMEDIATE/MARTS';

-- Roll functional roles up to SYSADMIN (clean role hierarchy / visibility).
GRANT ROLE OLIST_LOADER      TO ROLE SYSADMIN;
GRANT ROLE OLIST_TRANSFORMER TO ROLE SYSADMIN;

-- ---- Warehouse + database usage (both roles) ----
GRANT USAGE ON WAREHOUSE OLIST_WH TO ROLE OLIST_LOADER;
GRANT USAGE ON WAREHOUSE OLIST_WH TO ROLE OLIST_TRANSFORMER;
GRANT USAGE ON DATABASE  OLIST    TO ROLE OLIST_LOADER;
GRANT USAGE ON DATABASE  OLIST    TO ROLE OLIST_TRANSFORMER;

-- ---- LOADER: write RAW; create its own merge-staging schema (dlt -> RAW_STAGING) ----
GRANT USAGE                     ON SCHEMA   OLIST.RAW TO ROLE OLIST_LOADER;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA   OLIST.RAW TO ROLE OLIST_LOADER;
GRANT CREATE SCHEMA             ON DATABASE OLIST     TO ROLE OLIST_LOADER;

-- ---- TRANSFORMER: read RAW (existing + future objects) ----
GRANT USAGE  ON SCHEMA OLIST.RAW TO ROLE OLIST_TRANSFORMER;
GRANT SELECT ON ALL    TABLES IN SCHEMA OLIST.RAW TO ROLE OLIST_TRANSFORMER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA OLIST.RAW TO ROLE OLIST_TRANSFORMER;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA OLIST.RAW TO ROLE OLIST_TRANSFORMER;

-- ---- TRANSFORMER: write its three layers ----
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA OLIST.STAGING      TO ROLE OLIST_TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA OLIST.INTERMEDIATE TO ROLE OLIST_TRANSFORMER;
GRANT USAGE, CREATE TABLE, CREATE VIEW ON SCHEMA OLIST.MARTS        TO ROLE OLIST_TRANSFORMER;

-- ---- Service users (TYPE = SERVICE => key-pair auth only; cannot use a password) ----
-- RSA public keys below are NOT secret; the matching private keys live in .keys/ (gitignored).
CREATE USER IF NOT EXISTS OLIST_LOADER_SVC
    TYPE              = SERVICE
    DEFAULT_ROLE      = OLIST_LOADER
    DEFAULT_WAREHOUSE = OLIST_WH
    RSA_PUBLIC_KEY    = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw05QKNPhukzBF+j5um1iGInvwKZGChXds5MENDE3fzpHxCXV3O5dpLhAulcg5Cj6bOKAVKLXiPpXINkzvrmMvQ5q/4jh/D3VGwH/ZAx6riwIJfqacHjQrP2Zmpr1aNij5pdg3Xpa6wc/66dNFicvVKjDzhQJ785FupjZSNi8K+ZmR0MrACNF/uV/7SZH2n6taKX+84GBu/uIRhV2u41nnFRGu9MP0Ef+vXrkAe2XMvkWaYQnoLeiXcTDMFIWz6dplPbRRk3wCIukELjw1uPbQRvY79nIzzjMd9JfFCKmFr7aUNljf/PIWBN0itOJs3a5B9GOYU8dFzE+w2uAZNja/QIDAQAB'
    COMMENT           = 'Service user for dlt extract-load (role OLIST_LOADER)';
GRANT ROLE OLIST_LOADER TO USER OLIST_LOADER_SVC;

CREATE USER IF NOT EXISTS OLIST_TRANSFORMER_SVC
    TYPE              = SERVICE
    DEFAULT_ROLE      = OLIST_TRANSFORMER
    DEFAULT_WAREHOUSE = OLIST_WH
    RSA_PUBLIC_KEY    = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv/H6piPOyDjVezrexuGHSRshfK+S06JVUHIY7P+YkSVzlCJVqK2kCqALCbG0JtnIwIT0hUBeD3DZsY4IVWdZYmgewvfif5KQ0p4KH5i5ohDU7d5L+nUvPQk09H3ag+zefOunFxFh2UiJVfedoBD4uywYt8uurl4hrEGJaRr38omM80DyLsa2PLGaaJaK1bw3rKDgektRGM9RBdeI/uGI0yLDBiou6M+jKW1ZWHCvC6OfjNcou8Wlkzy7RDDdFHIXJDGqqFa0m7PTTMGVK/v91Lt4TNTte69kFBhPYAql0zhEuLlKPX4jAPOW/Ooc5lEVGB85fTPOzBiSDpAi4fz6mQIDAQAB'
    COMMENT           = 'Service user for dbt transform (role OLIST_TRANSFORMER)';
GRANT ROLE OLIST_TRANSFORMER TO USER OLIST_TRANSFORMER_SVC;


-- =============================================================================
-- 4) SANITY CHECKS (optional — run individually after the above)
-- =============================================================================
-- SHOW WAREHOUSES        LIKE 'OLIST_WH';
-- SHOW DATABASES         LIKE 'OLIST';
-- SHOW SCHEMAS IN DATABASE OLIST;
-- SHOW ROLES             LIKE 'OLIST_%';
-- SHOW USERS             LIKE 'OLIST_%_SVC';
-- SHOW RESOURCE MONITORS LIKE 'OLIST_WH_MONITOR';
-- SHOW GRANTS TO ROLE OLIST_LOADER;
-- SHOW GRANTS TO ROLE OLIST_TRANSFORMER;
