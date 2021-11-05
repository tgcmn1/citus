--
-- Testing ALTER TABLE on columnar tables.
--

CREATE SCHEMA columnar_alter;
SET search_path tO columnar_alter, public;

CREATE TABLE test_alter_table (a int, b int, c int) USING columnar;

WITH sample_data AS (VALUES
    (1, 2, 3),
    (4, 5, 6),
    (7, 8, 9)
)
INSERT INTO test_alter_table SELECT * FROM sample_data;

-- drop a column
ALTER TABLE test_alter_table DROP COLUMN a;

select
  version_major, version_minor, reserved_stripe_id, reserved_row_number
  from columnar_test_helpers.columnar_storage_info('test_alter_table');

-- test analyze
ANALYZE test_alter_table;

-- verify select queries run as expected
SELECT * FROM test_alter_table;
SELECT a FROM test_alter_table;
SELECT b FROM test_alter_table;

-- verify insert runs as expected
INSERT INTO test_alter_table (SELECT 3, 5, 8);
INSERT INTO test_alter_table (SELECT 5, 8);


-- add a column with no defaults
ALTER TABLE test_alter_table ADD COLUMN d int;
SELECT * FROM test_alter_table;
INSERT INTO test_alter_table (SELECT 3, 5, 8);
SELECT * FROM test_alter_table;

select
  version_major, version_minor, reserved_stripe_id, reserved_row_number
  from columnar_test_helpers.columnar_storage_info('test_alter_table');


-- add a fixed-length column with default value
ALTER TABLE test_alter_table ADD COLUMN e int default 3;
SELECT * from test_alter_table;
INSERT INTO test_alter_table (SELECT 1, 2, 4, 8);
SELECT * from test_alter_table;

select
  version_major, version_minor, reserved_stripe_id, reserved_row_number
  from columnar_test_helpers.columnar_storage_info('test_alter_table');


-- add a variable-length column with default value
ALTER TABLE test_alter_table ADD COLUMN f text DEFAULT 'TEXT ME';
SELECT * from test_alter_table;
INSERT INTO test_alter_table (SELECT 1, 2, 4, 8, 'ABCDEF');
SELECT * from test_alter_table;


-- drop couple of columns
ALTER TABLE test_alter_table DROP COLUMN c;
ALTER TABLE test_alter_table DROP COLUMN e;
ANALYZE test_alter_table;
SELECT * from test_alter_table;
SELECT count(*) from test_alter_table;
SELECT count(t.*) from test_alter_table t;


-- unsupported default values
ALTER TABLE test_alter_table ADD COLUMN g boolean DEFAULT isfinite(current_date);
ALTER TABLE test_alter_table ADD COLUMN h DATE DEFAULT current_date;
SELECT * FROM test_alter_table;
ALTER TABLE test_alter_table ALTER COLUMN g DROP DEFAULT;
SELECT * FROM test_alter_table;
ALTER TABLE test_alter_table ALTER COLUMN h DROP DEFAULT;
ANALYZE test_alter_table;
SELECT * FROM test_alter_table;

-- unsupported type change
ALTER TABLE test_alter_table ADD COLUMN i int;
ALTER TABLE test_alter_table ADD COLUMN j float;
ALTER TABLE test_alter_table ADD COLUMN k text;

-- this is valid type change
ALTER TABLE test_alter_table ALTER COLUMN i TYPE float;

-- this is not valid
ALTER TABLE test_alter_table ALTER COLUMN j TYPE int;

-- text / varchar conversion is valid both ways
ALTER TABLE test_alter_table ALTER COLUMN k TYPE varchar(20);
ALTER TABLE test_alter_table ALTER COLUMN k TYPE text;

-- rename column
ALTER TABLE test_alter_table RENAME COLUMN k TO k_renamed;

-- rename table
ALTER TABLE test_alter_table RENAME TO test_alter_table_renamed;

DROP TABLE test_alter_table_renamed;

-- https://github.com/citusdata/citus/issues/4602
create domain str_domain as text not null;
create table domain_test (a int, b int) using columnar;
insert into domain_test values (1, 2);
insert into domain_test values (1, 2);
-- the following should error out since the domain is not nullable
alter table domain_test add column c str_domain;
-- but this should succeed
alter table domain_test add column c str_domain DEFAULT 'x';
SELECT * FROM domain_test;

-- similar to "add column c str_domain DEFAULT 'x'", both were getting
-- stucked before fixing https://github.com/citusdata/citus/issues/5164
BEGIN;
  ALTER TABLE domain_test ADD COLUMN d INT DEFAULT random();
ROLLBACK;
BEGIN;
  ALTER TABLE domain_test ADD COLUMN d SERIAL;
  SELECT * FROM domain_test ORDER BY 1,2,3,4;
ROLLBACK;

set default_table_access_method TO 'columnar';
CREATE TABLE has_volatile AS
SELECT * FROM generate_series(1,10) id;
ALTER TABLE has_volatile ADD col4 int DEFAULT (random() * 10000)::int;
SELECT id, col4 < 10000 FROM has_volatile ORDER BY id;

-- https://github.com/citusdata/citus/issues/4601
CREATE TABLE itest13 (a int) using columnar;
INSERT INTO itest13 VALUES (1), (2), (3);
ALTER TABLE itest13 ADD COLUMN c int GENERATED BY DEFAULT AS IDENTITY;
SELECT * FROM itest13 ORDER BY a;

create table atacc1 (a int) using columnar;
insert into atacc1 values(1);
-- should error out. It previously crashed.
alter table atacc1
  add column b float8 not null default random(),
  add primary key(a);

-- Add a generate column with an expression value
create table test_gen_ex (x int) using columnar;
INSERT INTO test_gen_ex VALUES (1), (2), (3);
ALTER TABLE test_gen_ex ADD COLUMN y int generated always as (x+1) stored;
SELECT * FROM test_gen_ex;


-- check removing all columns while having some data to simulate
-- table with non-zero rows but zero-columns.
-- https://github.com/citusdata/citus/issues/4626
BEGIN;
create table local(y int);
insert into local values (1), (2);
alter table local drop column y;

CREATE TABLE zero_col_columnar (like local) USING COLUMNAR;
ALTER TABLE local RENAME TO local_xxxxx;
INSERT INTO zero_col_columnar SELECT * FROM local_xxxxx;
COMMIT;

SELECT * FROM zero_col_columnar;
SELECT count(*) FROM zero_col_columnar;
EXPLAIN (costs off, summary off) SELECT * FROM zero_col_columnar;

INSERT INTO zero_col_columnar DEFAULT VALUES;
INSERT INTO zero_col_columnar DEFAULT VALUES;
INSERT INTO zero_col_columnar DEFAULT VALUES;
SELECT * FROM zero_col_columnar;
SELECT count(*) FROM zero_col_columnar;
EXPLAIN (costs off, summary off) SELECT * FROM zero_col_columnar;

VACUUM VERBOSE zero_col_columnar;
ANALYZE zero_col_columnar;
VACUUM FULL zero_col_columnar;

SELECT * FROM zero_col_columnar;

TRUNCATE zero_col_columnar;

SELECT * FROM zero_col_columnar;

DROP TABLE zero_col_columnar;

CREATE TABLE zero_col_columnar(a int) USING columnar;
INSERT INTO zero_col_columnar SELECT i FROM generate_series(1, 5) i;
alter table zero_col_columnar drop column a;

SELECT * FROM zero_col_columnar;

INSERT INTO zero_col_columnar DEFAULT VALUES;
INSERT INTO zero_col_columnar DEFAULT VALUES;
INSERT INTO zero_col_columnar DEFAULT VALUES;

SELECT * FROM zero_col_columnar;

VACUUM VERBOSE zero_col_columnar;
ANALYZE zero_col_columnar;
VACUUM FULL zero_col_columnar;

SELECT * FROM zero_col_columnar;

-- Add constraints

-- Add a CHECK constraint
CREATE TABLE products (
    product_no integer,
    name text,
    price int CONSTRAINT price_constraint CHECK (price > 0)
) USING columnar;
-- first insert should fail
INSERT INTO products VALUES (1, 'bread', 0);
INSERT INTO products VALUES (1, 'bread', 10);
ALTER TABLE products ADD CONSTRAINT dummy_constraint CHECK (price > product_no);
-- first insert should fail
INSERT INTO products VALUES (2, 'shampoo', 1);
INSERT INTO products VALUES (2, 'shampoo', 20);
ALTER TABLE products DROP CONSTRAINT dummy_constraint;
INSERT INTO products VALUES (3, 'pen', 2);
SELECT * FROM products ORDER BY 1;

-- Add a UNIQUE constraint
CREATE TABLE products_unique (
    product_no integer UNIQUE,
    name text,
    price numeric
) USING columnar;
ALTER TABLE products ADD COLUMN store_id text UNIQUE;

-- Add a PRIMARY KEY constraint
CREATE TABLE products_primary (
    product_no integer PRIMARY KEY,
    name text,
    price numeric
) USING columnar;

BEGIN;
  ALTER TABLE products DROP COLUMN store_id;
  ALTER TABLE products ADD COLUMN store_id text PRIMARY KEY;
ROLLBACK;

-- Add an EXCLUSION constraint (should fail)
CREATE TABLE circles (
    c circle,
    EXCLUDE USING gist (c WITH &&)
) USING columnar;

-- Row level security
CREATE TABLE public.row_level_security_col (id int, pgUser CHARACTER VARYING) USING columnar;
CREATE USER user1;
CREATE USER user2;
INSERT INTO public.row_level_security_col VALUES (1, 'user1'), (2, 'user2');
GRANT SELECT, UPDATE, INSERT, DELETE ON public.row_level_security_col TO user1;
GRANT SELECT, UPDATE, INSERT, DELETE ON public.row_level_security_col TO user2;
CREATE POLICY policy_col ON public.row_level_security_col FOR ALL TO PUBLIC USING (pgUser = current_user);
ALTER TABLE public.row_level_security_col ENABLE ROW LEVEL SECURITY;
SELECT * FROM public.row_level_security_col ORDER BY 1;
SET ROLE user1;
SELECT * FROM public.row_level_security_col;
SET ROLE user2;
SELECT * FROM public.row_level_security_col;
RESET ROLE;
DROP TABLE public.row_level_security_col;
DROP USER user1;
DROP USER user2;

SET client_min_messages TO WARNING;
DROP SCHEMA columnar_alter CASCADE;