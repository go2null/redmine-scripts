-- Summarize (remove Status)

DROP TABLE IF EXISTS _workflow_permissions_without_status
;
CREATE TABLE _workflow_permissions_without_status
SELECT role, tracker, field,
	'optional'           AS rule,
	MAX(rule_precedence) AS rule_precedence
FROM _workflow_permissions
WHERE r_name <> 'ADMIN'
GROUP BY r_id, t_id, f_id
;
ALTER TABLE _workflow_permissions_without_status ADD INDEX (rule_precedence)
;
UPDATE _workflow_permissions_without_status
SET rule =
	CASE rule_precedence
		WHEN 0 THEN 'disabled'
		WHEN 1 THEN 'hidden'
		WHEN 2 THEN 'readonly'
		WHEN 3 THEN 'required'
		WHEN 4 THEN 'optional'
	END
;

-- exit;
SELECT * FROM _workflow_permissions_without_status;

-- exit;
SELECT 'tracker', 'field', 'role', 'rule_precedence', 'rule'
UNION
SELECT tracker, field, role, rule_precedence, rule
FROM _workflow_permissions_without_status
INTO OUTFILE '/tmp/export.csv'
	FIELDS TERMINATED BY ',' ENCLOSED BY '"'
	LINES  TERMINATED BY '\n'
;
