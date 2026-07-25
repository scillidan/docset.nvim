local M = {}

function M.read(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return {}
  end
  local content = table.concat(lines, "\n")
  local result = {}
  -- match <key>KEY</key> followed by <string>VALUE</string>
  for key, value in content:gmatch("<key>([^<]+)</key>%s*<string>([^<]+)</string>") do
    result[key] = value
  end
  return result
end

return M
