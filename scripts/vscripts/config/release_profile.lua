-- The release builder checks this trusted, server-side profile.
-- Local testing is explicitly enabled at the owner's request on 2026-10-22.
-- Developer commands still require a server running in Workshop Tools.
-- The public release builder rejects this profile until it is production.
return {
    channel = "development",
}
