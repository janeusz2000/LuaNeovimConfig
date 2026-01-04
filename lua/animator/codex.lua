local M = {}

local namespace = vim.api.nvim_create_namespace("animator_codex")
local last_log_path = nil

local function append_log(path, line)
    if not path then
        return
    end
    local file = io.open(path, "a")
    if not file then
        return
    end
    file:write(line)
    if not line:match("\n$") then
        file:write("\n")
    end
    file:close()
end

local function resolve_repo_root(buf_dir)
    local cmd = { "git", "-C", buf_dir, "rev-parse", "--show-toplevel" }
    local output = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or not output[1] then
        return nil
    end
    return output[1]
end

local function get_visual_range(bufnr)
    local current_mode = vim.fn.mode()
    if current_mode ~= "v" and current_mode ~= "V" and current_mode ~= "\22" then
        return nil
    end
    local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
    local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")
    if start_pos[1] == 0 or end_pos[1] == 0 then
        return nil
    end

    local s_row, s_col = start_pos[1], start_pos[2]
    local e_row, e_col = end_pos[1], end_pos[2]

    if s_row > e_row or (s_row == e_row and s_col > e_col) then
        s_row, e_row = e_row, s_row
        s_col, e_col = e_col, s_col
    end

    local mode = vim.fn.visualmode()
    local end_line = vim.api.nvim_buf_get_lines(bufnr, e_row - 1, e_row, false)[1] or ""
    local end_col
    if mode == "V" then
        end_col = #end_line
    else
        end_col = e_col + 1
    end
    if end_col > #end_line then
        end_col = #end_line
    end
    if end_col < 0 then
        end_col = 0
    end

    return {
        start_row = s_row,
        start_col = math.max(s_col, 0),
        end_row = e_row,
        end_col = end_col,
    }
end

local function get_fallback_range(bufnr)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
    return {
        start_row = cursor[1],
        start_col = 0,
        end_row = cursor[1],
        end_col = #line,
    }
end

local function get_text(bufnr, range)
    return vim.api.nvim_buf_get_text(
        bufnr,
        range.start_row - 1,
        range.start_col,
        range.end_row - 1,
        range.end_col,
        {}
    )
end

local function set_status(bufnr, range, message, extmark_id)
    return vim.api.nvim_buf_set_extmark(bufnr, namespace, range.start_row - 1, 0, {
        id = extmark_id,
        virt_text = { { message, "Comment" } },
        virt_text_pos = "eol",
    })
end

local function clear_status(bufnr, extmark_id)
    if extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, extmark_id)
    end
end

local function build_prompt(bufnr, range)
    local buffer_path = vim.api.nvim_buf_get_name(bufnr)
    local buffer_dir = buffer_path ~= "" and vim.fn.fnamemodify(buffer_path, ":h") or vim.loop.cwd()
    local repo_root = resolve_repo_root(buffer_dir) or "unknown"
    local cursor = vim.api.nvim_win_get_cursor(0)
    local filetype = vim.bo[bufnr].filetype

    local selection_lines = get_text(bufnr, range)
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local prompt_lines = {
        "Task: Replace the selected text in the current buffer with the correct output.",
        "Buffer path: " .. (buffer_path ~= "" and buffer_path or "unknown"),
        "Repo root: " .. repo_root,
        "Cursor: line " .. cursor[1] .. ", col " .. cursor[2],
        "Filetype: " .. (filetype ~= "" and filetype or "unknown"),
        "You may inspect repository context if needed.",
        "",
        "Selection:",
    }
    vim.list_extend(prompt_lines, selection_lines)
    vim.list_extend(prompt_lines, {
        "",
        "Full buffer:",
    })
    vim.list_extend(prompt_lines, buffer_lines)
    vim.list_extend(prompt_lines, {
        "",
        "Return only the replacement text for the selection.",
        "Do not include markdown, backticks, commentary, or status lines.",
    })

    return table.concat(prompt_lines, "\n"), repo_root, buffer_dir
end

local function replace_range(bufnr, range, new_text)
    local new_lines = {}
    if new_text ~= "" then
        new_lines = vim.split(new_text, "\n", { plain = true })
    end
    vim.api.nvim_buf_set_text(
        bufnr,
        range.start_row - 1,
        range.start_col,
        range.end_row - 1,
        range.end_col,
        new_lines
    )
end

local function start_job(bufnr, range, prompt)
    local buffer_path = vim.api.nvim_buf_get_name(bufnr)
    local buffer_dir = buffer_path ~= "" and vim.fn.fnamemodify(buffer_path, ":h") or vim.loop.cwd()
    local repo_root = resolve_repo_root(buffer_dir)
    local job_cwd = repo_root or buffer_dir

    local log_path = vim.fn.tempname() .. ".codex.log"
    last_log_path = log_path

    append_log(log_path, "Codex invocation started at " .. vim.fn.strftime("%Y-%m-%d %H:%M:%S"))
    append_log(log_path, "CWD: " .. job_cwd)
    append_log(log_path, "Buffer: " .. (buffer_path ~= "" and buffer_path or "unknown"))
    append_log(log_path, "Prompt:")
    append_log(log_path, prompt)

    local command = { "codex", "exec", "--cd", job_cwd, "-" }
    append_log(log_path, "Command: " .. table.concat(command, " "))

    local stdout_lines = {}
    local extmark_id = set_status(bufnr, range, "Codex: I got It!", nil)

    local job_id = vim.fn.jobstart(command, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if not data then
                return
            end
            for _, line in ipairs(data) do
                if line ~= "" then
                    table.insert(stdout_lines, line)
                    append_log(log_path, "stdout: " .. line)
                end
            end
        end,
        on_stderr = function(_, data)
            if not data then
                return
            end
            for _, line in ipairs(data) do
                if line ~= "" then
                    append_log(log_path, "stderr: " .. line)
                    vim.schedule(function()
                        extmark_id = set_status(bufnr, range, "Codex: " .. line, extmark_id)
                    end)
                end
            end
        end,
        on_exit = function(_, exit_code)
            vim.schedule(function()
                clear_status(bufnr, extmark_id)
                if exit_code ~= 0 then
                    vim.notify("Codex failed. See log: " .. log_path, vim.log.levels.ERROR)
                    append_log(log_path, "Exit code: " .. exit_code)
                    return
                end
                local output = table.concat(stdout_lines, "\n")
                replace_range(bufnr, range, output)
                append_log(log_path, "Exit code: " .. exit_code)
                append_log(log_path, "Codex invocation finished.")
            end)
        end,
    })

    if job_id <= 0 then
        clear_status(bufnr, extmark_id)
        vim.notify("Failed to start Codex job", vim.log.levels.ERROR)
        return
    end

    vim.fn.chansend(job_id, prompt)
    vim.fn.chanclose(job_id, "stdin")
end

function M.complete_selection_or_scope()
    local bufnr = vim.api.nvim_get_current_buf()
    local range = get_visual_range(bufnr) or get_fallback_range(bufnr)
    local prompt = build_prompt(bufnr, range)
    start_job(bufnr, range, prompt)
end

function M.open_last_log()
    if not last_log_path then
        vim.notify("No Codex log available yet.", vim.log.levels.INFO)
        return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(last_log_path))
end

return M
