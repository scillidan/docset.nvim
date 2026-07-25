local M = {}

function M.open(entries, opts)
  local cfg = require("docset.config").opts
  if cfg.picker == "telescope" then
    local ok, telescope_err = pcall(require, "telescope")
    if not ok then
      require("docset.utils").notify("telescope not found", vim.log.levels.ERROR)
      return
    end
    local telescope_picker = require("docset.picker.telescope")
    local ok_t, t_err = pcall(telescope_picker.open, entries, opts)
    if not ok_t then
      require("docset.utils").notify("telescope picker failed: " .. tostring(t_err), vim.log.levels.ERROR)
    end
    return
  end
  if cfg.picker == "fzf" then
    local ok, fzf_err = pcall(require, "fzf-lua")
    if not ok then
      require("docset.utils").notify("fzf-lua not found", vim.log.levels.ERROR)
      return
    end
    local fzf_picker = require("docset.picker.fzf")
    local ok_fzf, fzf_err2 = pcall(fzf_picker.open, entries, opts)
    if not ok_fzf then
      require("docset.utils").notify("fzf picker failed: " .. tostring(fzf_err2), vim.log.levels.ERROR)
    end
    return
  end
  require("docset.utils").notify("Unsupported picker: " .. tostring(cfg.picker), vim.log.levels.ERROR)
end

return M
