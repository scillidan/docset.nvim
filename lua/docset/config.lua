local M = {}

M.opts = {
  docset_dirs = {},
  picker = "fzf", -- telescope | fzf
  browser = "", -- see README "Terminal web browsers"
  doc_window = {
    -- Web-reader container mode: { split_type, opts }
    -- Examples:
    --   { "float",  { width = 0.8, height = 0.85 } }
    --   { "split",  { position = "below" } }
    --   { "vsplit", { position = "right" } }
    --   { "tab" }
    mode = { "float", { width = 0.8, height = 0.85 } },
  },
  highlights = {
    tab = "TabLine",
    tab_active = "TabLineSel",
    entry_type = "Comment",
    entry_docset = "Comment",
  },
  preview_max_lines = 200,
  online_url = nil,
}

function M.default_docset_dirs()
  local dirs = {}
  if vim.fn.has("win32") == 1 then
    table.insert(dirs, vim.fn.expand("~/AppData/Local/Zeal/Zeal/docsets"))
  else
    table.insert(dirs, vim.fn.expand("~/.local/share/Zeal/Zeal/docsets"))
    table.insert(dirs, vim.fn.expand("~/Library/Application Support/Zeal/Zeal/docsets"))
  end
  return dirs
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  if type(M.opts.docset_dirs) == "function" then
    M.opts.docset_dirs = M.opts.docset_dirs()
  end
  if #M.opts.docset_dirs == 0 then
    M.opts.docset_dirs = M.default_docset_dirs()
  end
end

return M
