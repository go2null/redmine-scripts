-- TABLE workflows has WorkflowPermissions and WorkflowTransitions
-- WorkflowPermissions: tracker_id, old_status_id, role_id, field_name, rule
-- WorkflowTransitions: tracker_id, old_status_id, new_status_id, role_id, assignee, author

-- rule_precedence: used for summaries
--   0 disabled
--   1 hidden
--   2 readonly
--   3 required
--   4 optional

-- get data from tables
DROP TABLE IF EXISTS _workflow_permissions
;
CREATE TABLE _workflow_permissions
SELECT
	r.position                                                       AS r_pos,
	r.id                                                             AS r_id,
	r.name                                                           AS r_name,
	CONCAT_WS(':', LPAD(r.position, 2, 0), LPAD(r.id, 2, 0), r.name) AS role,
	t.position                                                       AS t_pos,
	t.id                                                             AS t_id,
	t.name                                                           AS t_name,
	CONCAT_WS(':', LPAD(t.position, 2, 0), LPAD(t.id, 2, 0), t.name) AS tracker,
	s.position                                                       AS s_pos,
	s.id                                                             AS s_id,
	s.name                                                           AS s_name,
	s.is_closed                                                      AS s_closed,
	CONCAT_WS(':', LPAD(s.position, 2, 0), LPAD(s.id, 2, 0), s.name) AS status,
	f.position                                                       AS f_pos,
	f.id                                                             AS f_id,
	f.name                                                           AS f_name,
	f.type                                                           AS f_type,
	CONCAT_WS(':', LPAD(f.position, 2, 0), LPAD(f.id, 2, 0), f.name) AS field,
	4                                                                AS rule_precedence,
	'optional'                                                       AS rule
FROM roles       AS r,
	trackers       AS t,
	issue_statuses AS s,
	(
		SELECT position, id, name, 'custom' AS type
				FROM custom_fields WHERE type = 'IssueCustomField'
		UNION
		SELECT position, id, name, 'standard' FROM _standard_fields
	)              AS f
;

-- add indexes to speed up joins
ALTER TABLE _workflow_permissions
	ADD INDEX (f_id),
	ADD INDEX (f_name),
	ADD INDEX (f_type),
	ADD INDEX (r_id),
	ADD INDEX (rule),
	ADD INDEX (s_id),
	ADD INDEX (t_id)
;

-- disabled standard fields (per tracker)
UPDATE _workflow_permissions  AS p
	INNER JOIN trackers         AS t ON p.t_id = t.id
	INNER JOIN _standard_fields AS f ON p.f_id = f.id
SET p.rule                             = 'disabled',
	rule_precedence                      = 0
WHERE p.f_type                         = 'standard'
	AND f.disable_bit                    > 0
	AND (t.fields_bits & f.disable_bit) <> 0
;

-- disabled custom fields (per tracker)
UPDATE _workflow_permissions       AS p
	LEFT JOIN custom_fields_trackers AS f
		ON p.f_id = f.custom_field_id AND p.t_id = f.tracker_id
SET p.rule              = 'disabled',
	  rule_precedence     = 0
WHERE p.f_type          = 'custom'
	AND f.custom_field_id IS NULL
;

-- hidden (custom) fields (per role)
UPDATE _workflow_permissions    AS p
	INNER JOIN custom_fields      AS f ON p.f_id = f.id
	LEFT JOIN custom_fields_roles AS r
		ON p.f_id = r.custom_field_id AND p.r_id = r.role_id
SET p.rule              = 'hidden',
	  rule_precedence     = 1
WHERE p.f_type          = 'custom'
	AND f.visible         = 0
	AND r.custom_field_id IS NULL
;

-- readonly and required custom fields
UPDATE _workflow_permissions AS p
	INNER JOIN workflows       AS w
		ON p.r_id = w.role_id AND p.t_id = w.tracker_id AND p.s_id = w.old_status_id
SET p.rule     = w.rule
WHERE w.type   = 'WorkflowPermission'
	AND p.f_type = 'custom'
	AND p.f_id   = w.field_name
;

-- readonly and required standard fields
UPDATE _workflow_permissions AS p
	INNER JOIN workflows       AS w
		ON p.r_id = w.role_id AND p.t_id = w.tracker_id AND p.s_id = w.old_status_id
SET p.rule     = w.rule
WHERE w.type   = 'WorkflowPermission'
	AND p.f_type = 'standard'
	AND p.f_name = w.field_name
;

-- update rule precedence
UPDATE _workflow_permissions SET rule_precedence = 2 WHERE rule = 'readonly';
UPDATE _workflow_permissions SET rule_precedence = 3 WHERE rule = 'required';

exit;
SELECT * FROM _workflow_permissions;

exit;
SELECT * FROM _workflow_permissions
INTO OUTFILE '/tmp/export.csv'
	FIELDS TERMINATED BY ',' ENCLOSED BY '"'
	LINES  TERMINATED BY '\n'
;
