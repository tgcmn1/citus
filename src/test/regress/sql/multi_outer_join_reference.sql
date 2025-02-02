SET citus.next_shard_id TO 1260000;

SET citus.log_multi_join_order to true;
SET client_min_messages TO LOG;

SET citus.shard_count TO 4;

CREATE TABLE multi_outer_join_left_hash
(
	l_custkey integer not null,
	l_name varchar(25) not null,
	l_address varchar(40) not null,
	l_nationkey integer not null,
	l_phone char(15) not null,
	l_acctbal decimal(15,2) not null,
	l_mktsegment char(10) not null,
	l_comment varchar(117) not null
);
SELECT create_distributed_table('multi_outer_join_left_hash', 'l_custkey');

CREATE TABLE multi_outer_join_right_reference
(
	r_custkey integer not null,
	r_name varchar(25) not null,
	r_address varchar(40) not null,
	r_nationkey integer not null,
	r_phone char(15) not null,
	r_acctbal decimal(15,2) not null,
	r_mktsegment char(10) not null,
	r_comment varchar(117) not null
);
SELECT create_reference_table('multi_outer_join_right_reference');

CREATE TABLE multi_outer_join_third_reference
(
	t_custkey integer not null,
	t_name varchar(25) not null,
	t_address varchar(40) not null,
	t_nationkey integer not null,
	t_phone char(15) not null,
	t_acctbal decimal(15,2) not null,
	t_mktsegment char(10) not null,
	t_comment varchar(117) not null
);
SELECT create_reference_table('multi_outer_join_third_reference');

CREATE TABLE multi_outer_join_right_hash
(
	r_custkey integer not null,
	r_name varchar(25) not null,
	r_address varchar(40) not null,
	r_nationkey integer not null,
	r_phone char(15) not null,
	r_acctbal decimal(15,2) not null,
	r_mktsegment char(10) not null,
	r_comment varchar(117) not null
);
SELECT create_distributed_table('multi_outer_join_right_hash', 'r_custkey');

-- Make sure we do not crash if both tables are emmpty
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_third_reference b ON (l_custkey = t_custkey);

-- Left table is a large table
\set customer_1_10_data :abs_srcdir '/data/customer-1-10.data'
\set customer_11_20_data :abs_srcdir '/data/customer-11-20.data'
\set client_side_copy_command '\\copy multi_outer_join_left_hash FROM ' :'customer_1_10_data' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy multi_outer_join_left_hash FROM ' :'customer_11_20_data' ' with delimiter '''|''';'
:client_side_copy_command

-- Right table is a small table
\set customer_1_15_data :abs_srcdir '/data/customer-1-15.data'
\set client_side_copy_command '\\copy multi_outer_join_right_reference FROM ' :'customer_1_15_data' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy multi_outer_join_right_hash FROM ' :'customer_1_15_data' ' with delimiter '''|''';'
:client_side_copy_command

-- Make sure we do not crash if one table has data
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_third_reference b ON (l_custkey = t_custkey);

SELECT
	min(t_custkey), max(t_custkey)
FROM
	multi_outer_join_third_reference a LEFT JOIN multi_outer_join_right_reference b ON (r_custkey = t_custkey);

-- Third table is a single shard table with all data
\set customer_1_30_data :abs_srcdir '/data/customer-1-30.data'
\set client_side_copy_command '\\copy multi_outer_join_third_reference FROM ' :'customer_1_30_data' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy multi_outer_join_right_hash FROM ' :'customer_1_30_data' ' with delimiter '''|''';'
:client_side_copy_command


-- Regular outer join should return results for all rows
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey);

-- Since this is a broadcast join, we should be able to join on any key
SELECT
	count(*)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_nationkey = r_nationkey);


-- Anti-join should return customers for which there is no row in the right table
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey)
WHERE
	r_custkey IS NULL;


-- Partial anti-join with specific value
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey)
WHERE
	r_custkey IS NULL OR r_custkey = 5;


-- This query is an INNER JOIN in disguise since there cannot be NULL results
-- Added extra filter to make query not router plannable
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey)
WHERE
	r_custkey = 5 or r_custkey > 15;


-- Apply a filter before the join
SELECT
	count(l_custkey), count(r_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b
	ON (l_custkey = r_custkey AND r_custkey = 5);

-- Apply a filter before the join (no matches right)
SELECT
	count(l_custkey), count(r_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b
	ON (l_custkey = r_custkey AND r_custkey = -1 /* nonexistant */);

-- Apply a filter before the join (no matches left)
SELECT
	count(l_custkey), count(r_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b
	ON (l_custkey = r_custkey AND l_custkey = -1 /* nonexistant */);

-- Right join should be disallowed in this case
SELECT
	min(r_custkey), max(r_custkey)
FROM
	multi_outer_join_left_hash a RIGHT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey);


-- Reverse right join should be same as left join
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_right_reference a RIGHT JOIN multi_outer_join_left_hash b ON (l_custkey = r_custkey);


-- load some more data
\set customer_21_30_data :abs_srcdir '/data/customer-21-30.data'
\set client_side_copy_command '\\copy multi_outer_join_right_reference FROM ' :'customer_21_30_data' ' with delimiter '''|''';'
:client_side_copy_command

-- Update shards so that they do not have 1-1 matching, triggering an error.
UPDATE pg_dist_shard SET shardminvalue = '2147483646' WHERE shardid = 1260006;
UPDATE pg_dist_shard SET shardmaxvalue = '2147483647' WHERE shardid = 1260006;
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_hash b ON (l_custkey = r_custkey);
UPDATE pg_dist_shard SET shardminvalue = '-2147483648' WHERE shardid = 1260006;
UPDATE pg_dist_shard SET shardmaxvalue = '-1073741825' WHERE shardid = 1260006;

-- empty tables
TRUNCATE multi_outer_join_left_hash, multi_outer_join_right_hash, multi_outer_join_right_reference;

-- reload shards with 1-1 matching
\set client_side_copy_command '\\copy multi_outer_join_left_hash FROM ' :'customer_1_15_data' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy multi_outer_join_left_hash FROM ' :'customer_21_30_data' ' with delimiter '''|''';'
:client_side_copy_command

\set client_side_copy_command '\\copy multi_outer_join_right_reference FROM ' :'customer_11_20_data' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy multi_outer_join_right_reference FROM ' :'customer_21_30_data' ' with delimiter '''|''';'
:client_side_copy_command

\set client_side_copy_command '\\copy multi_outer_join_right_hash FROM ' :'customer_11_20_data' ' with delimiter '''|''';'
:client_side_copy_command
\set client_side_copy_command '\\copy multi_outer_join_right_hash FROM ' :'customer_21_30_data' ' with delimiter '''|''';'
:client_side_copy_command

-- multi_outer_join_third_reference is a single shard table

-- Regular left join should work as expected
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_hash b ON (l_custkey = r_custkey);


-- Citus can use broadcast join here
SELECT
	count(*)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_hash b ON (l_nationkey = r_nationkey);


-- Anti-join should return customers for which there is no row in the right table
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey)
WHERE
	r_custkey IS NULL;


-- Partial anti-join with specific value (5, 11-15)
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey)
WHERE
	r_custkey IS NULL OR r_custkey = 15;


-- This query is an INNER JOIN in disguise since there cannot be NULL results (21)
-- Added extra filter to make query not router plannable
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey)
WHERE
	r_custkey = 21 or r_custkey < 10;


-- Apply a filter before the join
SELECT
	count(l_custkey), count(r_custkey)
FROM
	multi_outer_join_left_hash a LEFT JOIN multi_outer_join_right_reference b
	ON (l_custkey = r_custkey AND r_custkey = 21);


-- Right join should not be allowed in this case
SELECT
	min(r_custkey), max(r_custkey)
FROM
	multi_outer_join_left_hash a RIGHT JOIN multi_outer_join_right_reference b ON (l_custkey = r_custkey);


-- Reverse right join should be same as left join
SELECT
	min(l_custkey), max(l_custkey)
FROM
	multi_outer_join_right_reference a RIGHT JOIN multi_outer_join_left_hash b ON (l_custkey = r_custkey);


-- complex query tree should error out
SELECT
	*
FROM
	multi_outer_join_left_hash l1
	LEFT JOIN multi_outer_join_right_reference r1 ON (l1.l_custkey = r1.r_custkey)
	LEFT JOIN multi_outer_join_right_reference r2 ON (l1.l_custkey  = r2.r_custkey)
	RIGHT JOIN multi_outer_join_left_hash l2 ON (r2.r_custkey = l2.l_custkey);

-- add an anti-join, this should also error out
SELECT
	*
FROM
	multi_outer_join_left_hash l1
	LEFT JOIN multi_outer_join_right_reference r1 ON (l1.l_custkey = r1.r_custkey)
	LEFT JOIN multi_outer_join_right_reference r2 ON (l1.l_custkey  = r2.r_custkey)
	RIGHT JOIN multi_outer_join_left_hash l2 ON (r2.r_custkey = l2.l_custkey)
WHERE
	r1.r_custkey is NULL;

-- Three way join 2-1-1 (broadcast + broadcast join) should work
SELECT
	l_custkey, r_custkey, t_custkey
FROM
	multi_outer_join_left_hash l1
	LEFT JOIN multi_outer_join_right_reference r1 ON (l1.l_custkey = r1.r_custkey)
	LEFT JOIN multi_outer_join_third_reference t1 ON (r1.r_custkey  = t1.t_custkey)
ORDER BY 1;

-- Right join with single shard right most table should error out
SELECT
	l_custkey, r_custkey, t_custkey
FROM
	multi_outer_join_left_hash l1
	LEFT JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey = r1.r_custkey)
	RIGHT JOIN multi_outer_join_third_reference t1 ON (r1.r_custkey  = t1.t_custkey);

-- Right join with single shard left most table should work
SELECT
	t_custkey, r_custkey, l_custkey
FROM
	multi_outer_join_third_reference t1
	RIGHT JOIN multi_outer_join_right_hash r1 ON (t1.t_custkey = r1.r_custkey)
	LEFT JOIN multi_outer_join_left_hash l1 ON (r1.r_custkey  = l1.l_custkey)
ORDER BY 1,2,3;

-- Make it anti-join, should display values with l_custkey is null
SELECT
	t_custkey, r_custkey, l_custkey
FROM
	multi_outer_join_third_reference t1
	RIGHT JOIN multi_outer_join_right_hash r1 ON (t1.t_custkey = r1.r_custkey)
	LEFT JOIN multi_outer_join_left_hash l1 ON (r1.r_custkey  = l1.l_custkey)
WHERE
	l_custkey is NULL
ORDER BY 1;

-- Cascading right join with single shard left most table should work
SELECT
	t_custkey, r_custkey, l_custkey
FROM
	multi_outer_join_third_reference t1
	RIGHT JOIN multi_outer_join_right_hash r1 ON (t1.t_custkey = r1.r_custkey)
	RIGHT JOIN multi_outer_join_left_hash l1 ON (r1.r_custkey  = l1.l_custkey)
ORDER BY l_custkey;

-- full outer join should work with 1-1 matched shards
SELECT
	l_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	FULL JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey = r1.r_custkey)
ORDER BY 1,2;

-- full outer join + anti (right) should work with 1-1 matched shards
SELECT
	l_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	FULL JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey = r1.r_custkey)
WHERE
	r_custkey is NULL
ORDER BY 1;

-- full outer join + anti (left) should work with 1-1 matched shards
SELECT
	l_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	FULL JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey = r1.r_custkey)
WHERE
	l_custkey is NULL
ORDER BY 2;

-- full outer join + anti (both) should work with 1-1 matched shards
SELECT
	l_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	FULL JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey = r1.r_custkey)
WHERE
	l_custkey is NULL or r_custkey is NULL
ORDER BY 1,2 DESC;

-- full outer join should error out for mismatched shards
SELECT
	l_custkey, t_custkey
FROM
	multi_outer_join_left_hash l1
	FULL JOIN multi_outer_join_third_reference t1 ON (l1.l_custkey = t1.t_custkey);

-- inner join  + single shard left join should work
SELECT
	l_custkey, r_custkey, t_custkey
FROM
	multi_outer_join_left_hash l1
	INNER JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey = r1.r_custkey)
	LEFT JOIN multi_outer_join_third_reference t1 ON (r1.r_custkey  = t1.t_custkey)
ORDER BY 1;

-- inner (broadcast) join  + 2 shards left (local) join should work
SELECT
	l_custkey, t_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	INNER JOIN multi_outer_join_third_reference t1 ON (l1.l_custkey = t1.t_custkey)
	LEFT JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey  = r1.r_custkey)
ORDER BY 1,2,3;

-- inner (local) join  + 2 shards left (dual partition) join
SELECT
	t_custkey, l_custkey, r_custkey
FROM
	multi_outer_join_third_reference t1
	INNER JOIN multi_outer_join_left_hash l1 ON (l1.l_custkey = t1.t_custkey)
	LEFT JOIN multi_outer_join_right_reference r1 ON (l1.l_custkey  = r1.r_custkey)
ORDER BY 1,2,3;

-- inner (local) join  + 2 shards left (dual partition) join should work
SELECT
	l_custkey, t_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	INNER JOIN multi_outer_join_third_reference t1 ON (l1.l_custkey = t1.t_custkey)
	LEFT JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey  = r1.r_custkey)
ORDER BY 1,2,3;

-- inner (broadcast) join  + 2 shards left (local) + anti join should work
SELECT
	l_custkey, t_custkey, r_custkey
FROM
	multi_outer_join_left_hash l1
	INNER JOIN multi_outer_join_third_reference t1 ON (l1.l_custkey = t1.t_custkey)
	LEFT JOIN multi_outer_join_right_hash r1 ON (l1.l_custkey  = r1.r_custkey)
WHERE
	r_custkey is NULL
ORDER BY 1;

-- Test joinExpr aliases by performing an outer-join.
SELECT
	t_custkey
FROM
	(multi_outer_join_right_hash r1
	LEFT OUTER JOIN multi_outer_join_left_hash l1 ON (l1.l_custkey = r1.r_custkey)) AS
    test(c_custkey, c_nationkey)
    INNER JOIN multi_outer_join_third_reference t1 ON (test.c_custkey = t1.t_custkey)
ORDER BY 1;

-- flattened out subqueries with outer joins are not supported
SELECT
  l1.l_custkey,
  count(*) as cnt
FROM (
  SELECT l_custkey, l_nationkey
  FROM multi_outer_join_left_hash
  WHERE l_comment like '%a%'
) l1
LEFT JOIN (
  SELECT r_custkey, r_name
  FROM multi_outer_join_right_reference
  WHERE r_comment like '%b%'
) l2 ON l1.l_custkey = l2.r_custkey
GROUP BY l1.l_custkey
ORDER BY cnt DESC, l1.l_custkey DESC
LIMIT 20;

-- full join among reference tables should go thourgh router planner
SELECT
	t_custkey, r_custkey
FROM
	multi_outer_join_right_reference FULL JOIN
	multi_outer_join_third_reference ON (t_custkey = r_custkey)
ORDER BY 1;

-- complex join order with multiple children on the right
SELECT
     count(*)
FROM
    multi_outer_join_left_hash l1
LEFT JOIN (
    multi_outer_join_right_reference r1
    INNER JOIN
    multi_outer_join_third_reference r2
    ON (r_name = t_name)
) AS bar
ON (l_name = r_name);

-- DROP unused tables to clean up workspace
DROP TABLE multi_outer_join_left_hash;
DROP TABLE multi_outer_join_right_reference;
DROP TABLE multi_outer_join_third_reference;
DROP TABLE multi_outer_join_right_hash;
