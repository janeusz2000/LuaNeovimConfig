local M = {}

local ns = vim.api.nvim_create_namespace("animator_codex")
local active_job = nil
local last_log_path = nil

local function normalize_range(srow, scol, erow, ecol)
    if srow > erow or (srow == erow and scol > ecol) then
        return erow, ecol, srow, scol
    end
    return srow, scol, erow, ecol
end

local function clamp_range(buf, srow, scol, erow, ecol)
    local line = vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1] or ""
    local max_col = vim.fn.strchars(line)
    if ecol > max_col then
        ecol = max_col
    end
    if ecol < 0 then
        ecol = 0
    end
    if scol < 0 then
        scol = 0
    end
    return srow, scol, erow, ecol
end

local function get_visual_range(buf)
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    local srow = start_pos[2] - 1
    local scol = start_pos[3] - 1
    local erow = end_pos[2] - 1
    local ecol = end_pos[3]

    if srow < 0 or erow < 0 then
        return nil
    end

    srow, scol, erow, ecol = normalize_range(srow, scol, erow, ecol)

    local line_count = vim.api.nvim_buf_line_count(buf)
    if srow >= line_count or erow >= line_count then
        return nil
    end

    if ecol < 0 then
        ecol = 0
    end

    return clamp_range(buf, srow, scol, erow, ecol)
end

local function get_context(buf, srow, erow, context_lines)
    local total = vim.api.nvim_buf_line_count(buf)
    local before_start = math.max(0, srow - context_lines)
    local after_end = math.min(total, erow + 1 + context_lines)

    local before = vim.api.nvim_buf_get_lines(buf, before_start, srow, false)
    local after = vim.api.nvim_buf_get_lines(buf, erow + 1, after_end, false)

    return table.concat(before, "\n"), table.concat(after, "\n")
end

local function build_prompt(before, selected, after, ft)
    local parts = {
        "You are completing code in a Neovim buffer.",
        "Filetype: " .. (ft or "unknown"),
        "Return ONLY the replacement code for the selected region.",
        "Do not include markdown, backticks, or extra commentary.",
        "",
        "Context before:",
        before,
        "",
        "Selected region:",
        selected,
        "",
        "Context after:",
        after,
        "",
        "Replacement code:",
    }
    return table.concat(parts, "\n")
end

local function get_cmd()
    local cmd = vim.g.codex_command or { "codex", "exec", "-" }
    if type(cmd) == "string" then
        return vim.split(cmd, " ", { plain = true, trimempty = true })
    end
    return cmd
end

local function ensure_log_dir()
    local dir = vim.g.codex_log_dir or (vim.fn.stdpath("state") .. "/codex")
    vim.fn.mkdir(dir, "p")
    return dir
end

local function make_log_path()
    local dir = ensure_log_dir()
    local stamp = os.date("%Y%m%d_%H%M%S")
    return dir .. "/session_" .. stamp .. ".log"
end

local function push_log_line(lines, line, limit)
    table.insert(lines, line)
    if #lines > limit then
        table.remove(lines, 1)
    end
end

local function set_inline_status(buf, row, id, text, lines)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local virt_lines = nil
    if lines then
        virt_lines = {}
        for _, line in ipairs(lines) do
            table.insert(virt_lines, { { line, "Comment" } })
        end
    end
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        id = id,
        virt_text = { { text, "Comment" } },
        virt_text_pos = "eol",
        virt_lines = virt_lines,
        virt_lines_above = false,
    })
end

local function trim_display(text, max_len)
    local len = vim.fn.strchars(text)
    if len <= max_len then
        return text
    end
    return vim.fn.strcharpart(text, len - max_len, max_len)
end

local function get_node_at_cursor(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]

    if vim.treesitter.get_node then
        local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
        if ok then
            return node
        end
    end

    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then
        return nil, "Treesitter parser missing for " .. (vim.bo[buf].filetype or "unknown")
    end

    local tree = parser:parse()[1]
    if not tree then
        return nil, "Treesitter parse failed"
    end

    return tree:root():named_descendant_for_range(row, col, row, col)
end

local function get_scope_range(buf)
    local node, err = get_node_at_cursor(buf)
    if not node then
        return nil, nil, nil, nil, err
    end

    local scope_nodes = vim.g.codex_scope_nodes or {
        "function_definition",
        "function_declaration",
        "function",
        "method_definition",
        "method_declaration",
        "method",
        "class_definition",
        "class_declaration",
        "struct_definition",
        "struct_specifier",
        "interface_declaration",
        "enum_declaration",
        "impl_item",
        "module",
        "namespace_definition",
        "test_definition",
        "test_item",
    }

    local scope_set = {}
    for _, name in ipairs(scope_nodes) do
        scope_set[name] = true
    end

    local cur = node
    while cur do
        if scope_set[cur:type()] then
            local srow, scol, erow, ecol = cur:range()
            srow, scol, erow, ecol = clamp_range(buf, srow, scol, erow, ecol)
            return srow, scol, erow, ecol, nil
        end
        cur = cur:parent()
    end

    return nil, nil, nil, nil, "No scope node found at cursor"
end

function M.complete_selection_or_scope()
    if active_job then
        vim.notify("Codex is already running.", vim.log.levels.WARN)
        return
    end

    local buf = vim.api.nvim_get_current_buf()
    local mode = vim.fn.mode()
    local in_visual = mode == "v" or mode == "V" or mode == "\22"
    local range = nil

    local scope_err = nil
    if in_visual then
        range = { get_visual_range(buf) }
    else
        local srow, scol, erow, ecol, err = get_scope_range(buf)
        range = { srow, scol, erow, ecol }
        scope_err = err
    end

    if not range[1] then
        if scope_err then
            vim.notify(scope_err, vim.log.levels.WARN)
        else
            vim.notify("No selection or scope found at cursor.", vim.log.levels.WARN)
        end
        return
    end

    local srow, scol, erow, ecol = range[1], range[2], range[3], range[4]
    local selected = vim.api.nvim_buf_get_text(buf, srow, scol, erow, ecol, {})
    local selected_text = table.concat(selected, "\n")

    if selected_text == "" then
        vim.notify("Selection is empty.", vim.log.levels.WARN)
        return
    end

    local context_lines = vim.g.codex_context_lines or 20
    local before, after = get_context(buf, srow, erow, context_lines)
    local prompt = build_prompt(before, selected_text, after, vim.bo[buf].filetype)

    local mark_id = vim.api.nvim_buf_set_extmark(buf, ns, srow, 0, {})
    local status_text = "Codex: thinking..."
    set_inline_status(buf, srow, mark_id, status_text)

    local output = {}
    local stderr = {}
    local stream = {}
    local max_stream = vim.g.codex_stream_lines or 8
    local log_lines = {}
    local log_limit = vim.g.codex_log_limit or 5000
    local log_path = make_log_path()
    local cmd = get_cmd()

    local function append_output(data, store, prefix)
        if not data then
            return
        end
        for _, line in ipairs(data) do
            if line ~= "" then
                table.insert(store, line)
            end
        end

        if store == output then
            local joined = table.concat(store, "\n")
            local display = trim_display(joined, 80)
            status_text = "Codex: " .. display
            for _, line in ipairs(data) do
                if line ~= "" then
                    table.insert(stream, line)
                    push_log_line(log_lines, "[stdout] " .. line, log_limit)
                end
            end
        elseif store == stderr then
            for _, line in ipairs(data) do
                if line ~= "" then
                    push_log_line(log_lines, "[stderr] " .. line, log_limit)
                end
            end
            return
        end

        if #stream > max_stream then
            stream = { unpack(stream, #stream - max_stream + 1, #stream) }
        end

        set_inline_status(buf, srow, mark_id, status_text, stream)
    end

    active_job = vim.fn.jobstart(cmd, {
        stdin = "pipe",
        stdout_buffered = false,
        stderr_buffered = false,
        pty = vim.g.codex_use_pty == true,
        on_stdout = function(_, data)
            append_output(data, output)
        end,
        on_stderr = function(_, data)
            append_output(data, stderr, "Codex error: ")
        end,
        on_exit = function(_, code)
            active_job = nil
            vim.schedule(function()
                if not vim.api.nvim_buf_is_valid(buf) then
                    return
                end

                if code ~= 0 then
                    status_text = "Codex: failed"
                    set_inline_status(buf, srow, mark_id, status_text, stream)
                    vim.fn.writefile(log_lines, log_path)
                    last_log_path = log_path
                    return
                end

                local replacement = table.concat(output, "\n")
                if replacement == "" then
                    status_text = "Codex: no output"
                    set_inline_status(buf, srow, mark_id, status_text, stream)
                    vim.fn.writefile(log_lines, log_path)
                    last_log_path = log_path
                    return
                end

                local lines = vim.split(replacement, "\n", { plain = true, trimempty = false })
                vim.api.nvim_buf_set_text(buf, srow, scol, erow, ecol, lines)
                vim.api.nvim_buf_del_extmark(buf, ns, mark_id)
                vim.fn.writefile(log_lines, log_path)
                last_log_path = log_path
            end)
        end,
    })

    if active_job <= 0 then
        active_job = nil
        status_text = "Codex: failed to start"
        set_inline_status(buf, srow, mark_id, status_text, stream)
        return
    end

    vim.fn.chansend(active_job, prompt)
    vim.fn.chanclose(active_job, "stdin")
end

function M.complete_visual()
    return M.complete_selection_or_scope()
end

function M.open_last_log()
    if not last_log_path or vim.fn.filereadable(last_log_path) == 0 then
        vim.notify("Codex log not found.", vim.log.levels.WARN)
        return
    end
    vim.cmd("split " .. vim.fn.fnameescape(last_log_path))
end

return M
