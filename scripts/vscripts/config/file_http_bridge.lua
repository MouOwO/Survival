-- Temporary transport for the existing closed test. No player/server secrets.
-- This does not authenticate players; the original PWA/backend checks remain.
return {
    enabled = true,
    protocol = 2,
    base_url = "https://pay.xiaofengnet.com/ws4-web",
    maximum_pending = 16,
    maximum_request_bytes = 262144,
    maximum_response_bytes = 8388608,
    outbound_chunk_bytes = 1024,
    inbound_chunk_bytes = 192,
    inbound_block_chunks = 16,
}
