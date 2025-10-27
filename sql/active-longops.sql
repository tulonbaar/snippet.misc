SELECT
    s.sid,
    s.serial#,
    s.username,
    s.module,
    so.opname,
    so.target,
    ROUND(so.elapsed_seconds / 60, 2) AS "CZAS_TRWANIA_MIN",
    ROUND(so.time_remaining / 60, 2) AS "POZOSTALO_MIN",
    ROUND(so.sofar / so.totalwork * 100, 2) AS "POSTEP_%",
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

--Opis kolumn:
-- SID, SERIAL#: Identyfikatory sesji.
-- USERNAME: Nazwa użytkownika wykonującego operację.
-- MODULE: Moduł lub aplikacja, z której pochodzi zapytanie.
-- OPNAME: Nazwa wykonywanej operacji (np. Table Scan).
-- TARGET: Obiekt, na którym wykonywana jest operacja.
-- CZAS_TRWANIA_MIN: Czas trwania operacji w minutach.
-- POZOSTALO_MIN: Szacowany pozostały czas w minutach.
-- POSTEP_%: Procentowy postęp operacji.
-- SQL_TEXT: Pełny tekst zapytania SQL.