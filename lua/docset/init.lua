local M = {}

local config = require("docset.config")
local docset = require("docset.docset")
local db = require("docset.db")
local browser = require("docset.browser")
local picker = require("docset.picker")
local utils = require("docset.utils")

local _docsets = {}
local _entries = nil

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "docset" })
end

local function load_entries_async(callback)
  if _entries then
    callback(_entries)
    return
  end

  local all = {}
  local pending = #_docsets
  if pending == 0 then
    _entries = all
    callback(all)
    return
  end

  for _, ds in ipairs(_docsets) do
    vim.schedule(function()
      local entries = db.load_entries(ds)
      for _, e in ipairs(entries) do
        table.insert(all, e)
      end
      pending = pending - 1
      if pending == 0 then
        table.sort(all, function(a, b)
          return a.name:lower() < b.name:lower()
        end)
        _entries = all
        callback(all)
      end
    end)
  end
end

local function get_word()
  local cword = vim.fn.expand("<cword>")
  if not cword or cword == "" then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local left, right = col, col
  while left > 1 and line:sub(left - 1, left - 1):match("[%w_%.:]") do
    left = left - 1
  end
  while right < #line and line:sub(right + 1, right + 1):match("[%w_%.:]") do
    right = right + 1
  end
  local expanded = line:sub(left, right)
  if expanded:lower():find(cword:lower(), 1, true) then
    return expanded
  end
  return cword
end

function M.setup(opts)
  config.setup(opts)
  _docsets = docset.discover(config.opts.docset_dirs)
  if #_docsets == 0 then
    notify("No Zeal docsets found in configured directories", vim.log.levels.WARN)
  end

  vim.api.nvim_create_user_command("Docset", function(args)
    M.open(args.args ~= "" and args.args or nil)
  end, { nargs = "?", desc = "Open docset picker" })

  vim.api.nvim_create_user_command("DocsetLookup", function(args)
    M.lookup(args.args ~= "" and args.args or nil)
  end, { nargs = "?", desc = "Look up word in docsets" })
end

function M.open(filter)
  load_entries_async(function(entries)
    if #entries == 0 then
      notify("No entries loaded", vim.log.levels.WARN)
      return
    end

    local ok, err = pcall(picker.open, entries, {
      query = filter or "",
      docsets = _docsets,
      on_select = browser.open,
    })
    if not ok then
      notify("Failed to open picker: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

function M.lookup(word)
  word = word or get_word()
  if not word or word == "" then
    notify("No word under cursor", vim.log.levels.WARN)
    return
  end

  load_entries_async(function(entries)
    if #entries == 0 then
      notify("No entries loaded", vim.log.levels.WARN)
      return
    end

    local ok, err = pcall(picker.open, entries, {
      query = word,
      docsets = _docsets,
      on_select = browser.open,
    })
    if not ok then
      notify("Failed to open picker: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

return M
