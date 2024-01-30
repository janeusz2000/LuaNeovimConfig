--[[
-- ===============================
-- This will trigger only if using neovim from Wsl2 instance.
--
-- it is based on workaround found in:
-- https://github.com/microsoft/WSL/issues/4440
--
-- ===============================
--]]
local mountedWindowsPath = "/mnt/c/widows/"
local win32yankPath = "/usr/bin/win32yank.exe"

local installationMessage = [[
please execute shell script:
curl -sLo /tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip
unzip -p /tmp/win32yank.zip win32yank.exe > /tmp/win32yank.exe
chmod +x /tmp/win32yank.exe
sudo mv /tmp/win32yank.exe /usr/bin/win32yank.exe
]]

local function doesExist(path)
    local f  = io.popen("cd " .. path)
    local ff = f:read("*all")
    return not ff:find("itemNotFoundExpection")
end

local function isWslInstance()
    return doesExist(mountedWindowsPath)
end

if isWslInstance() then
    if not doesExist(win32yankPath) then
       print(installationMessage)
    end
    vim.opt.clipboard = "unnamedplus"
end 
