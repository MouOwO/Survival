-- Explicit staging switch. No live server or public endpoint is assumed.
-- A reviewed release must pin its real worker endpoints and gameplay build.
return {
    enabled = false,
    base_url = "https://pay.xiaofengnet.com/ws4-web",
    expected_map = "ws4_lobby",
    match_build_sha256 = "",
    connect_addresses = {},
}
