# Changelog — avante-modes-rust branch

## New Features

### Follow Mode (`:AvanteFollowToggle`)

Auto-jumps the editor to files the agent edits in real-time, similar to Zed's crosshair feature.

- Toggle with `:AvanteFollowToggle` — winbar shows current status
- Hooks into `helpers.get_bufnr()` for native LLM tools (centers cursor at the edit line)
- Hooks into `acp_thread.lua` `_handle_tool_call_update` for ACP `locations` data
- Initialized from `Config.behaviour.acp_follow_agent_locations`

**Files:** `sidebar.lua`, `helpers.lua`, `acp_thread.lua`, `plugin/avante.lua`

### First-class AskUserQuestion UI

Agent questions are now rendered with the actual question text visible in the chat, instead of a generic collapsed tool box.

- New tool module `AskUserQuestion.lua` with custom `on_render` for inline display
- ACP flow: question text extracted from `tool_call.rawInput.question` and displayed above permission buttons
- Native flow: `vim.ui.input` for free-text or `vim.ui.select` for options
- Collapsed view shows `Q: "truncated question..." -> "answer"`
- Registered in `llm_tools/init.lua` tool list

**New files:** `lua/avante/llm_tools/AskUserQuestion.lua`
**Modified:** `history/render.lua`, `llm.lua`, `sidebar.lua`, `llm_tools/init.lua`

### Review Changes (`:AvanteReview`)

Unified diff view of all agent edits with per-hunk accept/reject, similar to a code review workflow.

- Snapshots files before first edit via `helpers.snapshot_file_for_review()`
- Tracks edited files via `helpers.track_edited_file()`
- Opens a vsplit buffer with unified diff (`vim.diff`, histogram algorithm, 3 lines context)
- Keybindings: `a` accept, `x` reject (reverts lines), `A`/`X` all, `]c`/`[c` navigate, `q` close
- Stats header: `Review: N files changed, +M -K`
- DiffAdd/DiffDelete/DiffChange highlighting

**New files:** `lua/avante/review.lua`
**Modified:** `helpers.lua`, `replace_in_file.lua`, `insert.lua`, `create.lua`, `plugin/avante.lua`

### Live Changed Files (`:AvanteChangedFiles`)

Real-time location list of all files the agent has modified, updated as edits happen.

- Uses `vim.fn.setloclist()` on `sidebar.code.winid` (per-window, doesn't trample user's quickfix)
- Computes `+N/-M` diff stats from file snapshots via `vim.diff()`
- Maintains insertion-ordered file list (`session_ctx.edited_files_order`)
- Fires `on_file_edited` callback from `track_edited_file()` to update loclist in real-time
- ACP path: snapshots on `in_progress` status, tracks on `completed`
- Navigate with `:lnext`/`:lprev` or `]l`/`[l`
- Clears on `:AvanteChatNew`

**New files:** `lua/avante/changed_files.lua`
**Modified:** `helpers.lua`, `acp_thread.lua`, `sidebar.lua`, `replace_in_file.lua`, `insert.lua`, `create.lua`, `plugin/avante.lua`

### Starred Sessions

Sessions can be starred/unstarred in the thread viewer. Starred sessions sort to the top.

**Modified:** `types.lua`, `path.lua`, `thread_viewer.lua`

### Collapsible Tool Calls

Tool call rendering in the chat now supports expand/collapse toggle.

**Modified:** `history/render.lua`, `sidebar.lua`

### Plan Container (editable)

The sidebar todos container was replaced with a plan container that supports BufWriteCmd for inline editing and feedback.

**Modified:** `sidebar.lua`, `api.lua`, `session_manager.lua`, `plugin/avante.lua`

---

## ACP Spec Compliance Audit

The following gaps were identified against the [ACP specification](https://agentclientprotocol.com):

### Protocol Bugs Found

| Issue | Severity | Location |
|---|---|---|
| `cancelled` outcome never sent for `session/request_permission` — agent hangs if sidebar is absent | High | `acp_client.lua`, `llm.lua` |
| `stopReason` from `session/prompt` response ignored — always reports `"complete"` | Medium | `llm.lua` |
| Empty string `content` rejected in `fs/write_text_file` validation | Low | `acp_client.lua` |

### Missing Protocol Features

| Feature | Spec Status |
|---|---|
| `session/set_config_option` + `configOptions` from responses | Stable spec |
| `config_options_update` session notification | Stable spec |
| `usage_update` session notification (token/context tracking) | RFD |
| `terminal` client capability + `terminal/*` methods | Stable spec |
| `clientInfo` in `initialize` request | Spec recommends |
| `agentInfo` from `initialize` response (discarded) | Spec provides |
| Diff-type tool call content rendering (`type: "diff"`) | Stable spec |

### Working Correctly

- `initialize` sends `protocolVersion` and `clientCapabilities` (fs)
- `session/new` sends `cwd` and `mcpServers`
- `session/load` checks `loadSession` capability
- `session/cancel` sent as notification
- `session/set_mode` implemented
- `fs/read_text_file` and `fs/write_text_file` fully implemented
- All 7 session update types dispatched (`plan`, `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `available_commands_update`, `current_mode_update`)
- `session/request_permission` options displayed with correct optionId responses

---

## Files Changed

### New Files (6)
- `lua/avante/acp_connection.lua` — ACP connection interface + factory
- `lua/avante/acp_connection_lua.lua` — Lua backend adapter
- `lua/avante/acp_thread.lua` — Session/thread data model
- `lua/avante/changed_files.lua` — Live changed files location list
- `lua/avante/llm_tools/AskUserQuestion.lua` — First-class question UI tool
- `lua/avante/review.lua` — Unified diff review buffer

### Modified Files (16)
- `lua/avante/api.lua` — `create_todos_container` -> `create_plan_container`
- `lua/avante/config.lua` — ACP behaviour config options
- `lua/avante/health.lua` — Health check updates
- `lua/avante/history/render.lua` — AskUserQuestion collapsed view, collapsible tool calls
- `lua/avante/llm.lua` — AskUserQuestion question text surfacing in ACP permission flow
- `lua/avante/llm_tools/create.lua` — File edit tracking
- `lua/avante/llm_tools/helpers.lua` — `get_bufnr` follow mode, `snapshot_file_for_review`, `track_edited_file` with callback
- `lua/avante/llm_tools/init.lua` — AskUserQuestion registration
- `lua/avante/llm_tools/insert.lua` — File snapshot + tracking
- `lua/avante/llm_tools/replace_in_file.lua` — File snapshot + tracking
- `lua/avante/path.lua` — Starred session sanitization
- `lua/avante/session_manager.lua` — `create_todos_container` -> `create_plan_container`
- `lua/avante/sidebar.lua` — Plan container, follow mode, question text, session_ctx, changed files callback
- `lua/avante/thread_viewer.lua` — Star toggle, starred-first sorting
- `lua/avante/types.lua` — `starred` field on ChatHistory
- `plugin/avante.lua` — New commands: `:AvanteFollowToggle`, `:AvanteReview`, `:AvanteChangedFiles`, `:AvantePlan`

**Total: 852 insertions, 103 deletions across 22 files**
