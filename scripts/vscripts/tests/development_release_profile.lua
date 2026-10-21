-- Explicit local fixture for tests that intentionally exercise developer APIs.
-- This module is excluded from the staged public addon.
package.loaded["config/release_profile"] = { channel = "development" }
if type(IsServer) ~= "function" then IsServer = function() return true end end
if type(IsInToolsMode) ~= "function" then IsInToolsMode = function() return true end end
return package.loaded["config/release_profile"]
