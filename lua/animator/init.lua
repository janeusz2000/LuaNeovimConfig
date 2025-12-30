do
  local paths = vim.opt.runtimepath:get()
  local filtered = {}
  for _, p in ipairs(paths) do
    if not string.find(p, "/site/pack/packer/start/harpoon", 1, true) then
      table.insert(filtered, p)
    end
  end
  if #filtered ~= #paths then
    vim.opt.runtimepath = table.concat(filtered, ",")
  end
end

require("animator.set")
require("animator.remap")
require("animator.lazy_init")
