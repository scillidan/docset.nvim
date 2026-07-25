local M = {}

function M.load_entries(docset)
  if vim.fn.filereadable(docset.db_path) == 0 then
    return {}
  end

  -- Prefer sqlite.lua (commonly used on Windows without external sqlite3)
  local ok, sqlite = pcall(require, "sqlite")
  if ok then
    local db = sqlite:open(docset.db_path)
    local entries = db:eval("SELECT name, type, path FROM searchIndex ORDER BY name")
    db:close()
    if type(entries) == "table" then
      for _, e in ipairs(entries) do
        e.docset = docset
      end
      return entries
    end
  end

  -- Fallback: sqlite3 CLI
  local cmd = { "sqlite3", docset.db_path, "-json", "SELECT name, type, path FROM searchIndex ORDER BY name" }
  local out = vim.fn.system(cmd)
  if vim.v.shell_error == 0 and out and out ~= "" then
    local decoded = vim.json.decode(out)
    if type(decoded) == "table" then
      for _, e in ipairs(decoded) do
        e.docset = docset
      end
      return decoded
    end
  end

  return {}
end

return M
