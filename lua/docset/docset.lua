local M = {}
local utils = require("docset.utils")
local plist = require("docset.plist")

-- Search for .docset bundles. Multi dirs supported; non-recursive (one level deep).
function M.discover(dirs)
  local docsets = {}
  for _, dir in ipairs(dirs) do
    dir = utils.normalize_path(vim.fn.expand(dir))
    if vim.fn.isdirectory(dir) == 1 then
      local pattern = dir .. "/*.docset"
      local matches = vim.fn.glob(pattern, true, true)
      for _, path in ipairs(matches) do
        local ds = M.parse(path)
        if ds then
          table.insert(docsets, ds)
        end
      end
    end
  end
  table.sort(docsets, function(a, b)
    return (a.title or a.name):lower() < (b.title or b.name):lower()
  end)
  return docsets
end

function M.parse(path)
  path = utils.normalize_path(path)
  local folder = vim.fn.fnamemodify(path, ":t")
  local name = folder:gsub("%.docset$", "")
  local info = plist.read(path .. "/Contents/Info.plist")
  local identifier = info.CFBundleIdentifier or name:lower()
  local title = info.CFBundleName or name:gsub("_", " ")
  local version = info.DocSetPlatformVersion or info.CFBundleVersion or ""
  return {
    name = name,
    title = title,
    identifier = identifier,
    version = version,
    path = path,
    db_path = path .. "/Contents/Resources/docSet.dsidx",
    doc_dir = path .. "/Contents/Resources/Documents",
  }
end

return M
