local M = {}
local utils = require("docset.utils")

M.known_browsers = {
  reader = function(file)
    return { "reader", "--image-mode", "none", file }
  end,
  elinks = function(file)
    return { "elinks", file }
  end,
  lynx = function(file)
    return { "lynx", file }
  end,
}

-- Container state: shared across all doc reads.
-- type: "float" | "tab" | "vsplit" | "split"
-- win: container window handle
-- tab: container tabpage handle (only for "tab")
-- bufs: list of { buf, entry, title }
-- index: currently shown buffer index
local _c = nil

function M.detect()
  for _, name in ipairs({ "reader", "elinks", "lynx" }) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  return nil
end

function M.resolve_name(browser)
  if browser == "auto" then
    return M.detect()
  end
  if type(browser) == "string" and M.known_browsers[browser] then
    return browser
  end
  if type(browser) == "table" or (type(browser) == "string" and browser ~= "auto") then
    return "custom"
  end
  return nil
end

function M.build_command(browser, file)
  local resolved = M.resolve_name(browser)
  if resolved == nil then
    return nil
  end
  if resolved == "custom" then
    if type(browser) == "table" then
      local cmd = vim.deepcopy(browser)
      local has_file = false
      for i, arg in ipairs(cmd) do
        if arg == "{file}" then
          cmd[i] = file
          has_file = true
        end
      end
      if not has_file then
        table.insert(cmd, file)
      end
      return cmd
    end
    return { browser, file }
  end
  return M.known_browsers[resolved](file)
end

local _preview_cache = {}

function M.preview_text(entry)
  local key = entry.docset.path .. "::" .. entry.path
  if _preview_cache[key] then
    return _preview_cache[key]
  end

  local file = entry.docset.doc_dir .. "/" .. entry.path
  file = utils.normalize_path(file)
  file = file:gsub("#.*$", "") -- strip fragment

  local cfg = require("docset.config").opts
  local cmd = M.build_command(cfg.browser, file)
  if not cmd then
    return "No browser configured"
  end

  local ok, result = pcall(function()
    if vim.system then
      return vim.system(cmd, { text = true }):wait()
    end
    local out = vim.fn.system(cmd)
    return { code = vim.v.shell_error, stdout = out, stderr = "" }
  end)

  local text
  if not ok or not result or result.code ~= 0 then
    text = "Preview failed: " .. (result and result.stderr or tostring(ok))
  else
    text = result.stdout or ""
  end

  -- Limit preview content to reduce lag on huge pages
  local max_lines = cfg.preview_max_lines
  if max_lines and max_lines > 0 then
    local lines = vim.split(text, "\n", { plain = true })
    if #lines > max_lines then
      lines = vim.list_slice(lines, 1, max_lines)
      table.insert(lines, "")
      table.insert(lines, "... (truncated; open doc to see full content)")
      text = table.concat(lines, "\n")
    end
  end

  _preview_cache[key] = text
  return text
end

local function clear_state()
  _c = nil
end

local function container_valid()
  if not _c then
    return false
  end
  if _c.type == "tab" then
    return _c.tab and vim.api.nvim_tabpage_is_valid(_c.tab)
  end
  return _c.win and vim.api.nvim_win_is_valid(_c.win)
end

local function file_for_entry(entry)
  local file = entry.docset.doc_dir .. "/" .. entry.path
  file = utils.normalize_path(file)
  return file:gsub("#.*$", "")
end

local function focus_container()
  if not container_valid() then
    return false
  end
  if _c.type == "tab" then
    vim.api.nvim_set_current_tabpage(_c.tab)
    _c.win = vim.api.nvim_tabpage_get_win(_c.tab)
  else
    vim.api.nvim_set_current_win(_c.win)
  end
  return true
end

local function parse_mode(doc_window)
  local mode = doc_window.mode
  if type(mode) == "string" then
    return mode, {}
  end
  return mode[1], mode[2] or {}
end

local function split_command(split, opts)
  if split == "split" then
    local pos = opts.position
    if pos == "below" then
      return "belowright split"
    elseif pos == "above" then
      return "aboveleft split"
    end
    return "split"
  end
  if split == "vsplit" then
    local pos = opts.position
    if pos == "right" then
      return "rightbelow vsplit"
    elseif pos == "left" then
      return "aboveleft vsplit"
    end
    return "vsplit"
  end
  return "vsplit"
end

local function create_container(cfg)
  clear_state()
  local split, opts = parse_mode(cfg.doc_window)
  _c = { type = split, bufs = {}, index = 0 }

  if split == "float" then
    local width = math.floor(vim.o.columns * (opts.width or 0.8))
    local height = math.floor(vim.o.lines * (opts.height or 0.85))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    _c.win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "none",
    })
  elseif split == "tab" then
    vim.cmd("tabnew")
    _c.tab = vim.api.nvim_get_current_tabpage()
    _c.win = vim.api.nvim_get_current_win()
  else
    vim.cmd(split_command(split, opts))
    _c.win = vim.api.nvim_get_current_win()
  end

  -- clear state when container closes
  if split == "tab" then
    vim.api.nvim_create_autocmd("TabClosed", {
      pattern = tostring(_c.tab),
      once = true,
      callback = clear_state,
    })
  else
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(_c.win),
      once = true,
      callback = clear_state,
    })
  end
end

local function ensure_container(cfg)
  local split, _ = parse_mode(cfg.doc_window)
  if container_valid() and _c.type == split then
    focus_container()
    return
  end
  if container_valid() then
    -- container type changed; close old one
    close_container()
  end
  create_container(cfg)
end

local function create_doc_item(entry)
  local cfg = require("docset.config").opts
  local file = file_for_entry(entry)
  local cmd = M.build_command(cfg.browser, file)
  if not cmd then
    return nil
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  return { buf = buf, entry = entry, title = entry.name, cmd = cmd }
end

local function run_item_terminal(item)
  if not focus_container() then
    return
  end
  vim.api.nvim_set_current_buf(item.buf)
  vim.fn.termopen(item.cmd)
end

local function update_winbar()
  if not _c or _c.type ~= "float" or not _c.win or not vim.api.nvim_win_is_valid(_c.win) then
    return
  end
  if #_c.bufs == 0 then
    pcall(vim.api.nvim_set_option_value, "winbar", "", { win = _c.win })
    return
  end
  local cfg = require("docset.config").opts
  local hl = cfg.highlights or {}
  local hl_normal = hl.tab or "TabLine"
  local hl_active = hl.tab_active or "TabLineSel"
  local parts = {}
  for i, item in ipairs(_c.bufs) do
    local active = i == _c.index
    local label = " " .. item.title .. " "
    local group = active and hl_active or hl_normal
    table.insert(parts, "%#" .. group .. "#%" .. i .. "@v:lua._G.__docset_winbar_click@" .. label .. "%X")
  end
  -- reset highlight at the end
  table.insert(parts, "%*")
  pcall(vim.api.nvim_set_option_value, "winbar", table.concat(parts, ""), { win = _c.win })
end

-- Global click handler for float winbar tabs.
_G.__docset_winbar_click = function(minwid)
  M.switch_buffer(minwid)
end

function M.switch_buffer(idx)
  if not _c or idx < 1 or idx > #_c.bufs then
    return
  end
  _c.index = idx
  local item = _c.bufs[idx]
  if focus_container() then
    vim.api.nvim_win_set_buf(_c.win, item.buf)
  end
  update_winbar()
end

local function close_container()
  local c = _c
  clear_state()
  if not c then
    return
  end
  for _, item in ipairs(c.bufs) do
    if vim.api.nvim_buf_is_valid(item.buf) then
      vim.api.nvim_buf_delete(item.buf, { force = true })
    end
  end
  if c.type == "tab" and c.tab and vim.api.nvim_tabpage_is_valid(c.tab) then
    vim.api.nvim_tabpage_close(c.tab, true)
  elseif c.win and vim.api.nvim_win_is_valid(c.win) then
    vim.api.nvim_win_close(c.win, true)
  end
end

local function close_current_buffer()
  local c = _c
  if not c then
    return
  end
  local item = table.remove(c.bufs, c.index)
  if not item then
    return
  end

  -- Decide which buffer to show next before deleting the current one.
  local remaining = c.bufs
  local next_index = math.min(c.index, #remaining)
  if remaining[next_index] then
    c.index = next_index
    M.switch_buffer(next_index)
  end

  if vim.api.nvim_buf_is_valid(item.buf) then
    vim.api.nvim_buf_delete(item.buf, { force = true })
  end

  if #remaining == 0 then
    -- Last buffer removed; close container using captured state.
    clear_state()
    if c.type == "tab" and c.tab and vim.api.nvim_tabpage_is_valid(c.tab) then
      vim.api.nvim_tabpage_close(c.tab, true)
    elseif c.win and vim.api.nvim_win_is_valid(c.win) then
      vim.api.nvim_win_close(c.win, true)
    end
  end
end

local function setup_buffer_keymaps(buf)
  vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = buf, silent = true })

  -- Terminal-mode convenience keys (Ctrl-modified to avoid conflicts)
  vim.keymap.set("t", "<C-h>", function()
    if _c then
      M.switch_buffer(_c.index - 1)
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set("t", "<C-l>", function()
    if _c then
      M.switch_buffer(_c.index + 1)
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set("t", "<C-d>", close_current_buffer, { buffer = buf, silent = true })
  vim.keymap.set("t", "<C-q>", close_container, { buffer = buf, silent = true })

  -- Normal-mode keys
  vim.keymap.set("n", "q", close_container, { buffer = buf, silent = true })
  vim.keymap.set("n", "d", close_current_buffer, { buffer = buf, silent = true })
  vim.keymap.set("n", "H", function()
    if _c then
      M.switch_buffer(_c.index - 1)
    end
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "L", function()
    if _c then
      M.switch_buffer(_c.index + 1)
    end
  end, { buffer = buf, silent = true })

  -- For dump browsers the job exits quickly; leave terminal mode so H/L/q/d work.
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      vim.cmd("stopinsert")
    end,
  })
end

function M.open(entries_or_entry)
  local entries = entries_or_entry
  if entries.docset then
    entries = { entries_or_entry }
  end
  if #entries == 0 then
    return
  end

  local cfg = require("docset.config").opts
  ensure_container(cfg)

  local first_new_index = #_c.bufs + 1
  for _, entry in ipairs(entries) do
    local item = create_doc_item(entry)
    if item then
      setup_buffer_keymaps(item.buf)
      run_item_terminal(item)
      table.insert(_c.bufs, item)
    end
  end

  if first_new_index > #_c.bufs then
    return
  end
  _c.index = first_new_index
  M.switch_buffer(_c.index)
end

return M
