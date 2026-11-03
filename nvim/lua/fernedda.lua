-- Link between Neovim and the fernedda app.
--
-- fernedda starts nvim with this module on package.path (not the runtimepath,
-- which lazy.nvim resets):
--   nvim --listen <sock> -c "lua package.path = [[<repo>/nvim/lua/?.lua;]] .. package.path;
--        require('fernedda').setup({ socket = ..., root = ... })" <boat dir>
--
-- nvim → app: whenever the cursor moves in oil (or you enter a file) under the
-- boat folder, the path is sent to the app ("focus\t<path>"), and the app
-- shows that part of the boat.
-- app → nvim: the app calls reveal / edit / insert below through
-- `nvim --server <sock> --remote-expr`, with the argument base64-encoded.

local M = {}

local cfg = { socket = nil, root = nil }
local chan = nil
local last = nil      -- last path sent, to skip repeats
local timer = nil

local function connect()
  if chan then return chan end
  local ok, c = pcall(vim.fn.sockconnect, "pipe", cfg.socket, { rpc = false })
  if ok and c and c > 0 then chan = c end
  return chan
end

local function send(line)
  if not connect() then return end
  local ok = pcall(vim.fn.chansend, chan, line .. "\n")
  if not ok then
    chan = nil -- app restarted; reconnect next time
    if connect() then pcall(vim.fn.chansend, chan, line .. "\n") end
  end
end

local function under_root(p)
  return p and cfg.root and (p == cfg.root or vim.startswith(p, cfg.root .. "/"))
end

-- The path the cursor is "on": the oil entry under it, or the current file.
local function current_path()
  if vim.bo.filetype == "oil" then
    local ok, oil = pcall(require, "oil")
    if not ok then return nil end
    local dir = oil.get_current_dir()
    if not dir then return nil end
    local entry = oil.get_cursor_entry()
    local p = dir
    if entry and entry.name ~= ".." then p = dir .. entry.name end
    return (p:gsub("/+$", ""))
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or vim.bo.buftype ~= "" then return nil end
  return vim.fs.normalize(name)
end

local function report()
  local p = current_path()
  if not p or p == last or not under_root(p) then return end
  last = p
  send("focus\t" .. p)
end

-- Debounced: holding j shouldn't flood the app.
local function schedule_report()
  if timer then timer:stop() end
  timer = vim.defer_fn(report, 40)
end

function M.setup(opts)
  cfg.socket = opts.socket
  cfg.root = vim.fs.normalize(opts.root)
  local group = vim.api.nvim_create_augroup("fernedda", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, { group = group, callback = schedule_report })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "OilEnter", callback = schedule_report })
end

local function decode(b64)
  return vim.base64.decode(b64)
end

-- Calls from the app arrive as RPC requests; run the work in the main loop so
-- prompts (e.g. a swap-file ATTENTION) show up normally instead of failing.
local function later(fn)
  return function(b64)
    local arg = decode(b64)
    vim.schedule(function() fn(arg) end)
  end
end

-- Put the cursor on `name` in the current oil buffer.
local function place_cursor(name)
  local ok, oil = pcall(require, "oil")
  if not ok then return end
  for lnum = 1, vim.api.nvim_buf_line_count(0) do
    local e = oil.get_entry_on_line(0, lnum)
    if e and e.name == name then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return
    end
  end
end

-- Show a path in oil with the cursor on it. Only while oil is on screen:
-- if you're editing a note, the app leaves you alone.
M.reveal = later(function(path)
  if vim.bo.filetype ~= "oil" or not vim.uv.fs_stat(path) then return end
  last = path -- the app already shows this; don't echo it back
  local parent, name = vim.fs.dirname(path), vim.fs.basename(path)
  if path == cfg.root then parent, name = path, nil end
  local oil = require("oil")
  local here = (oil.get_current_dir() or ""):gsub("/+$", "")
  if here == parent then
    if name then place_cursor(name) end
    return
  end
  vim.api.nvim_create_autocmd("User", {
    pattern = "OilEnter",
    once = true,
    callback = function()
      vim.schedule(function()
        if name then place_cursor(name) end
        last = path
      end)
    end,
  })
  oil.open(parent)
end)

-- Open a file for editing (other buffers stay open; nothing unsaved is lost).
M.edit = later(function(path)
  last = path
  if vim.api.nvim_win_get_config(0).relative ~= "" then
    pcall(vim.api.nvim_win_close, 0, false) -- leave an oil float first
  end
  pcall(vim.cmd.edit, vim.fn.fnameescape(path))
end)

-- Insert Markdown lines below the cursor, in a note under the boat folder.
M.insert = later(function(text)
  local name = vim.api.nvim_buf_get_name(0)
  if not under_root(vim.fs.normalize(name)) or not vim.bo.modifiable or vim.bo.filetype == "oil" then
    vim.notify("fernedda: open a note to insert readings", vim.log.levels.WARN)
    return
  end
  vim.api.nvim_put(vim.split(text, "\n", { plain = true }), "l", true, true)
end)

return M
