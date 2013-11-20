-- pgsql_11_imsto_auth.sql
-- 验证相关

BEGIN;

set search_path = imsto, public;

-- 更新 ticket
CREATE OR REPLACE FUNCTION imsto.ticket_update(a_id int, a_item_id varchar)
RETURNS int AS
$$
DECLARE
	t_section varchar;
	tb_meta varchar;
	t_path varchar;

BEGIN

	SELECT section INTO t_section FROM upload_ticket WHERE id = a_id;
	IF t_section IS NULL THEN
		RETURN -1;
	END IF;

	tb_meta := 'meta_' || t_section;

	EXECUTE 'SELECT path FROM '||tb_meta||' WHERE id = $1 LIMIT 1'
	INTO t_path
	USING a_item_id;

	IF t_path IS NULL THEN
		RAISE NOTICE 'item not found %', a_item_id;
		RETURN -2;
	END IF;

	UPDATE upload_ticket 
	SET img_id=a_item_id, img_path=t_path, uploaded=true, updated=CURRENT_TIMESTAMP
	WHERE id = a_id;

RETURN 1;
END;
$$
LANGUAGE 'plpgsql' VOLATILE;



END;