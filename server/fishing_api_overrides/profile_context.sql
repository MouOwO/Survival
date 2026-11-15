BEGIN;
-- Fresh isolated synthetic database only. No existing helper is replaced.
DO $scope$
BEGIN
 IF current_database()!~'^survival_loadtest_[0-9a-f]{32}$'
    OR current_user<>'postgres' OR session_user<>'postgres'
    OR to_regprocedure('public.archive_profile_context(text,text)') IS NOT NULL
    OR to_regprocedure('public.archive_online_pending(text,text)') IS NULL
    OR to_regprocedure('public.archive_pending(text)') IS NULL
    OR to_regprocedure('public.get_fishing_profile(text)') IS NULL THEN
  RAISE EXCEPTION 'profile_context_fresh_isolated_scope_required';
 END IF;
END
$scope$;
CREATE FUNCTION public.archive_profile_context(p_account text,p_hash text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'pg_catalog','public','extensions','pg_temp'
 AS $profile_context$
DECLARE v_online jsonb;v_pending jsonb;v_profile jsonb;
BEGIN
 IF p_account IS NULL OR p_account!~'^[0-9a-f]{64}$'
    OR p_hash IS NULL OR p_hash!~'^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'profile_context_arguments_invalid';
 END IF;
 v_online:=public.archive_online_pending(p_account,p_hash);
 IF jsonb_typeof(v_online) IS DISTINCT FROM 'array' OR jsonb_array_length(v_online)>64 THEN
  RAISE EXCEPTION 'profile_context_dependency_invalid';
 END IF;
 IF jsonb_array_length(v_online)>0 THEN
  RETURN jsonb_build_object('online',v_online,'pending',NULL,'profile',NULL);
 END IF;
 v_pending:=public.archive_pending(p_account);
 IF jsonb_typeof(v_pending) IS DISTINCT FROM 'array' OR jsonb_array_length(v_pending)>64 THEN
  RAISE EXCEPTION 'profile_context_dependency_invalid';
 END IF;
 IF jsonb_array_length(v_pending)>0 THEN
  RETURN jsonb_build_object('online',v_online,'pending',v_pending,'profile',NULL);
 END IF;
 v_profile:=public.get_fishing_profile(p_account);
 RETURN jsonb_build_object('online',v_online,'pending',v_pending,'profile',v_profile);
END
$profile_context$;
REVOKE ALL ON FUNCTION public.archive_profile_context(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_profile_context(text,text) TO goufayu_app;
COMMIT;
