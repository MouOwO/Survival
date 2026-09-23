-- Only for rolling the stopped API back to a release with the old RPC allowlist.
-- Run as the existing migration owner in goufayu_test. Keep the new table,
-- immutable baselines and migration ledger; no account data is rewritten.
BEGIN;
REVOKE ALL ON FUNCTION public.match_profile_context(text,text),
 public.match_profile_login(text,text,text,jsonb) FROM goufayu_app;
COMMIT;
-- Before activating the new API again, apply harden_match_sessions.sql as owner
-- and run the new adapter ready probe. A ledger row alone does not restore grants.
