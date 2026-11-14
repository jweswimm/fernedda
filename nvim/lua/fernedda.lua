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

-- Touch boxes: where oil's entries are on the screen, so the app can draw a
-- tappable box around each. Cells are 1-based screen rows / columns:
--   { boxes = { { name, dir, cur, row, col, width, span } }, status = { row, col, width, span } }
-- `span` is the cells from `col` to the window's right edge: the whole rest of
-- the row taps the entry, not just its name.
-- `status` is the current window's status line (tap: up a folder in oil, back
-- to the folder when editing a file). `footer` is how many rows at the bottom
-- are the last status line and the command line, which the app draws smaller.
local last_tiles = nil
local function report_tiles()
  local win = vim.api.nvim_get_current_win()
  local info = vim.fn.getwininfo(win)[1]
  local wins = #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == "" end,
    vim.api.nvim_tabpage_list_wins(0))
  local ls = vim.o.laststatus
  local has_status = ls == 2 or ls == 3 or (ls == 1 and wins > 1)
  local state = { boxes = {}, footer = vim.o.cmdheight + (has_status and 1 or 0) }
  local ok, oil = pcall(require, "oil")
  if ok and vim.bo.filetype == "oil" and oil.get_current_dir() then
    local leftcol = vim.fn.winsaveview().leftcol
    local curline = vim.fn.line(".")
    for lnum = info.topline, info.botline do
      local e = oil.get_entry_on_line(0, lnum)
      local text = vim.fn.getline(lnum)
      -- Oil conceals each line's "/<id> " prefix; what's left before the name
      -- (an icon column, say) is on screen.
      local body = text:gsub("^/%d+%s", "", 1)
      local at = e and e.name ~= "" and body:find(e.name, 1, true)
      local row = at and vim.fn.screenpos(win, lnum, 1).row or 0
      if row > 0 then
        local col = info.wincol + info.textoff + vim.fn.strdisplaywidth(body:sub(1, at - 1)) - leftcol
        local width = vim.fn.strdisplaywidth(e.name) + (e.type == "directory" and 1 or 0)
        width = math.min(width, info.wincol + info.width - col)
        local span = info.wincol + info.width - col
        if width > 0 then
          table.insert(state.boxes, { name = e.name, dir = e.type == "directory", cur = lnum == curline,
                                      row = row, col = col, width = width, span = span })
        end
      end
    end
  end
  local floating = vim.api.nvim_win_get_config(win).relative ~= ""
  if not floating and vim.o.laststatus > 0 and (vim.bo.filetype == "oil" or vim.bo.buftype == "") then
    -- The default status line starts with the name; a custom one, take it all.
    local width = info.width
    if vim.o.statusline == "" then
      width = math.min(width, vim.api.nvim_eval_statusline("%f", { winid = win }).width)
    end
    state.status = { row = info.winrow + info.height, col = info.wincol, width = width, span = info.width }
  end
  local msg = vim.json.encode(state)
  if msg ~= last_tiles then
    last_tiles = msg
    send("tiles", msg)
  end
end

-- Oil renamed or moved folders: tell the app ("moved", {src, dest} absolute
-- paths), so a part of the boat follows its folder to a new name.
local function report_moves(args)
  if args.data.err then return end
  for _, a in ipairs(args.data.actions or {}) do
    if a.type == "move" and a.entry_type == "directory" then
      local function path(url) return (url:gsub("^oil://", ""):gsub("/+$", "")) end
      local src, dest = path(a.src_url), path(a.dest_url)
      if under_root(src) then send("moved", vim.json.encode({ src = src, dest = dest })) end
    end
  end
end

-- Debounced: holding j shouldn't flood the app.
local function schedule_report()
  if timer then timer:stop() end
  timer = vim.defer_fn(function()
    report()
    report_tiles()
  end, 40)
end

-- A colorscheme with no Normal background leaves it to the host, like a
-- transparent terminal. The UI protocol can't say so: it just sends black.
local function report_background()
  send("transparent", vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg and "0" or "1")
end

function M.setup(opts)
  cfg.root = vim.fs.normalize(opts.root)
  local group = vim.api.nvim_create_augroup("fernedda", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "TextChanged", "TextChangedI", "WinScrolled", "WinResized", "VimResized", "OptionSet" }, { group = group, callback = schedule_report })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "OilEnter", callback = schedule_report })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "OilActionsPost", callback = report_moves })
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

-- A touch box was tapped. In oil: ".." goes up, a folder opens in oil, a
-- file opens for editing. Editing a file: any tap goes back to its folder.
M.tap = later(function(name)
  local ok, oil = pcall(require, "oil")
  if not ok then return end
  vim.cmd.stopinsert()
  if vim.bo.filetype ~= "oil" then
    oil.open() -- the current file's folder, cursor on the file
    return
  end
  if name == ".." then
    require("oil.actions").parent.callback() -- cursor lands on the folder you left
    return
  end
  place_cursor(name)
  oil.select()
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
