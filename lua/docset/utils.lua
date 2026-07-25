local M = {}

function M.normalize_path(p)
  return (p:gsub("\\", "/"))
end

function M.exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "docset" })
end

return M
