-- pgsql_061_content_storage.sql

BEGIN;

set search_path = imsto, public;

-- 初始化 hash 表

CREATE OR REPLACE FUNCTION hash_tables_init()
RETURNS int AS
$$
DECLARE
	count int;
	suffix text;
	tbname text;
BEGIN

	count := 0;
-- 创建 表
FOR i IN 0..15 LOOP
	-- some computations here
	suffix := to_hex(i%16);
	tbname := 'hash_' || suffix;

	IF NOT EXISTS(SELECT tablename FROM pg_catalog.pg_tables WHERE
		schemaname = 'imsto' AND tablename = tbname) THEN
	RAISE NOTICE 'tb is %', tbname;
	EXECUTE 'CREATE TABLE imsto.' || tbname || '
	(
		LIKE imsto.hash_template INCLUDING ALL ,
		CHECK (hashed LIKE ' || quote_literal(suffix||'%') || ')
	)
	INHERITS (imsto.hash_template)
	WITHOUT OIDS ;';
	count := count + 1;
	END IF;
END LOOP;

RETURN count;
END;
$$
LANGUAGE 'plpgsql' VOLATILE;

-- 保存 hash 记录
CREATE OR REPLACE FUNCTION hash_save(a_hashed text, a_item_id text, a_path text, a_size int)

RETURNS int AS
$$
DECLARE
	suffix text;
	tbname text;
	t_id text;
BEGIN

	IF char_length(a_hashed) < 20 THEN
		RAISE NOTICE 'bad hash value {%}', a_hashed;
		RETURN -1;
	END IF;

	suffix := substr(a_hashed, 1, 1);
	tbname := 'imsto.hash_'||suffix;

	EXECUTE 'SELECT item_id FROM '||tbname||' WHERE hashed = $1 LIMIT 1'
	INTO t_id
	USING a_hashed;

	IF t_id IS NOT NULL THEN
		RAISE NOTICE 'exists hash %(%)', a_hashed, t_id;
		RETURN -1;
	END IF;

	EXECUTE 'INSERT INTO '||tbname||' (hashed, item_id, path, size) VALUES (
		$1, $2, $3, $4
	)'
	USING a_hashed, a_item_id, a_path, a_size;

RETURN 1;
END;
$$
LANGUAGE 'plpgsql' VOLATILE;


-- hash trigger
CREATE OR REPLACE FUNCTION hash_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
	PERFORM hash_save(NEW.hashed, NEW.item_id, NEW.path, NEW.size);
	RETURN NULL;
END;
$$
LANGUAGE plpgsql;

-- CREATE TRIGGER hash_insert_trigger BEFORE INSERT ON hash_template
-- FOR EACH ROW EXECUTE PROCEDURE hash_insert_trigger();


-- 保存 map 记录
CREATE OR REPLACE FUNCTION map_save(
	a_id text, a_path text, a_name text, a_size int, a_sev jsonb, a_roof text)

RETURNS int AS
$$
DECLARE
	suffix text;
	tbname text;
	t_st smallint;
	t_roofs text[];
	i_roofs text[];
BEGIN

	suffix := substr(a_id, 1, 2);
	tbname := 'mapping_'||suffix;
	IF NOT EXISTS(SELECT tablename FROM pg_catalog.pg_tables WHERE
		schemaname = 'imsto' AND tablename = tbname) THEN
		EXECUTE 'CREATE TABLE imsto.' || tbname || '
		(
			LIKE imsto.map_template INCLUDING ALL ,
			CHECK (id LIKE ' || quote_literal(suffix||'%') || ')
		)
		INHERITS (imsto.map_template)
		WITHOUT OIDS ;';
	END IF;
	i_roofs := ('{' || a_roof || '}')::text[];

	EXECUTE 'SELECT roofs FROM '||tbname||' WHERE id = $1 LIMIT 1'
	INTO t_roofs
	USING a_id;

	IF t_roofs IS NOT NULL THEN
		RAISE NOTICE 'exists map %', t_roofs;
		-- TODO: merge roofs
		IF NOT t_roofs @> i_roofs THEN
		t_roofs := t_roofs || i_roofs;
		EXECUTE 'UPDATE ' || tbname || ' SET roofs = $1 WHERE id = $2'
		USING t_roofs, a_id;
		END IF;
		RETURN -1;
	ELSE
		t_roofs := i_roofs;
	END IF;

	EXECUTE 'INSERT INTO ' || tbname || '(id, path, name, size, sev, roofs) VALUES (
		$1, $2, $3, $4, $5, $6
	)'
	USING a_id, a_path, a_name, a_size, a_sev, t_roofs;

RETURN 1;
END;
$$
LANGUAGE 'plpgsql' VOLATILE;


-- 保存某条完整 entry 信息
CREATE OR REPLACE FUNCTION entry_save (a_roof text,
	a_id text, a_path text, a_name text, a_size int, a_meta jsonb, a_sev jsonb
	, a_hashes jsonb, a_ids text[]
	, a_appid int, a_author int, a_tags text[])

RETURNS int AS
$$
DECLARE
	m_v text;
	-- tb_hash text;
	-- tb_map text;
	-- t_name text;
	tb_meta text;
	t_status smallint;
BEGIN

	tb_meta := 'meta_' || a_roof;

	EXECUTE 'SELECT status FROM '||tb_meta||' WHERE id = $1 LIMIT 1'
	INTO t_status
	USING a_id;

	IF t_status IS NOT NULL THEN
		RAISE NOTICE 'exists meta %', t_status;
		IF t_status = 1 THEN -- deleted, so restore it
			EXECUTE 'UPDATE ' || tb_meta || ' SET status = 0 WHERE id = $1'
			USING a_id;
			RETURN -2;
		END IF;
		RETURN -1;
	END IF;

	-- save entry hashes
	PERFORM hash_save((a_hashes->>'hash')::text, a_id, a_path, (a_hashes->>'size')::int);
	IF a_hashes ? 'hash2' AND a_hashes ? 'size2' THEN
		PERFORM hash_save((a_hashes->>'hash2')::text, a_id, a_path, (a_hashes->>'size2')::int);
	END IF;

	-- save entry map
	FOR m_v IN SELECT UNNEST(a_ids) AS value LOOP
		PERFORM map_save(m_v, a_path, a_name, a_size, a_sev, a_roof);
	END LOOP;

	IF NOT a_ids @> ARRAY[a_id] THEN
		PERFORM map_save(a_id, a_path, a_name, a_size, a_sev, a_roof);
	END IF;

	-- save entry meta
	EXECUTE 'INSERT INTO ' || tb_meta || '(id, path, name, size, meta, hashes, ids, sev, app_id, author, roof, tags)
	 VALUES (
		$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12
	)'
	USING a_id, a_path, a_name, a_size, a_meta, a_hashes, a_ids, a_sev, a_appid, a_author, a_roof, a_tags;

RETURN 1;
END;
$$
LANGUAGE 'plpgsql' VOLATILE;


-- 预先保存某条完整 entry 信息
CREATE OR REPLACE FUNCTION entry_ready (a_roof text,
	a_id text, a_path text, a_meta json
	, a_hashes json, a_ids text[]
	, a_appid smallint, a_author int, a_tags text[])

RETURNS int AS
$$
BEGIN

RAISE NOTICE 'meta size %', a_meta->'size';

IF NOT EXISTS(SELECT created FROM meta__prepared WHERE id = a_id) THEN
	INSERT INTO meta__prepared (id, roof, path, name, size, meta, hashes, ids, app_id, author, tags)
	VALUES (a_id, a_roof, a_path, a_meta->'name', (a_meta->'size'), a_meta, a_hashes, a_ids, a_appid, a_author, a_tags);
	IF FOUND THEN
		RETURN 1;
	ELSE
		RETURN -1;
	END IF;
ELSE
	RETURN -2;
END IF;

END;
$$
LANGUAGE 'plpgsql' VOLATILE;

CREATE OR REPLACE FUNCTION entry_set_done(a_id text, a_sev jsonb)
RETURNS int AS
$$
DECLARE
	m_rec RECORD;
	t_ret int;
BEGIN

SELECT * FROM meta__prepared WHERE id = a_id INTO m_rec;
IF NOT FOUND THEN
	RETURN -2;
END IF;

SELECT entry_save(m_rec.roof, m_rec.id, m_rec.path, m_rec.name, m_rec.size, m_rec.meta, a_sev,
 m_rec.hashes, m_rec.ids, m_rec.app_id, m_rec.author, m_rec.tags) INTO t_ret;

DELETE FROM meta__prepared WHERE id = a_id;

RETURN t_ret;

END;
$$
LANGUAGE 'plpgsql' VOLATILE;


CREATE OR REPLACE FUNCTION entry_delete(a_roof text, a_id text)
RETURNS int AS
$$
DECLARE
	tb_hash text;
	tb_map text;
	tb_meta text;
	rec RECORD;
	s text;
BEGIN

	tb_map := 'mapping_' || substr(a_id, 1, 2);
	RAISE NOTICE 'delete mapping: %.%', tb_map, a_id;
	EXECUTE 'DELETE FROM '||tb_map||' WHERE id = $1' USING a_id;

	tb_meta := 'meta_' || a_roof;
	EXECUTE 'SELECT * FROM '||tb_meta||' WHERE id = $1 LIMIT 1'
	INTO rec
	USING a_id;

	IF rec.status IS NULL THEN
		RETURN -1;
	END IF;

	IF NOT EXISTS (SELECT status FROM meta__deleted WHERE id = a_id) THEN
		INSERT INTO meta__deleted (id, path, name, roof, meta, hashes, ids, size
			, sev, exif, app_id, author, status, created, tags)
		 VALUES(rec.id, rec.path, rec.name, rec.roof, rec.meta, rec.hashes, rec.ids, rec.size
		 , rec.sev, COALESCE(rec.exif, '{}'), rec.app_id, rec.author, rec.status, rec.created, rec.tags);
	END IF;

	-- delete hashes
	EXECUTE 'DELETE FROM hash_' || substr(rec.hashes->>'hash', 1, 1)||' WHERE hashed = $1' USING rec.hashes->>'hash';
	IF rec.hashes ? 'hash2' AND rec.hashes ? 'size2' THEN
		EXECUTE 'DELETE FROM hash_' || substr(rec.hashes->>'hash2', 1, 1)||' WHERE hashed = $1' USING rec.hashes->>'hash2';
	END IF;

	-- delete mapping
	FOR s IN SELECT UNNEST(rec.ids) AS value LOOP
		tb_map := 'mapping_' || substr(s, 1, 2);
		RAISE NOTICE 'delete mapping: %.%', tb_map, s;
		EXECUTE 'DELETE FROM '||tb_map||' WHERE id = $1' USING s;
	END LOOP;

	EXECUTE 'DELETE FROM '||tb_meta||' WHERE id = $1'
	USING a_id;

	RETURN 1;

END;
$$
LANGUAGE 'plpgsql' VOLATILE;


CREATE OR REPLACE FUNCTION tag_map(a_roof text, a_id text, VARIADIC a_tags text[])
RETURNS int AS
$$
DECLARE
	tb_meta text;
	rec RECORD;
	n_tags text[];
	s text;
	t_ret int;

BEGIN
	tb_meta := 'meta_' || a_roof;

	EXECUTE 'SELECT status, tags FROM '||tb_meta||' WHERE id = $1 LIMIT 1'
	INTO rec
	USING a_id;

	IF rec.status IS NULL THEN
		RETURN -2;
	END IF;

	n_tags := rec.tags;

	IF n_tags @> a_tags THEN
		RETURN -1;
	END IF;

	t_ret := 0;

	FOR s IN SELECT UNNEST(a_tags) LOOP
		IF NOT n_tags @> ARRAY[s] THEN
			n_tags := n_tags || s;
			t_ret := t_ret + 1;
		END IF;

	END LOOP;

	-- RAISE NOTICE 'new tags is % (%)', array_length(n_tags, 1), array_length(rec.tags, 1);
	IF t_ret > 0 THEN
		EXECUTE 'UPDATE '||tb_meta||' SET tags = $1 WHERE id = $2'
		USING n_tags, a_id;
	END IF;

	RETURN t_ret;


END;
$$
LANGUAGE 'plpgsql' VOLATILE;


CREATE OR REPLACE FUNCTION tag_unmap(a_roof text, a_id text, VARIADIC a_tags text[])
RETURNS int AS
$$
DECLARE
	tb_meta text;
	rec RECORD;
	n_tags text[];
	s text;
	t_ret int;

BEGIN
	tb_meta := 'meta_' || a_roof;

	EXECUTE 'SELECT status, tags FROM '||tb_meta||' WHERE id = $1 LIMIT 1'
	INTO rec
	USING a_id;

	IF rec.status IS NULL THEN
		RETURN -2;
	END IF;

	-- 有重叠部分才操作
	IF NOT rec.tags::text[] && a_tags THEN
		RETURN -1;
	END IF;

	t_ret := 0;

	n_tags := ARRAY[]::text[];

	FOR s IN SELECT UNNEST(rec.tags) LOOP
		-- RAISE NOTICE 'CHECK tag: % %', s, a_tags;
		IF NOT a_tags @> ARRAY[s] THEN
			RAISE NOTICE 'will remove tag: %', s;
			n_tags := n_tags || s;
		ELSE
			t_ret := t_ret + 1;
		END IF;

	END LOOP;

	-- RAISE NOTICE 'new tags is %', n_tags;
	-- RAISE NOTICE 'new tags is % (%)', array_length(n_tags, 1), array_length(rec.tags, 1);
	IF t_ret > 0 THEN
		EXECUTE 'UPDATE '||tb_meta||' SET tags = $1 WHERE id = $2'
		USING n_tags, a_id;
	END IF;

	RETURN t_ret;


END;
$$
LANGUAGE 'plpgsql' VOLATILE;




END;


SET search_path = imsto;
SELECT hash_tables_init();



