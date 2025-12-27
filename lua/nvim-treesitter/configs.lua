local M = {}

local function get_config()
  return vim.g._nvim_treesitter_config or {}
end

function M.get_module(name)
  local cfg = get_config()[name]
  if cfg == nil then
    return {}
  end
  return cfg
end

function M.is_enabled(module, lang, bufnr)
  local cfg = get_config()[module]
  if cfg == nil then
    return false
  end
  if cfg.enable == false then
    return false
  end
  if type(cfg.enable) == "table" and not vim.tbl_contains(cfg.enable, lang) then
    return false
  end
  if type(cfg.disable) == "function" then
    local ok, disabled = pcall(cfg.disable, lang, bufnr)
    if ok and disabled then
      return false
    end
  elseif type(cfg.disable) == "table" and vim.tbl_contains(cfg.disable, lang) then
    return false
  end
  return true
end

return M
