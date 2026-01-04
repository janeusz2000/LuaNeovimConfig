local M = {}

local namespace = vim.api.nvim_create_namespace("animator_codex")
local last_log_path = nil
local default_status_hl = "AnimatorCodexStatus"

vim.api.nvim_set_hl(0, default_status_hl, { fg = "#bfbfbf", default = true })

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

local function get_full_buffer_range(bufnr)
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    local line = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1] or ""
    return {
        start_row = 1,
        start_col = 0,
        end_row = last_line,
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
    local buf_last_line = vim.api.nvim_buf_line_count(bufnr)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local status_row
    if range.start_row == 1 and range.end_row == buf_last_line then
        status_row = math.max(cursor[1] - 1, 0)
    else
        status_row = math.max(range.end_row - 1, 0)
    end
    local status_hl = vim.g.animator_codex_status_hl or default_status_hl
    return vim.api.nvim_buf_set_extmark(bufnr, namespace, status_row, 0, {
        id = extmark_id,
        virt_lines = { { { message, status_hl } } },
        virt_lines_above = false,
    })
end

local function clear_status(bufnr, extmark_id)
    if extmark_id then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, extmark_id)
    end
end

local function build_prompt(bufnr, range, scope_label, task_label, include_full_buffer)
    local buffer_path = vim.api.nvim_buf_get_name(bufnr)
    local buffer_dir = buffer_path ~= "" and vim.fn.fnamemodify(buffer_path, ":h") or vim.loop.cwd()
    local repo_root = resolve_repo_root(buffer_dir) or "unknown"
    local cursor = vim.api.nvim_win_get_cursor(0)
    local filetype = vim.bo[bufnr].filetype

    local selection_lines = get_text(bufnr, range)
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local scope_title = scope_label or "Selection"
    local task_title = task_label or "Replace the selected text in the current buffer with the correct output."
    local return_label = scope_label == "Current line"
            and "Return only the replacement text for the current line."
        or scope_label == "Full buffer"
            and "Return only the replacement text for the full buffer."
        or scope_label == "Context line"
            and "Return only the replacement text for the detected scope."
        or "Return only the replacement text for the selection."
    local should_include_full_buffer = include_full_buffer ~= false

    local prompt_lines = {
        "Task: " .. task_title,
        "Buffer path: " .. (buffer_path ~= "" and buffer_path or "unknown"),
        "Repo root: " .. repo_root,
        "Cursor: line " .. cursor[1] .. ", col " .. cursor[2],
        "Filetype: " .. (filetype ~= "" and filetype or "unknown"),
        "You may inspect repository context if needed.",
        "",
        scope_title .. ":",
    }
    vim.list_extend(prompt_lines, selection_lines)
    if should_include_full_buffer then
        vim.list_extend(prompt_lines, {
            "",
            "Full buffer:",
        })
        vim.list_extend(prompt_lines, buffer_lines)
    end
    vim.list_extend(prompt_lines, {
        "",
        return_label,
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
    local stderr_output_lines = {}
    local capture_stderr_output = false
    local extmark_id = nil
    local status_timer = nil
    local status_message = "Codex: initializing..."
    local start_time = vim.loop.hrtime()

    local function format_elapsed()
        local elapsed_ms = (vim.loop.hrtime() - start_time) / 1e6
        return string.format("%.1fs", elapsed_ms / 1000)
    end

    local function update_status()
        if not status_message then
            return
        end
        local message = string.format("%s (%s)", status_message, format_elapsed())
        extmark_id = set_status(bufnr, range, message, extmark_id)
    end

    status_timer = vim.loop.new_timer()
    status_timer:start(0, 200, function()
        vim.schedule(update_status)
    end)

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
                    if line:match("^%*%*.*%*%*$") then
                        local cleaned = vim.trim(line:gsub("^%*%*", ""):gsub("%*%*$", ""))
                        status_message = "Codex: " .. cleaned
                        append_log(log_path, status_message)
                        vim.schedule(update_status)
                    else
                        append_log(log_path, "stderr: " .. line)
                    end
                    if line == "codex" or line == "assistant" or line == "final" then
                        capture_stderr_output = true
                    elseif capture_stderr_output then
                        if line:match("^tokens used") or line == "exec" or line == "thinking"
                                or line == "user" or line:match("^mcp startup")
                                or line == "--------" then
                            capture_stderr_output = false
                        else
                            table.insert(stderr_output_lines, line)
                        end
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            vim.schedule(function()
                if status_timer then
                    status_timer:stop()
                    status_timer:close()
                    status_timer = nil
                end
                clear_status(bufnr, extmark_id)
                if exit_code ~= 0 then
                    vim.notify("Codex failed. See log: " .. log_path, vim.log.levels.ERROR)
                    append_log(log_path, "Exit code: " .. exit_code)
                    return
                end
                local output = table.concat(stdout_lines, "\n")
                if output == "" and #stderr_output_lines > 0 then
                    output = table.concat(stderr_output_lines, "\n")
                end
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
    local visual_range = get_visual_range(bufnr)
    local range = visual_range or get_fallback_range(bufnr)
    local prompt
    if visual_range then
        prompt = build_prompt(bufnr, range)
    else
        range = get_full_buffer_range(bufnr)
        prompt = build_prompt(
            bufnr,
            range,
            "Full buffer",
            "Complete the scope based on the context of the line under the cursor. The scope could be a class, method, function, comment, variable, or other logical block. Update the full buffer accordingly.",
            false
        )
    end
    start_job(bufnr, range, prompt)
end

function M.complete_full_buffer()
    local bufnr = vim.api.nvim_get_current_buf()
    local range = get_full_buffer_range(bufnr)
    local prompt = build_prompt(
        bufnr,
        range,
        "Full buffer",
        "Replace the full buffer with the generated output only in the context of given neovim cursor. Context could be inside a function, lambda, class, method or scope implementation.",
        false
    )
    start_job(bufnr, range, prompt)
end

function M.complete_current_line()
    M.complete_full_buffer()
end

function M.open_last_log()
    if not last_log_path then
        vim.notify("No Codex log available yet.", vim.log.levels.INFO)
        return
    end
    vim.cmd("edit " .. vim.fn.fnameescape(last_log_path))
end

return M
