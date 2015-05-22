-- Version: 0.1.0

-- old names

DROP PROCEDURE IF EXISTS Execute_SQL;
DROP FUNCTION  IF EXISTS Sanitize_Identifier;
DROP PROCEDURE IF EXISTS Denormalize_Base_Table;
DROP EVENT     IF EXISTS Generate_Denormalized_Base_Tables;

-- current names
DROP PROCEDURE IF EXISTS ExecuteSQL;
DROP FUNCTION  IF EXISTS SanitizeIdentifier;
DROP PROCEDURE IF EXISTS redmine_DenormalizeTable;
DROP EVENT     IF EXISTS redmine_DenormalizeTables;

DELIMITER //




-- http://stackoverflow.com/questions/5895383/mysql-prepare-statement-in-stored-procedures
CREATE PROCEDURE ExecuteSQL(IN sqlQ VARCHAR(5000)) COMMENT 'Executes the statement'
BEGIN
	SET @sqlV=sqlQ;
	PREPARE stmt FROM @sqlV;
	EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END;
//




-- replaces all non-alnum chars (a-zA-Z0-9) with underscopres (_).
-- optionalUnique is only used if baseName contains chars other than 'a-zA-Z0-9_ '.
--   if optionalUnique is empty, then '0' is used.
-- prefixes return value with '_' if the first char is a number.
-- size 63 taken per http://dev.mysql.com/doc/refman/5.5/en/identifiers.html
CREATE FUNCTION SanitizeIdentifier(baseName VARCHAR(63), optionalUnique VARCHAR(63))
	RETURNS VARCHAR(63) DETERMINISTIC
BEGIN
	DECLARE prefix     CHAR(1) DEFAULT '_';
	DECLARE suffix     CHAR(1) DEFAULT '0';

	DECLARE idName     VARCHAR(50);
	DECLARE useUnique  BOOLEAN DEFAULT FALSE;
	DECLARE minPos     TINYINT UNSIGNED;
	DECLARE currPos    TINYINT UNSIGNED;
	DECLARE currChar   CHAR(1);

	SET idName := REPLACE(baseName, ' ', '_');

	IF idName = '' THEN
		SET useUnique := TRUE;
	ELSE
		-- start from right end, as may delete chars and so index will change
		SET minPos     := 0;
		SET currPos    := CHAR_LENGTH(idName);

		WHILE currPos > minPos DO
			SET currChar := SUBSTRING(idName, currPos, 1);

			IF currChar NOT REGEXP '[a-z0-9_]' THEN
					SET idName    := INSERT(idName, currPos, 1, '_');
					SET useUnique := TRUE;
			END IF;

			SET currPos := CurrPos - 1;
		END WHILE;
	END IF;

	IF useUnique THEN
		IF optionalUnique = '' THEN
			SET idName := CONCAT(idName, suffix);
		ELSE
			SET minPos  := CHAR_LENGTH(idName);
			SET idName  := CONCAT(idName, REPLACE(optionalUnique, ' ', '_'));
			SET currPos := CHAR_LENGTH(idName);

			WHILE currPos > minPos DO
				SET currChar := SUBSTRING(idName, currPos, 1);

				IF currChar NOT REGEXP '[a-z0-9_]' THEN
						SET idName := INSERT(idName, currPos, 1, '_');
				END IF;

				SET currPos := CurrPos - 1;
			END WHILE;

			-- if baseName was empty or all-invalid, and optionalUnique was all-invalid
			-- then idName will be empty
			IF idName = '' THEN
				-- concat prefix as well to avoid being updated again by later 1st char=num check
				SET idName := CONCAT(prefix,suffix);
			END IF;
		END IF;
	END IF;

	-- ensure doesn't start with digit
	IF LEFT(idName, 1) REGEXP '[[:digit:]]' THEN
		SET idName := CONCAT(prefix, idName);
	END IF;

	RETURN(idName);
END;
//

-- test cases for SanitizeIdentifier function
-- [v]alid, [i]nvalid, [e]mpty, [s]pace with valid, [S]pace with invalid
-- SELECT
-- 	 SanitizeIdentifier(''   ,'')     AS     _0_ee
-- 	,SanitizeIdentifier('abc','')     AS    abc_ve
-- 	,SanitizeIdentifier(''   ,'xyz')  AS    xyz_ev
-- 	,SanitizeIdentifier('abc','xyz')  AS    abc_vv
-- 	,SanitizeIdentifier(''   ,'@&*')  AS     _0_ei--
-- 	,SanitizeIdentifier('^$#','')     AS     _0_ie
-- 	,SanitizeIdentifier('^$#','@&*')  AS     _0_ii--
-- 	,SanitizeIdentifier('@&*','^$#')  AS     _0_iir--
-- 	,SanitizeIdentifier('abc','@&*')  AS    abc_vi
-- 	,SanitizeIdentifier('^$#','xyz')  AS    xyz_iv
-- 	,SanitizeIdentifier('a c','x z')  AS    a_c_ss
-- 	,SanitizeIdentifier('a c','@ *')  AS    a_c_sS
-- 	,SanitizeIdentifier('^ #','x z')  AS   _x_z_Ss
-- 	,SanitizeIdentifier('^ #','@ *')  AS     ___SS
-- ;




-- baseTable = ['issues', 'projects, 'users', 'versions']
CREATE PROCEDURE redmine_DenormalizeTable(IN baseTable VARCHAR(50))
	COMMENT 'creates an _baseTable for issues and projects'
--	LANGUAGE SQL
--	DETERMINISTIC
--	MODIFIES SQL DATA
--	SQL SECURITY INVOKER

thisProc: BEGIN
	-- declare variables
	DECLARE sqlQ          VARCHAR(5000);

	DECLARE customizedType VARCHAR(10);

	DECLARE reportTable   VARCHAR(10);
	DECLARE rtSqlSelect   VARCHAR(5000);
	DECLARE rtSqlFrom     VARCHAR(5000) DEFAULT '';
	DECLARE rtSqlAlter    VARCHAR(5000) DEFAULT '';

	DECLARE tempTable     VARCHAR(15);
	DECLARE ttSqlSelect   VARCHAR(5000) DEFAULT '';

	DECLARE cfId          INTEGER UNSIGNED;
	DECLARE cfType        VARCHAR(50);
	DECLARE cfName        VARCHAR(50);
	DECLARE cfFieldFormat VARCHAR(50);
	DECLARE cfDataType    VARCHAR(50);
	DECLARE cfMultiple    BOOLEAN;
	DECLARE cfAlias       VARCHAR(10);

	DECLARE done          BOOLEAN       DEFAULT FALSE;
	DECLARE cfCursor      CURSOR FOR
		-- SELECT id, name, field_format FROM custom_fields WHERE type IN (cfType);
		SELECT id, name, field_format, multiple FROM custom_fields WHERE FIND_IN_SET(type, cfType);
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET done := TRUE;

	SET customizedType := INSERT(baseTable, CHAR_LENGTH(baseTable), 1, '');
	SET cfType         := CONCAT(customizedType, 'CustomField');
	SET reportTable    := CONCAT('_', baseTable);

	-- process source table columns
	CASE baseTable
		WHEN 'issues' THEN
			SET rtSqlSelect    := CONCAT(
				', lt.name AS tracker',
				', lp.name AS project',
				', lc.name AS category',
				', ls.name AS status',
				', IF(luv.login="",luv.lastname,luv.login) AS visible_to',
				', le.name   AS priority',
				', lvt.name  AS target_version',
				', lua.login AS author'
			);
			SET rtSqlFrom      := CONCAT(
				' INNER JOIN trackers         AS lt  ON rt.tracker_id      = lt.id',
				' INNER JOIN projects         AS lp  ON rt.project_id      = lp.id',
				'  LEFT JOIN issue_categories AS lc  ON rt.category_id     = lc.id',
				' INNER JOIN issue_statuses   AS ls  ON rt.status_id       = ls.id',
				'  LEFT JOIN users            AS luv ON rt.assigned_to_id  = luv.id',
				' INNER JOIN enumerations     AS le  ON rt.priority_id     = le.id',
				'  LEFT JOIN versions         AS lvt ON rt.fixed_version_id= lvt.id',
				' INNER JOIN users            AS lua ON rt.author_id       = lua.id'
			);
			SET rtSqlAlter     := CONCAT(
				',CHANGE COLUMN assigned_to_id   visible_to_id     INTEGER(11)',
				',CHANGE COLUMN fixed_version_id target_version_id INTEGER(11)'
			);
		WHEN 'projects' THEN
			SET rtSqlSelect    := CONCAT(
				', CASE status WHEN 1 THEN "active" WHEN 5 THEN "closed" WHEN 9 THEN "archived" END AS status_name'
			);
		WHEN 'users' THEN
			SET customizedType := 'Principal';
			SET cfType         := 'UserCustomField,GroupCustomField';

			SET rtSqlSelect    := '';
		WHEN 'versions' THEN
			SET rtSqlSelect    := '';
		ELSE
			LEAVE thisProc;
	END CASE;

	-- int variables
	SET tempTable      := CONCAT(reportTable, '_temp');


	-- process custom fields/values
	OPEN cfCursor;
	cfLoop: LOOP
		FETCH cfCursor INTO cfId, cfName, cfFieldFormat, cfMultiple;

		IF done THEN LEAVE cfLoop; END IF;

		-- handle duplicate custom field names - possible for users and groups
		IF LOCATE(CONCAT(' AS "',cfName, '"'), ttSqlSelect) > 0 THEN
			SET cfName := CONCAT(cfName, cfId);
		END IF;

		-- strip non-alphanum chars
		SET cfName := SanitizeIdentifier(cfName, cfId);

		-- TODO: handle 'multiple' more intelligently
		IF cfMultiple THEN
			SET cfDataType := 'CHAR(255)';
		ELSE
			CASE cfFieldFormat
				WHEN 'bool'    THEN SET cfDataType := 'DECIMAL(1)';
				WHEN 'date'    THEN SET cfDataType := 'DATE';
				WHEN 'float'   THEN SET cfDataType := 'DECIMAL(10,10)';
				WHEN 'int'     THEN SET cfDataType := 'UNSIGNED INTEGER';
				WHEN 'user'    THEN
					SET cfDataType  := 'UNSIGNED INTEGER';
					SET cfAlias     := CONCAT('u', cfId);
					SET rtSqlSelect := CONCAT(rtSqlSelect, ', IF(', cfAlias, '.login="",', cfAlias, '.lastname,', cfAlias, '.login) AS "', cfName, '"');

					SET cfName      := CONCAT(cfName, '_id');
					SET rtSqlFrom   := CONCAT(rtSqlFrom, ' LEFT JOIN users AS ', cfAlias, ' ON rt.', cfName, '=', cfAlias, '.id');
				WHEN 'version' THEN
					SET cfDataType  := 'UNSIGNED INTEGER';
					SET cfAlias     := CONCAT('v', cfId);
					SET rtSqlSelect := CONCAT(rtSqlSelect, ',', cfAlias, '.name AS "', cfName,'"');

					SET cfName      := CONCAT(cfName, '_id');
					SET rtSqlFrom   := CONCAT(rtSqlFrom, ' LEFT JOIN versions AS ', cfAlias, ' ON rt.', cfName, '=', cfAlias, '.id');
				ELSE
					SET cfDataType := 'CHAR(255)';
			END CASE;
		END IF;

		SET ttSqlSelect := CONCAT(ttSqlSelect,
			',CAST(GROUP_CONCAT(IF(custom_field_id=', cfId, ',value,NULL)) AS ', cfDataType,') AS "', cfName, '"'
		);
	END LOOP cfLoop;
	CLOSE cfCursor;

	-- create custom values temp table
	-- (this should be faster, than doing it all together, as it is only queries c_v table)
	SET sqlQ := CONCAT('DROP TABLE IF EXISTS ', tempTable);
	CALL ExecuteSQL(sqlQ);
	SET sqlQ := CONCAT('CREATE TEMPORARY TABLE ', tempTable,
		' SELECT customized_id AS id', ttSqlSelect,
		' FROM custom_values WHERE customized_type = "', customizedType, '" GROUP BY customized_id;'
	);
	CALL ExecuteSQL(sqlQ);

	-- create reportTable
	SET sqlQ := CONCAT('DROP TABLE IF EXISTS ', reportTable);
	CALL ExecuteSQL(sqlQ);
	SET sqlQ := CONCAT('CREATE TABLE ', reportTable,
		' SELECT rt.*', rtSqlSelect,
		' FROM (SELECT * FROM ', baseTable, ' CROSS JOIN ', tempTable, ' USING (id)) AS rt', rtSqlFrom
	);
	CALL ExecuteSQL(sqlQ);

	-- TODO: add indexes

	-- clean up
	SET sqlQ := CONCAT('DROP TABLE IF EXISTS ', tempTable);
	CALL ExecuteSQL(sqlQ);
END thisProc;
//

-- requires event_scheduler set to ON
--  /etc/mysql/my.cnf (or ~/.my.cnf) [mysqld] event_scheduler = ON
--  OR --event-scheduler=ON as a command-line parameter
--  OR SET GLOBAL event_scheduler = ON; at mysql prompt (lost on restart thought)
CREATE EVENT redmine_DenormalizeTables
	ON SCHEDULE
		EVERY 1 DAY
		STARTS '2015-02-03 01:00:00'
	DO
		CALL redmine_DenormalizeTable('issues');
		CALL redmine_DenormalizeTable('projects');
		CALL redmine_DenormalizeTable('versions');
		CALL redmine_DenormalizeTable('users');
//


DELIMITER ;

