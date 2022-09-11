local M = {}

function M.getSymbolUnderTheCursor()
    -- arg: 0 in nvim_win_get_cursor() stands for current window 
    local cursorPosition = vim.api.nvim_win_get_cursor(0)
    -- currentPosition[2] points to column number
    local currentColumn = cursorPosition[2] + 1
    return vim.api.nvim_get_current_line():sub(currentColumn, currentColumn)
end

function M.checkWhiteSpaceOrEmptyUnderTheCursor()
    local currentSymbol = M.getSymbolUnderTheCursor()
    return currentSymbol == ' ' or currentSymbol == ''
end

function M.escapeVimTermcodes(cmd)
    return vim.api.nvim_replace_termcodes(cmd, true, false, true)
end




return M
