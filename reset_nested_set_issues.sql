-- http://www.redmine.org/issues/3722#note-4

DROP PROCEDURE IF EXISTS Reset_Nested_Set_Issues;
DROP PROCEDURE IF EXISTS Reset_Nested_Set_Issues_recurse;

DELIMITER //

CREATE PROCEDURE Reset_Nested_Set_Issues()
BEGIN
	-- ensure root_id is correct for roots. Do it quickly here.
	UPDATE issues SET root_id = id WHERE parent_id IS NULL;

	-- MySQL didn't/doesn't allowed OUT or INOUT parameters
	SET @left_value = 1;

	-- now do recusion
	CALL Reset_Nested_Set_Issues_recurse(NULL, NULL);
END;
//

CREATE PROCEDURE Reset_Nested_Set_Issues_recurse(root INTEGER, parent INTEGER)
BEGIN
	DECLARE done             INTEGER DEFAULT 0;
	DECLARE node             INTEGER;
	DECLARE roots     CURSOR FOR SELECT id FROM issues WHERE parent_id IS NULL  ORDER BY id;
	DECLARE children  CURSOR FOR SELECT id FROM issues WHERE parent_id = parent ORDER BY id;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

	-- MySQL setting - allow up to 10 stored procedure recursions. Default is 0.
	SET max_sp_recursion_depth := 10;

	-- this is bypassed on first run
	IF parent IS NOT NULL THEN
		UPDATE issues SET root_id = root, lft = @left_value WHERE id = parent;
		SET @left_value := @left_value + 1;
	END IF;

	OPEN roots;
	OPEN children;

	-- for 1st run, and for root nodes
	IF parent IS NULL THEN
		FETCH roots INTO node;
		REPEAT
		IF node IS NOT NULL THEN
			CALL Reset_Nested_Set_Issues_recurse(node, node);
			SET @left_value := @left_value + 1;
		END IF;
		FETCH roots INTO node;
		UNTIL done END REPEAT;
	ELSE
		FETCH children INTO node;
		REPEAT
		IF node IS NOT NULL THEN
			CALL Reset_Nested_Set_Issues_recurse(root, node);
			SET @left_value := @left_value + 1;
		END IF;
		FETCH children INTO node;
		UNTIL done END REPEAT;
	END IF;
	UPDATE issues SET rgt = @left_value WHERE id = parent;

	CLOSE roots;
	CLOSE children;
END;
//

DELIMITER ;

-- CALL Reset_Nested_Set_Issues;

