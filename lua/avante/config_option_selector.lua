--- Config Option Selector
---
--- Picker UI for ACP config options (mode, model, thought_level, etc.)
--- Falls back to legacy session modes if configOptions not available.

local Utils = require("avante.utils")
local Config = require("avante.config")

---@class avante.ConfigOptionSelector
local M = {}

---Open the config option selector
---@param opts? { category?: string }
function M.open(opts)
  opts = opts or {}
  local sidebar = require("avante").get()
  if not sidebar then
    Utils.warn("No Avante sidebar found")
    return
  end

  local acp_client = sidebar.acp_client
  if not acp_client then
    Utils.warn("No ACP connection active")
    return
  end

  -- Prefer configOptions over legacy modes
  if acp_client:has_config_options() then
    M._open_config_options(sidebar, acp_client, opts.category)
  elseif acp_client:has_modes() then
    M._open_legacy_modes(sidebar, acp_client)
  else
    Utils.info("Agent does not provide config options or modes")
  end
end

---Open selector for configOptions
---@param sidebar table
---@param acp_client table
---@param category? string
function M._open_config_options(sidebar, acp_client, category)
  local config_options = acp_client:all_config_options()

  -- If category specified, filter to that category
  local filtered = config_options
  if category then
    filtered = vim.tbl_filter(function(opt) return opt.category == category end, config_options)
    if #filtered == 0 then
      Utils.warn("No config options with category: " .. category)
      return
    end
  end

  -- If single option (or single after filter), go straight to value picker
  if #filtered == 1 then
    M._pick_option_value(sidebar, acp_client, filtered[1])
    return
  end

  -- Multiple options: pick which option to configure
  vim.ui.select(filtered, {
    prompt = "Agent Options",
    format_item = function(opt)
      local current_label = opt.currentValue
      -- Find the display name for the current value
      for _, val in ipairs(opt.options) do
        if val.value == opt.currentValue then
          current_label = val.name
          break
        end
      end
      local prefix = opt.category and ("[" .. opt.category .. "] ") or ""
      return prefix .. opt.name .. ": " .. current_label
    end,
  }, function(selected)
    if not selected then return end
    M._pick_option_value(sidebar, acp_client, selected)
  end)
end

---Pick a value for a specific config option
---@param sidebar table
---@param acp_client table
---@param opt avante.acp.ConfigOption
function M._pick_option_value(sidebar, acp_client, opt)
  vim.ui.select(opt.options, {
    prompt = opt.name,
    format_item = function(val)
      local current = val.value == opt.currentValue and " (current)" or ""
      local desc = val.description and (" — " .. val.description) or ""
      return val.name .. current .. desc
    end,
  }, function(selected)
    if not selected then return end
    if selected.value == opt.currentValue then return end

    local session_id = sidebar.chat_history and sidebar.chat_history.acp_session_id
    if not session_id then
      Utils.warn("No active session")
      return
    end

    acp_client:set_config_option(session_id, opt.id, selected.value, function(result, err)
      if err then
        vim.schedule(function()
          Utils.warn("Failed to set " .. opt.name .. ": " .. tostring(err.message or err))
        end)
      else
        vim.schedule(function()
          Utils.info(opt.name .. ": " .. selected.name)
          sidebar:render_result()
          sidebar:show_input_hint()
        end)
      end
    end)
  end)
end

---Fallback: open selector for legacy session modes
---@param sidebar table
---@param acp_client table
function M._open_legacy_modes(sidebar, acp_client)
  local modes = acp_client:all_modes()
  local current_mode = acp_client:current_mode()

  vim.ui.select(modes, {
    prompt = "Session Mode",
    format_item = function(mode)
      local current = mode.id == current_mode and " (current)" or ""
      local desc = mode.description and (" — " .. mode.description) or ""
      return mode.name .. current .. desc
    end,
  }, function(selected)
    if not selected then return end
    if selected.id == current_mode then return end

    local session_id = sidebar.chat_history and sidebar.chat_history.acp_session_id
    if not session_id then
      Utils.warn("No active session")
      return
    end

    acp_client:set_mode(session_id, selected.id, function(result, err)
      if err then
        if err.message and err.message:match("Method not found") then
          vim.schedule(function() Utils.info("Mode: " .. selected.name .. " (local only)") end)
        else
          vim.schedule(function() Utils.warn("Failed to set mode: " .. tostring(err.message)) end)
        end
      else
        vim.schedule(function()
          Utils.info("Mode: " .. selected.name)
          sidebar:render_result()
          sidebar:show_input_hint()
        end)
      end
    end)
  end)
end

return M
