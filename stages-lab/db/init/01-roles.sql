-- Runs once, when the data directory is empty, as the superuser.
--
-- Two roles on purpose: the POSTGRES_USER above owns the schema and runs the
-- migrations; the role created here is the only one the application ever
-- connects with. Its table grants are set by the initial migration, once the
-- tables exist — here we only create it and make sure it cannot create its own.
-- psql does not import the environment on its own: every value used below has
-- to be pulled in with \set first.
\set app_role `echo "$APP_DB_ROLE"`
\set app_password `echo "$APP_DB_PASSWORD"`
\set db_name `echo "$POSTGRES_DB"`

CREATE ROLE :"app_role" WITH LOGIN PASSWORD :'app_password';

-- It may read and write what it is granted, and nothing else: no schema
-- creation, no new tables to quietly park data in.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db_name" TO :"app_role";
