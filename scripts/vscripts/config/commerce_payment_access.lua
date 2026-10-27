-- A separately reviewed cloud release may enable authenticated native checkout.
-- Keep false until original Arcade identity, WS4 profile readback and delivery
-- have passed acceptance. No merchant secret or global bearer belongs here.
return {
    enabled = false,
    connection_helper = false,
    expected_map = "template_map",
    base_url = "https://pay.xiaofengnet.com/ws4-web",
}
