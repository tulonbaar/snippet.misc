SELECT
    s.sid,
    s.serial#,
    s.username,
    s.module,
    so.opname,
    so.target,
    ROUND(so.elapsed_seconds / 60, 2) AS "ELAPSED_TIME_MIN",
    ROUND(so.time_remaining / 60, 2) AS "REMAINING_MIN",
    ROUND(so.sofar / so.totalwork * 100, 2) AS "PROGRESS_%",
    sq.sql_text
FROM
    v$session s
JOIN
    v$session_longops so ON s.sid = so.sid AND s.serial# = so.serial#
LEFT JOIN
    v$sql sq ON so.sql_id = sq.sql_id
WHERE
    so.time_remaining > 0
ORDER BY
    so.elapsed_seconds DESC;

--Column descriptions:
-- SID, SERIAL#: Session identifiers.
-- USERNAME: Name of the user performing the operation.
-- MODULE: Module or application from which the query originates.
-- OPNAME: Name of the operation being performed (e.g., Table Scan).
-- TARGET: Object on which the operation is being performed.
-- ELAPSED_TIME_MIN: Duration of the operation in minutes.
-- REMAINING_MIN: Estimated remaining time in minutes.
-- PROGRESS_%: Percentage progress of the operation.
-- SQL_TEXT: Full text of the SQL query.