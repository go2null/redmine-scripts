DROP TABLE IF EXISTS _standard_fields;
CREATE TABLE _standard_fields (
	id          INT(11)  AUTO_INCREMENT PRIMARY KEY,
	name        VARCHAR(30) NOT NULL,
	is_required TINYINT(1)  UNSIGNED NOT NULL DEFAULT 0,
	position    INT(11)  NOT NULL,
	disable_bit TINYINT(3)  UNSIGNED NOT NULL DEFAULT 0,
	INDEX (disable_bit)
);
INSERT INTO _standard_fields
		(name,                is_required,  position,  disable_bit)
	VALUES
		('project_id',        1,            1,         0),
		('tracker_id',        1,            2,         0),
		('subject',           1,            3,         0),
		('description',       0,            4,         0),
		('priority_id',       1,            5,         0),
		('is_private',        1,            6,         0),
		('assigned_to_id',    0,            7,         1),
		('category_id',       0,            8,         2),
		('fixed_version_id',  0,            9,         4),
		('parent_issue_id',   0,            10,        8),
		('start_date',        0,            11,        16),
		('due_date',          0,            12,        32),
		('estimated_hours',   0,            13,        64),
		('done_ratio',        0,            14,        128)
;
