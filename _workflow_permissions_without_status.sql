-- Summarize (remove Status)

DROP TABLE IF EXISTS _tmp_export
;
CREATE TEMPORARY TABLE _tmp_export
SELECT role, tracker, field,
	'optional'           AS rule,
	MAX(rule_precedence) AS rule_precedence
FROM _workflow_permissions
WHERE r_name <> 'ADMIN'
GROUP BY r_id, t_id, f_type, f_id
;
ALTER TABLE _tmp_export ADD INDEX (rule_precedence)
;
UPDATE _tmp_export
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
-- SELECT * FROM _tmp_export;

-- exit;
SELECT 'tracker', 'field', 'role', 'rule_precedence', 'rule'
UNION
SELECT tracker, field, role, rule_precedence, rule
FROM _tmp_export
INTO OUTFILE '/tmp/workflow-permissions-summary-without-status.csv'
	FIELDS TERMINATED BY ',' ENCLOSED BY '"'
	LINES  TERMINATED BY '\n'
;
