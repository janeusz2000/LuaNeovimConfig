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

local function build_prompt(before, selected, after, ft, region_label, scope_type, file_path, cursor_line)
    local region_line = region_label or "Selected region"
    local instruction = "Return ONLY the replacement code for the selected region."
    local scope_line = nil
    if region_label == "Scope region" then
        instruction = "Return ONLY the replacement code for the scoped region."
        if scope_type and scope_type ~= "" then
            scope_line = "Scope node: " .. scope_type
        end
    end
    local status_prefix = vim.g.codex_status_prefix or "STATUS:"
    local location_line = nil
    if file_path and cursor_line then
        location_line = string.format("Location: %s:%d", file_path, cursor_line)
    end

    local parts = {
        "You are completing code in a Neovim buffer.",
        "Filetype: " .. (ft or "unknown"),
        instruction,
        "Do not include markdown or backticks.",
        "Do not include commentary or status lines in the replacement code.",
    }
    if vim.g.codex_status_updates == true then
        table.insert(parts, "While working, emit brief status updates on their own line prefixed with " .. status_prefix .. ".")
        table.insert(parts, "Do not include status lines in the replacement code.")
    end
    if location_line then
        table.insert(parts, location_line)
    end
    if scope_line then
        table.insert(parts, scope_line)
    end
    table.insert(parts, "")
    table.insert(parts, region_line .. ":")
    table.insert(parts, selected)
    table.insert(parts, "")
    table.insert(parts, "Replacement code:")
    return table.concat(parts, "\n")
end

local function build_prompt_buffer(full_text, target_text, ft, target_label, target_range, scope_type, file_path, cursor_line)
    local scope_line = nil
    if scope_type and scope_type ~= "" then
        scope_line = "Scope node: " .. scope_type
    end
    local range_line = nil
    if target_range and target_range[1] then
        range_line = string.format("Edit target lines: %d-%d", target_range[1] + 1, target_range[3] + 1)
    end
    local status_prefix = vim.g.codex_status_prefix or "STATUS:"
    local location_line = nil
    if file_path and cursor_line then
        location_line = string.format("Location: %s:%d", file_path, cursor_line)
    end
    local parts = {
        "You are editing a Neovim buffer.",
        "Filetype: " .. (ft or "unknown"),
        "Return ONLY the full updated buffer.",
        "Do not include markdown, backticks, commentary, or status lines.",
        "Remember to check if the code will compile / works after the change.",
        "Please fix the code when its' not sematically correct"
    }
    if vim.g.codex_status_updates == true then
        table.insert(parts, "While working, emit brief status updates on their own line prefixed with " .. status_prefix .. ".")
        table.insert(parts, "Do not include status lines in the updated buffer.")
    end
    if location_line then
        table.insert(parts, location_line)
    end
    if scope_line then
        table.insert(parts, scope_line)
    end
    if range_line then
        table.insert(parts, range_line)
    end
    table.insert(parts, "")
    table.insert(parts, (target_label or "Edit target") .. ":")
    table.insert(parts, target_text)
    table.insert(parts, "")
    table.insert(parts, "Full buffer:")
    table.insert(parts, full_text)
    table.insert(parts, "")
    table.insert(parts, "Updated buffer:")
    return table.concat(parts, "\n")
end

local function get_cmd()
    local cmd = vim.g.codex_command or { "codex", "exec", "-" }
    if type(cmd) == "string" then
        local parts = vim.split(cmd, " ", { plain = true, trimempty = true })
        local has_json = false
        for _, part in ipairs(parts) do
            if part == "--json" then
                has_json = true
                break
            end
        end
        if vim.g.codex_use_json == true and not has_json then
            table.insert(parts, 3, "--json")
        end
        return parts
    end
    local has_json = false
    for _, part in ipairs(cmd) do
        if part == "--json" then
            has_json = true
            break
        end
    end
    if vim.g.codex_use_json == true and not has_json then
        table.insert(cmd, 3, "--json")
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
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        id = id,
        virt_text = { { text, "Comment" } },
        virt_text_pos = "eol",
    })
end

local function trim_display(text, max_len)
    local len = vim.fn.strchars(text)
    if len <= max_len then
        return text
    end
    return vim.fn.strcharpart(text, len - max_len, max_len)
end

local function sanitize_status_text(text)
    local cleaned = text:gsub("%*%*", ""):gsub("[%s]+", " ")
    return cleaned
end

local function sanitize_replacement(replacement, selected_text)
    if replacement == "" or selected_text == "" then
        return replacement
    end
    local rep = replacement:gsub("\r", "")
    local sel = selected_text:gsub("\r", "")
    local rep_trim = rep:gsub("%s+$", "")
    local sel_trim = sel:gsub("%s+$", "")
    if rep_trim == sel_trim then
        return replacement
    end
    if #rep_trim > #sel_trim and rep_trim:sub(-#sel_trim) == sel_trim then
        local new_rep = rep_trim:sub(1, #rep_trim - #sel_trim)
        new_rep = new_rep:gsub("%s+$", "")
        return new_rep
    end
    return replacement
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
        return nil, nil, nil, nil, nil, err
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
            return srow, scol, erow, ecol, cur:type(), nil
        end
        cur = cur:parent()
    end

    return nil, nil, nil, nil, nil, "No scope node found at cursor"
end

local function get_fallback_range(buf, fallback)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local context_lines = vim.g.codex_fallback_context_lines or 0
    local until_type_change = vim.g.codex_fallback_parent_until_type_change == true
    if fallback == "line" then
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        local ecol = vim.fn.strchars(line)
        local srow, erow = row, row
        if context_lines > 0 then
            local line_count = vim.api.nvim_buf_line_count(buf)
            srow = math.max(0, row - context_lines)
            erow = math.min(line_count - 1, row + context_lines)
            local end_line = vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1] or ""
            ecol = vim.fn.strchars(end_line)
        end
        return srow, 0, erow, ecol, "line", nil
    end

    local node, err = get_node_at_cursor(buf)
    if not node then
        -- If Treesitter isn't available, fall back to current line.
        local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
        local ecol = vim.fn.strchars(line)
        local srow, erow = row, row
        if context_lines > 0 then
            local line_count = vim.api.nvim_buf_line_count(buf)
            srow = math.max(0, row - context_lines)
            erow = math.min(line_count - 1, row + context_lines)
            local end_line = vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1] or ""
            ecol = vim.fn.strchars(end_line)
        end
        return srow, 0, erow, ecol, "line", err
    end
    local srow, scol, erow, ecol = node:range()
    srow, scol, erow, ecol = clamp_range(buf, srow, scol, erow, ecol)
    if until_type_change then
        local target = node
        local parent = target:parent()
        while parent and parent:type() == target:type() do
            target = parent
            parent = parent:parent()
        end
        if parent then
            target = parent
        end
        srow, scol, erow, ecol = target:range()
        srow, scol, erow, ecol = clamp_range(buf, srow, scol, erow, ecol)
    end
    if context_lines > 0 then
        local line_count = vim.api.nvim_buf_line_count(buf)
        srow = math.max(0, srow - context_lines)
        erow = math.min(line_count - 1, erow + context_lines)
        local end_line = vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1] or ""
        ecol = vim.fn.strchars(end_line)
        scol = 0
    end
    return srow, scol, erow, ecol, node:type(), nil
end

function M.complete_selection_or_scope()
    if active_job then
        vim.notify("Codex is already running.", vim.log.levels.WARN)
        return
    end

    local buf = vim.api.nvim_get_current_buf()
    local mode = vim.fn.mode()
    local in_visual = mode == "v" or mode == "V" or mode == "\22"
    local replace_mode = vim.g.codex_replace_mode or "region"
    local range = nil

    local scope_err = nil
    local scope_type = nil
    local used_fallback = false
    if in_visual then
        range = { get_visual_range(buf) }
    else
        local srow, scol, erow, ecol, found_type, err = get_scope_range(buf)
        range = { srow, scol, erow, ecol }
        scope_err = err
        scope_type = found_type
        if not range[1] then
            local fallback = vim.g.codex_scope_fallback or "node"
            local fsrow, fscol, ferow, fecol, ftype, ferr = get_fallback_range(buf, fallback)
            if fsrow then
                range = { fsrow, fscol, ferow, fecol }
                scope_type = ftype
                used_fallback = true
            else
                scope_err = ferr or scope_err
            end
        end
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
    local target = vim.api.nvim_buf_get_text(buf, srow, scol, erow, ecol, {})
    local target_text = table.concat(target, "\n")

    if replace_mode ~= "buffer" and target_text == "" then
        vim.notify("Selection is empty.", vim.log.levels.WARN)
        return
    end

    local prompt = nil
    local file_path = vim.api.nvim_buf_get_name(buf)
    if file_path == "" then
        file_path = nil
    end
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    if replace_mode == "buffer" then
        local full = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local full_text = table.concat(full, "\n")
        local target_label = in_visual and "Selected region" or "Scope region"
        if used_fallback then
            target_label = "Scope region (fallback)"
        end
        prompt = build_prompt_buffer(full_text, target_text, vim.bo[buf].filetype, target_label, range, scope_type, file_path, cursor_row)
    else
        local region_label = in_visual and "Selected region" or "Scope region"
        if used_fallback then
            region_label = "Scope region (fallback)"
        end
        prompt = build_prompt("", target_text, "", vim.bo[buf].filetype, region_label, scope_type, file_path, cursor_row)
    end

    local mark_id = vim.api.nvim_buf_set_extmark(buf, ns, srow, 0, {})
    local status_text = "Codex: thinking..."
    set_inline_status(buf, srow, mark_id, status_text)

    local function last_nonempty(lines)
        for i = #lines, 1, -1 do
            if lines[i] ~= "" then
                return lines[i]
            end
        end
        return nil
    end

    local output = {}
    local stderr = {}
    local stream = {}
    local max_stream = vim.g.codex_stream_lines or 8
    local log_lines = {}
    local log_limit = vim.g.codex_log_limit or 5000
    local log_path = make_log_path()
    last_log_path = log_path
    vim.fn.writefile({}, log_path)
    local cmd = get_cmd()
    local status_prefix = vim.g.codex_status_prefix or "STATUS:"
    local status_updates = vim.g.codex_status_updates == true
    local saw_status = false
    local status_prefix_len = #status_prefix
    local use_json = vim.g.codex_use_json == true
    local status_timer = nil
    local start_time = vim.loop.hrtime()
    local last_status_update = start_time
    local status_tick_ms = vim.g.codex_status_tick_ms or 1000

    local function is_status_line(line)
        return status_updates and vim.startswith(line, status_prefix)
    end

    local function strip_status_prefix(line)
        return line:sub(status_prefix_len + 1):gsub("^%s+", "")
    end

    local function note_status_update()
        last_status_update = vim.loop.hrtime()
    end

    local function stop_status_timer()
        if status_timer then
            status_timer:stop()
            status_timer:close()
            status_timer = nil
        end
    end

    local function append_log_line(line)
        push_log_line(log_lines, line, log_limit)
        vim.fn.writefile({ line }, log_path, "a")
    end

    local function handle_json_line(line)
        local ok, event = pcall(vim.fn.json_decode, line)
        if not ok or type(event) ~= "table" then
            return false
        end
        if event.type == "thread.started" then
            saw_status = true
            status_text = "Codex: starting..."
            note_status_update()
            append_log_line("[status] thread.started")
            return true
        end
        if event.type == "turn.started" then
            saw_status = true
            status_text = "Codex: working..."
            note_status_update()
            append_log_line("[status] turn.started")
            return true
        end
        local item = event.item
        if event.type == "item.completed" and type(item) == "table" then
            if item.type == "reasoning" and type(item.text) == "string" and status_updates then
                saw_status = true
                local display = trim_display(sanitize_status_text(item.text), 80)
                status_text = "Codex: " .. display
                note_status_update()
                append_log_line("[status] " .. item.text)
            elseif item.type == "agent_message" and type(item.text) == "string" then
                table.insert(output, item.text)
                table.insert(stream, item.text)
                append_log_line("[stdout] " .. item.text)
            end
        end
        return true
    end

    local function should_skip_plain_line(line)
        return line == "Replacement code:" or line == "Updated buffer:" or line == "Full buffer:"
    end

    local function strip_non_code_lines(lines)
        local cleaned = {}
        for _, chunk in ipairs(lines) do
            local chunk_lines = vim.split(chunk, "\n", { plain = true, trimempty = false })
            for _, line in ipairs(chunk_lines) do
                if not is_status_line(line) and not vim.startswith(line, "Commentary:") then
                    table.insert(cleaned, line)
                end
            end
        end
        return cleaned
    end

    local function append_output(data, store, prefix)
        if not data then
            return
        end

        if store == output then
            for _, line in ipairs(data) do
                if line ~= "" then
                    if use_json and handle_json_line(line) then
                        goto continue
                    end
                    if use_json and should_skip_plain_line(line) then
                        append_log_line("[stdout] " .. line)
                        goto continue
                    end
                    if is_status_line(line) then
                        saw_status = true
                        local display = trim_display(strip_status_prefix(line), 80)
                        status_text = "Codex: " .. display
                        note_status_update()
                        append_log_line("[status] " .. line)
                    else
                        table.insert(store, line)
                        table.insert(stream, line)
                        append_log_line("[stdout] " .. line)
                    end
                    ::continue::
                end
            end
            if not saw_status and not use_json then
                local last_line = last_nonempty(store)
                if last_line then
                    local display = trim_display(last_line, 80)
                    status_text = "Codex: " .. display
                end
            end
        elseif store == stderr then
            for _, line in ipairs(data) do
                if line ~= "" then
                    append_log_line("[stderr] " .. line)
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
                stop_status_timer()
                if not vim.api.nvim_buf_is_valid(buf) then
                    return
                end

                if code ~= 0 then
                    status_text = "Codex: failed"
                    set_inline_status(buf, srow, mark_id, status_text, stream)
                    return
                end

                local cleaned_output = strip_non_code_lines(output)
                local replacement = table.concat(cleaned_output, "\n")
                if replace_mode ~= "buffer" then
                    replacement = sanitize_replacement(replacement, target_text)
                end
                if replacement == "" then
                    status_text = "Codex: no output"
                    set_inline_status(buf, srow, mark_id, status_text, stream)
                    return
                end

                local lines = vim.split(replacement, "\n", { plain = true, trimempty = false })
                if replace_mode == "buffer" then
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                else
                    vim.api.nvim_buf_set_text(buf, srow, scol, erow, ecol, lines)
                end
                vim.api.nvim_buf_del_extmark(buf, ns, mark_id)
            end)
        end,
    })

    if active_job <= 0 then
        active_job = nil
        status_text = "Codex: failed to start"
        set_inline_status(buf, srow, mark_id, status_text, stream)
        stop_status_timer()
        return
    end

    status_timer = vim.loop.new_timer()
    status_timer:start(0, status_tick_ms, vim.schedule_wrap(function()
        if not vim.api.nvim_buf_is_valid(buf) then
            stop_status_timer()
            return
        end
        if saw_status then
            stop_status_timer()
            return
        end
        local elapsed = math.floor((vim.loop.hrtime() - start_time) / 1e9)
        status_text = "Codex: working... " .. elapsed .. "s"
        set_inline_status(buf, srow, mark_id, status_text, stream)
    end))

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
