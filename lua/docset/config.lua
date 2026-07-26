local M = {}

M.opts = {
  docset_dirs = {},
  picker = "fzf",
  browser = "",
  window = {
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
  include_documents = nil,
  exclude_documents = nil,
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
end

return M
