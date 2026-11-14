-- Link between Neovim and the fernedda app.
--
-- fernedda embeds nvim and starts it with this module on package.path (not the
-- runtimepath, which lazy.nvim resets):
--   nvim --embed -c "lua package.path = [[<repo>/nvim/lua/?.lua;]] .. package.path;
--        require('fernedda').setup({ root = ... })" <boat dir>
--
-- nvim → app: whenever the cursor moves in oil (or you enter a file) under the
-- boat folder, the path is sent to the app ("focus", <path>), and the app shows
-- that part of the boat.
-- app → nvim: the app calls reveal / open_folder / insert / quit below over the
-- same RPC channel.

local M = {}

local cfg = { root = nil }
local last = nil      -- last path sent, to skip repeats
local timer = nil
local quiet_until = 0 -- after the app moves oil, its landing isn't reported back
local opening = false -- a reveal is still opening its folder in oil
local after_open = nil -- an open_folder waiting for that

-- The app is the UI attached to this nvim.
local function send(cmd, arg)
  local ui = vim.api.nvim_list_uis()[1]
  if ui then vim.rpcnotify(ui.chan, "fernedda", cmd, arg or "") end
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
  if vim.uv.now() < quiet_until then last = p; return end
  if not p or p == last or not under_root(p) then return end
  last = p
  send("focus", p)
end

-- Debounced: holding j shouldn't flood the app.
local function schedule_report()
  if timer then timer:stop() end
  timer = vim.defer_fn(report, 40)
end

-- A colorscheme with no Normal background leaves it to the host, like a
-- transparent terminal. The UI protocol can't say so: it just sends black.
local function report_background()
  send("transparent", vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg and "0" or "1")
end

function M.setup(opts)
  cfg.root = vim.fs.normalize(opts.root)
  local group = vim.api.nvim_create_augroup("fernedda", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, { group = group, callback = schedule_report })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "OilEnter", callback = schedule_report })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = report_background })
  report_background()
  send("ready")
end

-- Calls from the app arrive over RPC; run the work in the main loop so prompts
-- (e.g. a swap-file ATTENTION) show up normally instead of failing.
local function later(fn)
  return function(arg)
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

local function opened()
  opening = false
  if after_open then
    after_open()
    after_open = nil
  end
end

-- Show a path in oil. Only while oil is on screen: if you're editing a note,
-- the app leaves you alone.
--   folder → open it in oil (enter it)
--   file   → open its folder with the cursor on it
M.reveal = later(function(path)
  local stat = vim.uv.fs_stat(path)
  if vim.bo.filetype ~= "oil" or not stat then return end
  local oil = require("oil")
  local here = (oil.get_current_dir() or ""):gsub("/+$", "")
  local dir, name = path, nil
  if stat.type ~= "directory" then dir, name = vim.fs.dirname(path), vim.fs.basename(path) end

  -- Whatever the cursor lands on next isn't a move of yours, so don't report
  -- it back (the app already shows `path`); your next real move will be.
  local function settle()
    if name then place_cursor(name) end
    last = current_path()
  end
  last = path
  quiet_until = vim.uv.now() + 400
  if here == dir then return settle() end
  opening = true
  vim.defer_fn(opened, 1000) -- never leave an open_folder waiting if oil didn't open
  -- Not an OilEnter autocmd: that only fires the first time oil loads a folder.
  oil.open(dir, nil, function()
    vim.schedule(function()
      settle()
      opened()
    end)
  end)
end)

local function open_folder(path)
  last = path
  quiet_until = vim.uv.now() + 400
  vim.cmd.stopinsert()
  if vim.api.nvim_win_get_config(0).relative ~= "" then
    pcall(vim.api.nvim_win_close, 0, false) -- leave a float first
  end
  local ok, oil = pcall(require, "oil")
  if ok then
    oil.open(path)
  else
    pcall(vim.cmd.edit, vim.fn.fnameescape(path))
  end
  -- The app may have just made this folder, and oil wouldn't list it in a
  -- parent it already read. Drop that listing so going up reads it afresh.
  local parent = "oil://" .. vim.fs.dirname(path) .. "/"
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == parent and not vim.bo[buf].modified and #vim.fn.win_findbuf(buf) == 0 then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
end

-- Open a folder you asked for. Unlike reveal this also leaves a note you're
-- editing (it stays open, unsaved changes included). If oil is still opening a
-- folder, wait: its reveal would land on top of this one.
M.open_folder = later(function(path)
  if opening then
    after_open = function() open_folder(path) end
  else
    open_folder(path)
  end
end)

-- Insert Markdown lines below the cursor, in a file under the boat folder.
M.insert = later(function(text)
  local name = vim.api.nvim_buf_get_name(0)
  if not under_root(vim.fs.normalize(name)) or not vim.bo.modifiable or vim.bo.filetype == "oil" then
    vim.notify("fernedda: open a file to insert readings", vim.log.levels.WARN)
    return
  end
  vim.api.nvim_put(vim.split(text, "\n", { plain = true }), "l", true, true)
end)

-- The app is closing. Unsaved notes get the usual prompt, shown in the pane;
-- answering Cancel leaves everything open.
M.quit = later(function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      send("attention")
      break
    end
  end
  pcall(vim.cmd, "confirm qall")
  send("quit_cancelled")
end)

return M
