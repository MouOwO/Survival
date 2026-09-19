-- Run as the administrator of the NEW PostgreSQL 17 target only.
-- No passwords are embedded here. Provision login passwords separately through
-- a mode-0600 psql variables file or the deployment secret manager.
-- The current database must already exist and be dedicated to this application.
\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(719232014003);
DO $roles$
DECLARE item record; existing record;
BEGIN
 IF current_setting('server_version_num')::integer / 10000 <> 17 THEN
  RAISE EXCEPTION 'postgresql_17_required';
 END IF;
 IF current_database() !~ '^(goufayu_test|goufayu_restore_[a-z0-9_]{1,48})$' THEN
  RAISE EXCEPTION 'bootstrap_database_name_refused';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
    WHERE NOT ((e.extname='plpgsql' AND n.nspname='pg_catalog')
      OR (e.extname='pgcrypto' AND n.nspname IN ('public','extensions')))) THEN
  RAISE EXCEPTION 'bootstrap_unknown_extension';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname !~ '^pg_'
    AND nspname NOT IN ('information_schema','public','extensions')) THEN
  RAISE EXCEPTION 'bootstrap_unknown_schema';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND c.relkind IN ('r','p','v','m','S','f')) THEN
  RAISE EXCEPTION 'bootstrap_requires_empty_target';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
    AND NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_extension e ON e.oid=d.refobjid
      WHERE d.classid='pg_proc'::regclass AND d.refclassid='pg_extension'::regclass
      AND d.objid=p.oid AND d.deptype='e' AND e.extname IN ('pgcrypto','plpgsql'))) THEN
  RAISE EXCEPTION 'bootstrap_requires_no_business_functions';
 END IF;
 FOR item IN SELECT * FROM (VALUES
   ('goufayu_owner',false), ('goufayu_migrator',true), ('goufayu_app',true),
   ('anon',false), ('authenticated',false), ('service_role',false)
 ) AS roles(name,login) LOOP
  SELECT * INTO existing FROM pg_roles WHERE rolname=item.name;
  IF NOT FOUND THEN
   EXECUTE format('CREATE ROLE %I %s NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
     item.name,CASE WHEN item.login THEN 'LOGIN' ELSE 'NOLOGIN' END);
  ELSIF existing.rolsuper OR existing.rolcreatedb OR existing.rolcreaterole
     OR existing.rolreplication OR existing.rolbypassrls
     OR existing.rolcanlogin <> item.login THEN
   RAISE EXCEPTION 'existing_role_attributes_unexpected: %',item.name;
  END IF;
 END LOOP;
 IF EXISTS (SELECT 1 FROM pg_auth_members WHERE member=(SELECT oid FROM pg_roles WHERE rolname='goufayu_app')) THEN
  RAISE EXCEPTION 'application_role_membership';
 END IF;
END $roles$;
GRANT goufayu_owner TO goufayu_migrator WITH INHERIT FALSE, SET TRUE;
-- Keep newly created functions inaccessible to the app until final hardening
-- grants schema USAGE together with its explicit RPC allowlist.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
ALTER SCHEMA public OWNER TO goufayu_owner;
DO $database$
BEGIN
 EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC',current_database());
 EXECUTE format('GRANT CONNECT ON DATABASE %I TO goufayu_migrator,goufayu_app',current_database());
 EXECUTE format('GRANT CREATE ON DATABASE %I TO goufayu_owner',current_database());
END $database$;
COMMIT;
