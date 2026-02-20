local Utils = require("avante.utils")
local Highlights = require("avante.highlights")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("avante-review")

---@class avante.ReviewHunk
---@field file_path string
---@field start_line integer -- 1-indexed line in review buffer
---@field end_line integer   -- 1-indexed line in review buffer
---@field old_start integer  -- original file line
---@field old_count integer
---@field new_start integer  -- new file line
---@field new_count integer
---@field old_lines string[]
---@field new_lines string[]
---@field status "pending"|"accepted"|"rejected"

---@class avante.ReviewState
---@field hunks avante.ReviewHunk[]
---@field files table<string, { old: string, new: string }>
---@field bufnr integer
---@field winid integer

--- Parse a unified diff hunk header
---@param line string
---@return integer old_start, integer old_count, integer new_start, integer new_count
local function parse_hunk_header(line)
  local os, oc, ns, nc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  os = tonumber(os) or 0
  oc = tonumber(oc) or 1
  ns = tonumber(ns) or 0
  nc = tonumber(nc) or 1
  return os, oc, ns, nc
end

--- Open the review buffer showing all agent changes
---@param session_ctx table
function M.open(session_ctx)
  local file_snapshots = session_ctx.file_snapshots or {}
  local edited_files = session_ctx.edited_files or {}

  if vim.tbl_isempty(edited_files) then
    Utils.info("No files were edited in this session")
    return
  end

  -- Collect diffs for all edited files
  local files = {}
  local file_order = {}
  for abs_path, _ in pairs(edited_files) do
    local old_content = file_snapshots[abs_path] or ""
    local current_lines = vim.fn.readfile(abs_path)
    local new_content = current_lines and table.concat(current_lines, "\n") or ""
    if old_content ~= new_content then
      files[abs_path] = { old = old_content, new = new_content }
      table.insert(file_order, abs_path)
    end
  end
  table.sort(file_order)

  if vim.tbl_isempty(files) then
    Utils.info("No changes detected")
    return
  end

  -- Build unified diff content and track hunks
  local buf_lines = {}
  local hunks = {}
  local total_additions = 0
  local total_deletions = 0

  for _, abs_path in ipairs(file_order) do
    local diff_data = files[abs_path]
    local rel_path = vim.fn.fnamemodify(abs_path, ":~:.")

    table.insert(buf_lines, "═══ " .. rel_path .. " ═══")
    table.insert(buf_lines, "")

    local diff_text = vim.diff(diff_data.old .. "\n", diff_data.new .. "\n", {
      algorithm = "histogram",
      ctxlen = 3,
    })

    if diff_text and diff_text ~= "" then
      local diff_lines = vim.split(diff_text, "\n")
      for _, dl in ipairs(diff_lines) do
        -- Skip file headers (--- / +++)
        if not dl:match("^%-%-%-") and not dl:match("^%+%+%+") then
          if dl:match("^@@") then
            -- Parse hunk header and start tracking
            local os_val, oc, ns, nc = parse_hunk_header(dl)
            table.insert(buf_lines, dl)
            local hunk = {
              file_path = abs_path,
              start_line = #buf_lines,
              end_line = #buf_lines, -- will be updated
              old_start = os_val,
              old_count = oc,
              new_start = ns,
              new_count = nc,
              old_lines = {},
              new_lines = {},
              status = "pending",
            }
            table.insert(hunks, hunk)
          else
            table.insert(buf_lines, dl)
            -- Track additions/deletions in current hunk
            local current_hunk = hunks[#hunks]
            if current_hunk then
              current_hunk.end_line = #buf_lines
              if dl:match("^%+") then
                total_additions = total_additions + 1
                table.insert(current_hunk.new_lines, dl:sub(2))
              elseif dl:match("^%-") then
                total_deletions = total_deletions + 1
                table.insert(current_hunk.old_lines, dl:sub(2))
              end
            end
          end
        end
      end
    end
    table.insert(buf_lines, "")
  end

  -- Add stats header
  local file_count = #file_order
  local header = string.format(
    "Review: %d file%s changed, +%d -%d  (a=accept, x=reject, A=all, X=reject all, ]c/[c=nav, q=close)",
    file_count,
    file_count > 1 and "s" or "",
    total_additions,
    total_deletions
  )
  table.insert(buf_lines, 1, header)
  table.insert(buf_lines, 2, string.rep("─", math.min(#header, 80)))
  table.insert(buf_lines, 3, "")

  -- Adjust hunk line numbers for the 3 header lines
  for _, hunk in ipairs(hunks) do
    hunk.start_line = hunk.start_line + 3
    hunk.end_line = hunk.end_line + 3
  end

  -- Create scratch buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "diff", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buf_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

  -- Open in a vertical split
  vim.cmd("vsplit")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_set_option_value("number", true, { win = winid })
  vim.api.nvim_set_option_value("wrap", false, { win = winid })

  -- Apply highlights
  M._highlight_diff(bufnr, buf_lines)

  -- Register keybindings
  local state = { hunks = hunks, files = files, bufnr = bufnr, winid = winid }
  M._register_keybindings(state, session_ctx)

  -- Jump to first hunk
  if #hunks > 0 then
    pcall(vim.api.nvim_win_set_cursor, winid, { hunks[1].start_line, 0 })
  end

  return state
end

--- Highlight diff lines in the review buffer
---@param bufnr integer
---@param lines string[]
function M._highlight_diff(bufnr, lines)
  for i, line in ipairs(lines) do
    local row = i - 1
    if line:match("^%+") and not line:match("^%+%+%+") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, NAMESPACE, "DiffAdd", row, 0, -1)
    elseif line:match("^%-") and not line:match("^%-%-%-") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, NAMESPACE, "DiffDelete", row, 0, -1)
    elseif line:match("^@@") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, NAMESPACE, "DiffChange", row, 0, -1)
    elseif line:match("^═══") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, NAMESPACE, "Title", row, 0, -1)
    elseif line:match("^Review:") then
      pcall(vim.api.nvim_buf_add_highlight, bufnr, NAMESPACE, "WarningMsg", row, 0, -1)
    end
  end
end

--- Find the hunk at the cursor position
---@param state avante.ReviewState
---@return avante.ReviewHunk|nil, integer|nil
function M._get_hunk_at_cursor(state)
  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  local row = cursor[1]
  for i, hunk in ipairs(state.hunks) do
    if row >= hunk.start_line and row <= hunk.end_line then
      return hunk, i
    end
  end
  -- If not directly on a hunk, find nearest
  for i, hunk in ipairs(state.hunks) do
    if row <= hunk.end_line then
      return hunk, i
    end
  end
  return nil, nil
end

--- Mark a hunk as accepted (dim it)
---@param state avante.ReviewState
---@param hunk avante.ReviewHunk
function M._accept_hunk(state, hunk)
  if hunk.status ~= "pending" then return end
  hunk.status = "accepted"
  -- Dim the hunk lines
  for row = hunk.start_line - 1, hunk.end_line - 1 do
    pcall(vim.api.nvim_buf_add_highlight, state.bufnr, NAMESPACE, "Comment", row, 0, -1)
  end
  Utils.info("Hunk accepted")
end

--- Reject a hunk (revert lines in actual file)
---@param state avante.ReviewState
---@param hunk avante.ReviewHunk
---@param session_ctx table
function M._reject_hunk(state, hunk, session_ctx)
  if hunk.status ~= "pending" then return end

  local file_snapshots = session_ctx.file_snapshots or {}
  local old_content = file_snapshots[hunk.file_path]
  if not old_content then
    Utils.error("No snapshot available for " .. hunk.file_path)
    return
  end

  -- Read old lines for the hunk range
  local old_file_lines = vim.split(old_content, "\n")
  local old_hunk_lines = {}
  for i = hunk.old_start, hunk.old_start + hunk.old_count - 1 do
    table.insert(old_hunk_lines, old_file_lines[i] or "")
  end

  -- Replace in the actual file buffer
  local bufnr = vim.fn.bufnr(hunk.file_path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(hunk.file_path)
    vim.fn.bufload(bufnr)
  end

  local new_start_0 = hunk.new_start - 1
  local new_end = hunk.new_start - 1 + hunk.new_count
  pcall(vim.api.nvim_buf_set_lines, bufnr, new_start_0, new_end, false, old_hunk_lines)
  vim.api.nvim_buf_call(bufnr, function() pcall(vim.cmd, "noautocmd write") end)

  hunk.status = "rejected"
  -- Strikethrough/dim the hunk
  for row = hunk.start_line - 1, hunk.end_line - 1 do
    pcall(vim.api.nvim_buf_add_highlight, state.bufnr, NAMESPACE, "DiagnosticUnnecessary", row, 0, -1)
  end
  Utils.info("Hunk rejected — reverted to original")
end

--- Jump to next/prev hunk
---@param state avante.ReviewState
---@param direction 1|-1
function M._jump_hunk(state, direction)
  local cursor = vim.api.nvim_win_get_cursor(state.winid)
  local row = cursor[1]

  if direction == 1 then
    for _, hunk in ipairs(state.hunks) do
      if hunk.start_line > row then
        pcall(vim.api.nvim_win_set_cursor, state.winid, { hunk.start_line, 0 })
        return
      end
    end
    -- Wrap to first
    if #state.hunks > 0 then
      pcall(vim.api.nvim_win_set_cursor, state.winid, { state.hunks[1].start_line, 0 })
    end
  else
    for i = #state.hunks, 1, -1 do
      if state.hunks[i].start_line < row then
        pcall(vim.api.nvim_win_set_cursor, state.winid, { state.hunks[i].start_line, 0 })
        return
      end
    end
    -- Wrap to last
    if #state.hunks > 0 then
      pcall(vim.api.nvim_win_set_cursor, state.winid, { state.hunks[#state.hunks].start_line, 0 })
    end
  end
end

--- Register keybindings for the review buffer
---@param state avante.ReviewState
---@param session_ctx table
function M._register_keybindings(state, session_ctx)
  local bufnr = state.bufnr

  -- Accept hunk
  vim.keymap.set("n", "a", function()
    local hunk = M._get_hunk_at_cursor(state)
    if hunk then M._accept_hunk(state, hunk) end
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Accept hunk" })

  -- Reject hunk
  vim.keymap.set("n", "x", function()
    local hunk = M._get_hunk_at_cursor(state)
    if hunk then M._reject_hunk(state, hunk, session_ctx) end
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Reject hunk" })

  -- Accept all
  vim.keymap.set("n", "A", function()
    for _, hunk in ipairs(state.hunks) do
      if hunk.status == "pending" then M._accept_hunk(state, hunk) end
    end
    Utils.info("All hunks accepted")
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Accept all hunks" })

  -- Reject all
  vim.keymap.set("n", "X", function()
    for _, hunk in ipairs(state.hunks) do
      if hunk.status == "pending" then M._reject_hunk(state, hunk, session_ctx) end
    end
    Utils.info("All hunks rejected")
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Reject all hunks" })

  -- Navigation
  vim.keymap.set("n", "]c", function()
    M._jump_hunk(state, 1)
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Next hunk" })

  vim.keymap.set("n", "[c", function()
    M._jump_hunk(state, -1)
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Previous hunk" })

  -- Close
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(state.winid) then
      vim.api.nvim_win_close(state.winid, true)
    end
  end, { buffer = bufnr, noremap = true, silent = true, desc = "Close review" })
end

return M
