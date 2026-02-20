local Utils = require("avante.utils")

local M = {}

--- Tool titles from ACP agents that indicate file writes
M.ACP_WRITE_TOOL_TITLES = {
  "Write",
  "Edit",
  "Create",
  "write_to_file",
  "str_replace",
  "replace_in_file",
  "insert",
  "create",
  "edit_file",
}

--- Called from track_edited_file; schedules a loclist refresh
---@param abs_path string
---@param session_ctx table
---@param tool_name? string
function M.on_file_edited(abs_path, session_ctx, tool_name)
  vim.schedule(function() M._refresh_loclist(session_ctx) end)
end

--- Rebuild the location list from session_ctx
---@param session_ctx table
function M._refresh_loclist(session_ctx)
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.code or not vim.api.nvim_win_is_valid(sidebar.code.winid) then return end

  local file_snapshots = session_ctx.file_snapshots or {}
  local file_order = session_ctx.edited_files_order or {}

  local items = {}
  for _, abs_path in ipairs(file_order) do
    local old_content = file_snapshots[abs_path] or ""
    local ok, new_lines = pcall(vim.fn.readfile, abs_path)
    local new_content = (ok and new_lines) and table.concat(new_lines, "\n") or ""

    local additions, deletions = 0, 0
    if old_content ~= new_content then
      local diff_text = vim.diff(old_content .. "\n", new_content .. "\n", { algorithm = "histogram" })
      if diff_text then
        for line in diff_text:gmatch("[^\n]+") do
          if line:match("^%+") and not line:match("^%+%+%+") then
            additions = additions + 1
          elseif line:match("^%-") and not line:match("^%-%-%-") then
            deletions = deletions + 1
          end
        end
      end
    end

    local rel_path = vim.fn.fnamemodify(abs_path, ":~:.")
    local text = string.format("+%d -%d", additions, deletions)
    table.insert(items, {
      filename = abs_path,
      lnum = 1,
      col = 1,
      text = text,
      type = "",
    })
  end

  vim.fn.setloclist(sidebar.code.winid, items, "r")
  vim.fn.setloclist(sidebar.code.winid, {}, "a", {
    title = "Avante: Changed Files (" .. #items .. ")",
  })
end

--- Open the location list window
function M.open()
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.code or not vim.api.nvim_win_is_valid(sidebar.code.winid) then
    Utils.error("No sidebar found")
    return
  end
  local items = vim.fn.getloclist(sidebar.code.winid)
  if #items == 0 then
    Utils.info("No files changed in this session")
    return
  end
  vim.api.nvim_set_current_win(sidebar.code.winid)
  vim.cmd("lopen")
end

--- Clear the location list
function M.clear()
  local sidebar = require("avante").get()
  if not sidebar or not sidebar.code then return end
  if not vim.api.nvim_win_is_valid(sidebar.code.winid) then return end
  pcall(vim.fn.setloclist, sidebar.code.winid, {}, "r")
end

return M
