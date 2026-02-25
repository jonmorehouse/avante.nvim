---@class avante.Notifications
local M = {}

-- Module state
M.session_timings = {} -- Track start times for duration calculation
M.notification_available = nil -- Cache availability check
M.os_type = nil -- Cache platform detection
M.notification_tool = nil -- Cached notification tool name

---Initialize the notification system
---Detects platform and checks for available notification tools
function M.setup()
  M.os_type = vim.uv.os_uname().sysname
  M.notification_available = M._detect_notification_tool()
  
  if not M.notification_available then
    local Config = require("avante.config")
    if Config.debug then
      vim.notify(
        "[Avante] Desktop notifications unavailable: notification tool not found for " .. M.os_type,
        vim.log.levels.DEBUG
      )
    end
  end
end

---Detect if notification tool is available on the system
---@return boolean
function M._detect_notification_tool()
  if M.os_type == "Darwin" then
    -- Try terminal-notifier first (better UX), fall back to osascript
    if vim.fn.executable("terminal-notifier") == 1 then
      M.notification_tool = "terminal-notifier"
      return true
    elseif vim.fn.executable("osascript") == 1 then
      M.notification_tool = "osascript"
      return true
    end
  elseif M.os_type == "Linux" then
    if vim.fn.executable("notify-send") == 1 then
      M.notification_tool = "notify-send"
      return true
    end
  elseif M.os_type == "Windows_NT" then
    if vim.fn.executable("powershell") == 1 or vim.fn.executable("powershell.exe") == 1 then
      M.notification_tool = "powershell"
      return true
    end
  end
  
  return false
end

---Track agent start time
---@param session_id string
function M.on_agent_start(session_id)
  if not session_id then return end
  M.session_timings[session_id] = vim.loop.hrtime()
end

---Handle agent completion and send notification
---@param session_id string
---@param stop_opts table Stop options with reason and optional error
---@param task_summary string|nil Brief description of the task
---@param thread_title string|nil Title of the thread (shown in notification for pinned threads)
function M.on_agent_complete(session_id, stop_opts, task_summary, thread_title)
  local Config = require("avante.config")

  if not Config.notifications.enabled then return end
  if not M.notification_available then return end
  if not stop_opts then return end

  -- Check if we should notify for this event type
  local should_notify = false
  if stop_opts.reason == "complete" and Config.notifications.notify_on_complete then
    should_notify = true
  elseif stop_opts.error and Config.notifications.notify_on_error then
    should_notify = true
  elseif stop_opts.reason == "cancelled" and Config.notifications.notify_on_cancel then
    should_notify = true
  end

  if not should_notify then return end

  -- Calculate duration
  local duration = M._calculate_duration(session_id)

  -- Build notification message
  local title, message = M._format_message(task_summary, duration, stop_opts, Config, thread_title)

  -- Send notification asynchronously
  M._send_notification_async(title, message)
end

---Calculate duration for a session
---@param session_id string
---@return number|nil Duration in seconds, or nil if not tracked
function M._calculate_duration(session_id)
  if not session_id or not M.session_timings[session_id] then
    return nil
  end
  
  local start_time = M.session_timings[session_id]
  local end_time = vim.loop.hrtime()
  local duration_ns = end_time - start_time
  local duration_s = duration_ns / 1e9
  
  -- Clean up timing data
  M.session_timings[session_id] = nil
  
  return duration_s
end

---Format notification title and message
---@param task_summary string|nil
---@param duration number|nil
---@param stop_opts table
---@param config table
---@param thread_title string|nil
---@return string title
---@return string message
function M._format_message(task_summary, duration, stop_opts, config, thread_title)
  local title
  local message = ""

  -- Determine title based on reason, include thread title if available
  local suffix = thread_title and (" - " .. thread_title) or ""
  if stop_opts.reason == "complete" then
    title = "Avante Complete" .. suffix
  elseif stop_opts.error then
    title = "Avante Error" .. suffix
  elseif stop_opts.reason == "cancelled" then
    title = "Avante Cancelled" .. suffix
  else
    title = "Avante Agent" .. suffix
  end
  
  -- Add duration if available and enabled
  if duration and config.notifications.include_duration then
    local duration_str = M._format_duration(duration)
    if stop_opts.reason == "complete" then
      message = "Completed in " .. duration_str
    elseif stop_opts.error then
      message = "Failed after " .. duration_str
    else
      message = "Stopped after " .. duration_str
    end
  elseif stop_opts.reason == "complete" then
    message = "Agent task completed"
  elseif stop_opts.error then
    message = "Agent task failed"
  else
    message = "Agent task stopped"
  end
  
  -- Add task summary if available and enabled
  if task_summary and config.notifications.include_summary then
    if #message > 0 then
      message = message .. ": " .. task_summary
    else
      message = task_summary
    end
  end
  
  -- Add error details if available
  if stop_opts.error and type(stop_opts.error) == "string" then
    local error_msg = stop_opts.error:sub(1, 100)
    if #message > 0 then
      message = message .. " - " .. error_msg
    else
      message = error_msg
    end
  end
  
  return title, message
end

---Format duration in human-readable format
---@param seconds number
---@return string
function M._format_duration(seconds)
  if seconds < 60 then
    return string.format("%ds", math.floor(seconds))
  elseif seconds < 3600 then
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%dm %ds", minutes, secs)
  else
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, minutes)
  end
end

---Escape special characters for shell commands
---@param str string
---@param platform string
---@return string
function M._escape_string(str, platform)
  if not str then return "" end
  
  if platform == "Darwin" or platform == "Linux" then
    -- Escape single quotes for shell
    str = str:gsub("'", "'\"'\"'")
    -- Remove control characters
    str = str:gsub("[\n\r\t]", " ")
  elseif platform == "Windows_NT" then
    -- Escape double quotes for PowerShell
    str = str:gsub('"', '""')
    -- Remove control characters
    str = str:gsub("[\n\r\t]", " ")
  end
  
  return str
end

---Build platform-specific notification command
---@param title string
---@param message string
---@return string[]|nil
function M._build_notification_command(title, message)
  if not M.notification_tool then return nil end
  
  local safe_title = M._escape_string(title, M.os_type)
  local safe_message = M._escape_string(message, M.os_type)
  
  if M.notification_tool == "terminal-notifier" then
    return {
      "terminal-notifier",
      "-title", safe_title,
      "-message", safe_message,
      "-sender", "com.vim.nvim"
    }
  elseif M.notification_tool == "osascript" then
    local script = string.format(
      'display notification "%s" with title "%s"',
      safe_message,
      safe_title
    )
    return { "osascript", "-e", script }
  elseif M.notification_tool == "notify-send" then
    return {
      "notify-send",
      "--urgency=normal",
      safe_title,
      safe_message
    }
  elseif M.notification_tool == "powershell" then
    local ps_script = string.format([[
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
[Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
$APP_ID = 'Neovim';
$template = @"
<toast>
  <visual>
    <binding template='ToastText02'>
      <text id='1'>%s</text>
      <text id='2'>%s</text>
    </binding>
  </visual>
</toast>
"@;
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument;
$xml.LoadXml($template);
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml;
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($APP_ID).Show($toast);
]], safe_title, safe_message)
    
    return { "powershell.exe", "-NoProfile", "-Command", ps_script }
  end
  
  return nil
end

---Send notification asynchronously (fire-and-forget)
---@param title string
---@param message string
function M._send_notification_async(title, message)
  local cmd = M._build_notification_command(title, message)
  if not cmd then
    M._log_error("Failed to build notification command")
    return
  end
  
  -- Log the notification attempt
  M._log_notification(title, message, cmd)
  
  -- Fire-and-forget async execution
  vim.system(cmd, { text = true }, function(result)
    if result.code ~= 0 then
      local error_msg = string.format(
        "Notification command failed (exit code %d): %s\nStderr: %s\nStdout: %s",
        result.code,
        vim.inspect(cmd),
        result.stderr or "none",
        result.stdout or "none"
      )
      M._log_error(error_msg)
      
      local Config = require("avante.config")
      if Config.debug then
        vim.schedule(function()
          vim.notify(
            "[Avante] Notification failed: " .. (result.stderr or "unknown error"),
            vim.log.levels.DEBUG
          )
        end)
      end
    else
      M._log_notification("Notification sent successfully", title)
    end
  end)
end

---Log notification attempts to file for debugging
---@param title string
---@param message string|nil
---@param cmd table|nil
function M._log_notification(title, message, cmd)
  local log_file = vim.fn.stdpath("data") .. "/avante-notifications.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = string.format(
    "[%s] %s\n  Message: %s\n  Command: %s\n\n",
    timestamp,
    title,
    message or "N/A",
    cmd and vim.inspect(cmd) or "N/A"
  )
  
  local file = io.open(log_file, "a")
  if file then
    file:write(log_entry)
    file:close()
  end
end

---Log errors to file for debugging
---@param error_msg string
function M._log_error(error_msg)
  local log_file = vim.fn.stdpath("data") .. "/avante-notifications.log"
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_entry = string.format("[%s] ERROR: %s\n\n", timestamp, error_msg)
  
  local file = io.open(log_file, "a")
  if file then
    file:write(log_entry)
    file:close()
  end
end

return M