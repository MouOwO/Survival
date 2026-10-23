local ok, result = pcall(function() return require("ws4_local_launcher/status")() end)
if not ok then result={status="probe_failed"} end
print("WS4_LOCAL_STATUS:"..require("core/json_encoder").encode(result))
