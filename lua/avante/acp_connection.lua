--- ACP Connection Interface + Factory
---
--- Defines the contract that both Lua and Rust ACP backends must implement.
--- Modeled after Zed's AgentConnection trait (crates/acp_thread/src/connection.rs).
---
--- Usage:
---   local AcpConnection = require("avante.acp_connection")
---   local conn = AcpConnection.create(provider_config)
---   conn:connect(function(err) ... end)

local Config = require("avante.config")
local Utils = require("avante.utils")

local M = {}

---@class avante.AcpConnection
---@field connect fun(self: avante.AcpConnection, callback: fun(err: avante.acp.ACPError|nil))
---@field disconnect fun(self: avante.AcpConnection)
---@field is_connected fun(self: avante.AcpConnection): boolean
---@field is_ready fun(self: avante.AcpConnection): boolean
---@field get_state fun(self: avante.AcpConnection): ACPConnectionState
---@field create_session fun(self: avante.AcpConnection, cwd: string, mcp_servers: table[], callback: fun(session_id: string|nil, err: avante.acp.ACPError|nil))
---@field load_session fun(self: avante.AcpConnection, session_id: string, cwd: string, mcp_servers: table[], callback: fun(result: table|nil, err: avante.acp.ACPError|nil))
---@field send_prompt fun(self: avante.AcpConnection, session_id: string, prompt: table[], mode_id: string|nil, callback: fun(result: table|nil, err: avante.acp.ACPError|nil))
---@field cancel_session fun(self: avante.AcpConnection, session_id: string)
---@field list_sessions fun(self: avante.AcpConnection, callback: fun(sessions: table[]|nil, err: avante.acp.ACPError|nil))
---@field set_mode fun(self: avante.AcpConnection, session_id: string, mode_id: string, callback: fun(result: table|nil, err: avante.acp.ACPError|nil))
---@field has_modes fun(self: avante.AcpConnection): boolean
---@field all_modes fun(self: avante.AcpConnection): avante.acp.SessionMode[]
---@field current_mode fun(self: avante.AcpConnection): string|nil
---@field mode_by_id fun(self: avante.AcpConnection, mode_id: string): avante.acp.SessionMode|nil
---@field set_handlers fun(self: avante.AcpConnection, handlers: ACPHandlers)
---@field supports_load_session fun(self: avante.AcpConnection): boolean
---@field on_mode_changed fun(mode_id: string)|nil Callback set by consumer when mode changes
---@field agent_capabilities avante.acp.AgentCapabilities|nil

--- Content block helpers (shared across backends)
---@param text string
---@param annotations table|nil
---@return avante.acp.TextContent
function M.create_text_content(text, annotations)
  return { type = "text", text = text, annotations = annotations }
end

---@param data string Base64 encoded image data
---@param mime_type string
---@param uri string|nil
---@param annotations table|nil
---@return avante.acp.ImageContent
function M.create_image_content(data, mime_type, uri, annotations)
  return { type = "image", data = data, mimeType = mime_type, uri = uri, annotations = annotations }
end

---@param uri string
---@param name string
---@param description string|nil
---@param mime_type string|nil
---@param size number|nil
---@param title string|nil
---@param annotations table|nil
---@return avante.acp.ResourceLinkContent
function M.create_resource_link_content(uri, name, description, mime_type, size, title, annotations)
  return {
    type = "resource_link",
    uri = uri,
    name = name,
    description = description,
    mimeType = mime_type,
    size = size,
    title = title,
    annotations = annotations,
  }
end

---@param resource avante.acp.EmbeddedResource
---@param annotations table|nil
---@return avante.acp.ResourceContent
function M.create_resource_content(resource, annotations)
  return { type = "resource", resource = resource, annotations = annotations }
end

---@param uri string
---@param text string
---@param mime_type string|nil
---@return avante.acp.EmbeddedResource
function M.create_text_resource(uri, text, mime_type)
  return { uri = uri, text = text, mimeType = mime_type }
end

--- Create a connection instance using the configured backend.
---@param provider_config ACPConfig
---@return avante.AcpConnection
function M.create(provider_config)
  local use_rust = Config.acp_backend == "rust"

  if use_rust then
    local ok, _ = pcall(require, "avante_acp")
    if not ok then
      Utils.warn("avante-acp native module not found, falling back to Lua backend")
      use_rust = false
    end
  end

  if use_rust then
    return require("avante.acp_connection_rust"):new(provider_config)
  else
    return require("avante.acp_connection_lua"):new(provider_config)
  end
end

return M
