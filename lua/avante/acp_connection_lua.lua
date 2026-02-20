--- Lua ACP Backend Adapter
---
--- Wraps the existing lua/avante/libs/acp_client.lua to conform to
--- the avante.AcpConnection interface. Pure delegation — no behavioral changes.

local ACPClient = require("avante.libs.acp_client")

---@class avante.AcpConnectionLua : avante.AcpConnection
---@field _client avante.acp.ACPClient
local LuaConnection = {}
LuaConnection.__index = LuaConnection

---@param config ACPConfig
---@return avante.AcpConnectionLua
function LuaConnection:new(config)
  local obj = setmetatable({
    _client = ACPClient:new(config),
  }, LuaConnection)
  return obj
end

---@param callback fun(err: avante.acp.ACPError|nil)
function LuaConnection:connect(callback)
  self._client:connect(callback)
end

function LuaConnection:disconnect()
  self._client:stop()
end

---@return boolean
function LuaConnection:is_connected()
  return self._client:is_connected()
end

---@return boolean
function LuaConnection:is_ready()
  return self._client:is_ready()
end

---@return ACPConnectionState
function LuaConnection:get_state()
  return self._client:get_state()
end

---@param cwd string
---@param mcp_servers table[]
---@param callback fun(session_id: string|nil, err: avante.acp.ACPError|nil)
function LuaConnection:create_session(cwd, mcp_servers, callback)
  self._client:create_session(cwd, mcp_servers, callback)
end

---@param session_id string
---@param cwd string
---@param mcp_servers table[]
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function LuaConnection:load_session(session_id, cwd, mcp_servers, callback)
  self._client:load_session(session_id, cwd, mcp_servers, callback)
end

---@param session_id string
---@param prompt table[]
---@param mode_id string|nil
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function LuaConnection:send_prompt(session_id, prompt, mode_id, callback)
  self._client:send_prompt(session_id, prompt, mode_id, callback)
end

---@param session_id string
function LuaConnection:cancel_session(session_id)
  self._client:cancel_session(session_id)
end

---@param callback fun(sessions: table[]|nil, err: avante.acp.ACPError|nil)
function LuaConnection:list_sessions(callback)
  self._client:list_sessions(callback)
end

---@param session_id string
---@param mode_id string
---@param callback fun(result: table|nil, err: avante.acp.ACPError|nil)
function LuaConnection:set_mode(session_id, mode_id, callback)
  self._client:set_mode(session_id, mode_id, callback)
end

---@return boolean
function LuaConnection:has_modes()
  return self._client:has_modes()
end

---@return avante.acp.SessionMode[]
function LuaConnection:all_modes()
  return self._client:all_modes()
end

---@return string|nil
function LuaConnection:current_mode()
  return self._client:current_mode()
end

---@param mode_id string
---@return avante.acp.SessionMode|nil
function LuaConnection:mode_by_id(mode_id)
  return self._client:mode_by_id(mode_id)
end

---@param handlers ACPHandlers
function LuaConnection:set_handlers(handlers)
  self._client.config.handlers = handlers
end

---@return boolean
function LuaConnection:supports_load_session()
  return self._client.agent_capabilities ~= nil and self._client.agent_capabilities.loadSession == true
end

--- Proxy the on_mode_changed callback to the underlying client
---@param callback fun(mode_id: string)|nil
function LuaConnection:set_on_mode_changed(callback)
  self._client.on_mode_changed = callback
end

--- Access to agent capabilities for external inspection
---@return avante.acp.AgentCapabilities|nil
function LuaConnection:get_agent_capabilities()
  return self._client.agent_capabilities
end

--- Access to underlying client (escape hatch for features not yet abstracted)
---@return avante.acp.ACPClient
function LuaConnection:raw_client()
  return self._client
end

return LuaConnection
