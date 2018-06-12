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
CREATE TEMPORARY TABLE _workflow_permissions
SELECT
	CONCAT_WS(':', LPAD(r.position, 2, 0), LPAD(r.id, 2, 0), r.name) AS role,
	CONCAT_WS(':', LPAD(t.position, 2, 0), LPAD(t.id, 2, 0), t.name) AS tracker,
	CONCAT_WS(':', LPAD(s.position, 2, 0), LPAD(s.id, 2, 0), s.name) AS status,
	CONCAT_WS(':', LPAD(f.position, 2, 0), LPAD(f.id, 2, 0), f.name) AS field,
	'optional'                                                       AS rule,
	4                                                                AS rule_precedence,
	r.position                                                       AS r_pos,
	r.id                                                             AS r_id,
	r.name                                                           AS r_name,
	t.position                                                       AS t_pos,
	t.id                                                             AS t_id,
	t.name                                                           AS t_name,
	s.position                                                       AS s_pos,
	s.id                                                             AS s_id,
	s.name                                                           AS s_name,
	s.is_closed                                                      AS s_closed,
	f.position                                                       AS f_pos,
	f.id                                                             AS f_id,
	f.name                                                           AS f_name,
	f.type                                                           AS f_type
FROM roles       AS r,
	trackers       AS t,
	issue_statuses AS s,
	(
		SELECT position,      id, name, 'standard' AS type FROM _standard_fields
		UNION
		SELECT position + 20, id, name, 'custom'           FROM custom_fields
		WHERE type = 'IssueCustomField'
	)              AS f
;

-- add indexes to speed up joins
ALTER TABLE _workflow_permissions
	ADD INDEX (f_id),
	ADD INDEX (f_name),
	ADD INDEX (f_type),
	ADD INDEX (r_id),
	ADD INDEX (r_name),
	ADD INDEX (rule_precedence),
	ADD INDEX (rule),
	ADD INDEX (s_id),
	ADD INDEX (t_id),
	ADD INDEX (r_id, t_id, f_type, f_id)
;

-- optional -> required

-- required standard fields
UPDATE _workflow_permissions  AS p
	INNER JOIN _standard_fields AS f ON p.f_id = f.id
SET p.rule              = 'required'
WHERE p.f_type          = 'standard'
	AND f.is_required     = 1
;

-- required custom fields
UPDATE _workflow_permissions AS p
	INNER JOIN custom_fields   AS f ON p.f_id = f.id
SET p.rule              = 'required'
WHERE p.f_type          = 'custom'
	AND f.is_required     = 1
	AND f.type            = 'IssueCustomField'
;

-- optional -> required
--          -> readonly
-- required -> readonly

-- readonly and required standard fields
UPDATE _workflow_permissions AS p
	INNER JOIN workflows       AS w
		ON p.r_id = w.role_id AND p.t_id = w.tracker_id AND p.s_id = w.old_status_id
SET p.rule     = w.rule
WHERE w.type   = 'WorkflowPermission'
	AND p.f_type = 'standard'
	AND p.f_name = w.field_name
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

-- optional -> hidden
-- required -> hidden
-- readonly -> hidden

-- hidden (custom) fields (per role)
UPDATE _workflow_permissions    AS p
	INNER JOIN custom_fields      AS f ON p.f_id = f.id
	LEFT JOIN custom_fields_roles AS r
		ON p.f_id = r.custom_field_id AND p.r_id = r.role_id
SET p.rule              = 'hidden'
WHERE p.f_type          = 'custom'
	AND f.type            = 'IssueCustomField'
	AND f.visible         = 0
	AND r.custom_field_id IS NULL
;

-- optional -> disabled
-- required -> disabled
-- readonly -> disabled
-- hidden   -> disabled

-- disabled standard fields (per tracker)
UPDATE _workflow_permissions  AS p
	INNER JOIN trackers         AS t ON p.t_id = t.id
	INNER JOIN _standard_fields AS f ON p.f_id = f.id
SET p.rule                            = 'disabled'
WHERE p.f_type                        = 'standard'
	AND f.disable_bit                   > 0
	AND (t.fields_bits & f.disable_bit) > 0
;

-- disabled custom fields (per tracker)
UPDATE _workflow_permissions       AS p
	LEFT JOIN custom_fields_trackers AS f
		ON p.f_id = f.custom_field_id AND p.t_id = f.tracker_id
SET p.rule              = 'disabled'
WHERE p.f_type          = 'custom'
	AND f.custom_field_id IS NULL
;

-- update rule precedence
UPDATE _workflow_permissions SET rule_precedence = 0 WHERE rule = 'disabled';
UPDATE _workflow_permissions SET rule_precedence = 1 WHERE rule = 'hidden';
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
