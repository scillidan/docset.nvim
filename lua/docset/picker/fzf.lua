local M = {}

local filter = require("docset.filter")

local function hl_to_ansi(hl_name, attrs)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_name, link = false })
  if not ok or not hl then
    return ""
  end
  local codes = {}
  if attrs and attrs.italic then
    table.insert(codes, "3")
  end
  if attrs and attrs.dim then
    table.insert(codes, "2")
  end
  if hl.fg then
    local r = math.floor(hl.fg / 65536) % 256
    local g = math.floor(hl.fg / 256) % 256
    local b = hl.fg % 256
    table.insert(codes, string.format("38;2;%d;%d;%d", r, g, b))
  end
  if #codes == 0 then
    return ""
  end
  return string.format("\27[%sm", table.concat(codes, ";"))
end

local NAME_WIDTH = 30
local TYPE_WIDTH = 12

local function pad_right(str, width)
  local w = vim.fn.strdisplaywidth(str)
  if w > width then
    return str:sub(1, width - 1) .. "…"
  end
  return str .. string.rep(" ", width - w)
end

-- Returns the name column and the type/docset column as separate fields so
-- fzf's search scope (--nth) can be restricted to the name; docset and type
-- are matched via the filter syntax instead.
local function format_entry(entry, cfg)
  local hl = cfg.highlights or {}
  local type_ansi = hl_to_ansi(hl.entry_type or "Comment", { dim = true })
  local docset_ansi = hl_to_ansi(hl.entry_docset or "Comment", { dim = true })
  local reset = "\27[0m"
  local docset_name = entry.docset.title or entry.docset.name
  local type_text = "[" .. entry.type .. "]"

  local type_pad = TYPE_WIDTH - vim.fn.strdisplaywidth(type_text)
  if type_pad < 0 then type_pad = 0 end

  local name_part = pad_right(entry.name, NAME_WIDTH)
  local meta_part = type_ansi .. type_text .. reset .. string.rep(" ", type_pad)
    .. "  " .. docset_ansi .. docset_name .. reset .. " "
  return name_part, meta_part
end

function M.open(entries, opts)
  opts = opts or {}
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    require("docset.utils").notify("fzf-lua not found", vim.log.levels.ERROR)
    return
  end
  local fzf_actions = require("fzf-lua.actions")

  local cfg = require("docset.config").opts
  local docsets = opts.docsets or {}
  local query = opts.query or ""

  -- Parse initial filter from query
  local filters = opts.filters or { docsets = {}, types = {} }
  local content_query = query
  if not opts.filters then
    local docset_ids, types, content = filter.parse_filter(query, docsets, entries)
    if docset_ids then
      filters.docsets = docset_ids
      filters.types = types or {}
      content_query = content or ""
    end
  end

  local shown = filter.filter_entries(entries, filters)

  local function contents(cb)
    for i, entry in ipairs(shown) do
      -- Fields: 1 = name column (searched), 2 = type/docset column, 3 = index
      local name_part, meta_part = format_entry(entry, cfg)
      cb(name_part .. "\t" .. meta_part .. "\t" .. i)
    end
    cb(nil)
  end

  local function resolve_selected(raw)
    local idx = tonumber(raw and raw:match("\t(%d+)$"))
    return idx and shown[idx]
  end

  local function reopen(new_filters, new_query)
    M.open(entries, {
      prompt = opts.prompt,
      query = new_query or "",
      filters = new_filters,
      docsets = docsets,
      on_select = opts.on_select,
    })
  end

  -- Apply a filter typed in the query box (e.g. "lua:", "lua:function").
  -- Returns true when the query was a valid filter and the picker reopened.
  local function apply_query_filter(query_text)
    local docset_ids, types, content = filter.parse_filter(query_text, docsets, entries)
    if not docset_ids then
      return false
    end
    reopen({ docsets = docset_ids, types = types or {} }, content or "")
    return true
  end

  local ok_exec, exec_err = pcall(fzf.fzf_exec, contents, {
    prompt = opts.prompt or "Docset> ",
    query = content_query,
    winopts = {
      border = "none",
      preview = {
        horizontal = "right:50%",
        layout = "horizontal",
        border = "none",
      },
    },
    preview = function(items)
      local entry = resolve_selected(items[1])
      if not entry then
        return ""
      end
      return require("docset.browser").preview_text(entry)
    end,
    fzf_opts = {
      ["--ansi"] = true,
      ["--multi"] = true,
      ["--delimiter"] = "\\t",
      -- NOTE: --nth applies to the --with-nth-transformed line, so the
      -- display fields are arranged as { name, type/docset } and search is
      -- limited to the name column only.
      ["--with-nth"] = "1,2",
      ["--nth"] = "1",
      ["--header"] = filter.build_header("C-f filter | C-r reset | C-q quit", filters, #shown),
    },
    actions = {
      ["default"] = function(selected)
        -- Enter on a query with filter syntax applies the filter instead of
        -- opening a selection (the query fuzzy-matched nothing anyway).
        if apply_query_filter(fzf.get_last_query() or "") then
          return
        end
        if opts.on_select and #selected > 0 then
          local resolved = {}
          for _, raw in ipairs(selected) do
            local entry = resolve_selected(raw)
            if entry then
              table.insert(resolved, entry)
            end
          end
          opts.on_select(resolved)
        end
      end,
      ["ctrl-f"] = function()
        local last_query = fzf.get_last_query() or ""
        if not apply_query_filter(last_query) then
          require("docset.utils").notify("No valid filter in query", vim.log.levels.WARN)
          -- fzf exits on any action key; reopen to restore the previous state
          reopen(filters, last_query)
        end
      end,
      ["ctrl-r"] = function()
        reopen({ docsets = {}, types = {} }, "")
      end,
      ["ctrl-q"] = fzf_actions.dummy_abort,
    },
  })
  if not ok_exec then
    require("docset.utils").notify("fzf_exec failed: " .. tostring(exec_err), vim.log.levels.ERROR)
  end
end

return M
