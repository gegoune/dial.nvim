local util = require("./util")
local default = require("./default")
local augends = require("./augends")

local M = {}

function M.increment_normal(addend, override_searchlist)
    -- signature
    vim.validate{
        -- 加数。
        addend = {addend, "number"},
        -- 対象とする被加数の種類のリスト (optional)。
        override_searchlist = {override_searchlist, "table", true},
    }
    util.validate_list("override searchlist", override_searchlist, "string")

    -- 対象の searchlist 文字列に対応する augends のリストを取得
    if override_searchlist then
        searchlist = override_searchlist
    else
        searchlist = default.searchlist.normal
    end
    local search_augends = assert(util.try_get_keys(augends, searchlist))

    -- 現在のカーソル位置、行内容を取得
    local curpos = vim.call('getcurpos')
    local cursor = curpos[3]
    local line = vim.fn.getline('.')

    -- 更新後の行内容、新たなカーソル位置を取得
    cursor, line = get_incremented_text(cursor, line, addend, search_augends)

    -- 対象行の内容及びカーソル位置を更新
    if line ~= nil then
        vim.fn.setline('.', line)
    end
    if cursor ~=nil then
        vim.fn.setpos('.', {curpos[1], curpos[2], cursor, curpos[4], curpos[5]})
    end

end

function M.increment_visual(addend, override_searchlist, is_additional)
    vim.validate{
        -- 加数。
        addend = {addend, "number"},
        -- 対象とする被加数の種類のリスト (optional)。
        override_searchlist = {override_searchlist, "table", true},
        -- 複数行に渡るインクリメントの場合、加数を
        -- 1行目は1、2行目は2、3行目は3、…と増やしていくかどうか。
        -- default は false。
        additional = {additional, "boolean", true},
    }
    util.validate_list("override searchlist", override_searchlist, "string")

    -- 対象の searchlist 文字列に対応する augends のリストを取得
    if override_searchlist then
        searchlist = override_searchlist
    else
        searchlist = default.searchlist.visual
    end
    local search_augends = assert(util.try_get_keys(augends, searchlist))

    -- VISUAL mode の種類により場合分け
    local mode = vim.fn.visualmode()
    if mode == "v" then
        increment_visual_normal(addend, override_searchlist)
    elseif mode == "V" then
        -- 選択範囲の取得
        local row_s = vim.fn.line("'<")
        local row_e = vim.fn.line("'>")
        M.increment_range(addend, {from = row_s, to = row_e}, override_searchlist, additional)
    elseif mode == "" then
        increment_visual_block(addend, override_searchlist, additional)
    end

end

function M.increment_range(addend, range, override_searchlist, additional)
    -- signature
    vim.validate{
        -- 加数。
        addend = {addend, "number"},
        -- テキストの範囲を表すテーブル。
        -- {from = m, to = n } で "m行目からn行目まで（両端含む）" を表す。
        range = {range, "table"},
        ["range.from"] = {range.from, "number"},
        ["range.to"] = {range.to, "number"},
        -- 対象とする被加数の種類のリスト (optional)。
        override_searchlist = {override_searchlist, "table", true},
    }
    util.validate_list("override searchlist", override_searchlist, "string")

    -- 対象の searchlist 文字列に対応する augends のリストを取得
    if override_searchlist then
        searchlist = override_searchlist
    else
        searchlist = default.searchlist.normal
    end
    local search_augends = assert(util.try_get_keys(augends, searchlist))

    for row=row_s,row_e do
        local f = function()
            -- 対象となる行の内容を取得
            local line = vim.fn.getline(row)
            if line == "" then
                return  -- continue
            end

            -- addend の計算
            if additional then
                actual_addend = addend * (row - row_s + 1)
            else
                actual_addend = addend
            end

            -- 更新後のそれぞれの行内容を取得
            local _, line = get_incremented_text(1, line, actual_addend, search_augends)

            -- 対象行の内容を更新
            if line ~= nil then
                vim.fn.setline(row, line)
            end
        end
        f()
    end

end

-- 完全一致を条件としたインクリメント。
local function get_incremented_text_fullmatch(cursor, text, addend, search_augends)
    -- signature
    vim.validate{
        -- カーソル位置（行頭にある文字が1）。
        cursor = {cursor, "number"},
        -- 行の内容。
        text = {text, "string"},
        -- 加数。
        addend = {addend, "number"},
        -- 対象とする被加数の種類のリスト (optional)。
        search_augends = {search_augends, "table", true},
    }
    util.validate_list("search_augends", search_augends, util.has_augend_field, "is augend")

    local augendlst = util.filter_map(
        function(aug)
            span = aug.find(cursor, text)
            -- 完全一致以外は認めない
            if span == nil or span.from ~= 1 or span.to ~= #text then
                return nil
            end
            return {augend = aug, from = span.from, to = span.to}
        end,
        search_augends
    )

    -- 優先順位が最も高い augend を選択
    local elem = M.pickup_augend(augendlst, cursor)
    if elem == nil then
        return
    end

    -- 加算後のテキストの作成
    local aug = elem.augend
    local s = elem.from
    local e = elem.to
    local rel_cursor = cursor - s + 1
    local subtext = string.sub(text, s, e)
    local rel_cursor, subtext = aug.add(rel_cursor, subtext, addend)
    local text = string.sub(text, 1, s - 1) .. subtext .. string.sub(text, e + 1)
    cursor = rel_cursor + s - 1

    return cursor, text
end

local function get_incremented_text(cursor, text, addend, search_augends)
    -- signature
    vim.validate{
        -- カーソル位置（行頭にある文字が1）。
        cursor = {cursor, "number"},
        -- 行の内容。
        text = {text, "string"},
        -- 加数。
        addend = {addend, "number"},
        -- 対象とする被加数の種類のリスト (optional)。
        search_augends = {search_augends, "table", true},
    }
    util.validate_list("search_augends", search_augends, util.has_augend_field, "is augend")

    local augendlst = util.filter_map(
        function(aug)
            span = aug.find(cursor, text)
            if span == nil then
                return nil
            end
            return {augend = aug, from = span.from, to = span.to}
        end,
        search_augends
    )

    -- 優先順位が最も高い augend を選択
    local elem = M.pickup_augend(augendlst, cursor)
    if elem == nil then
        return
    end

    -- 加算後のテキストの作成
    local aug = elem.augend
    local s = elem.from
    local e = elem.to
    local rel_cursor = cursor - s + 1
    local subtext = string.sub(text, s, e)
    local rel_cursor, subtext = aug.add(rel_cursor, subtext, addend)
    local text = string.sub(text, 1, s - 1) .. subtext .. string.sub(text, e + 1)
    cursor = rel_cursor + s - 1

    return cursor, text
end

-- Increment/Decrement function in visual (not visual-line or visual-block) mode.
-- This edits the current buffer.
local function increment_visual_normal(addend, override_searchlist)
    -- searchlist 取得
    if override_searchlist then
        searchlist = override_searchlist
    else
        searchlist = default.searchlist.visual
    end
    local search_augends = assert(util.try_get_keys(augends, searchlist))

    -- 選択範囲の取得
    local pos_s = vim.fn.getpos("'<")
    local pos_e = vim.fn.getpos("'>")
    if pos_s[2] ~= pos_e[2] then
        -- 行が違う場合はパターンに合致しない
        return
    end
    local line = vim.fn.getline(pos_s[2])
    -- TODO: マルチバイト文字への対応
    local col_s = pos_s[3]
    local col_e = pos_e[3]
    if col_e < col_s then
        col_s, col_e = col_e, col_s
    end
    local text = line:sub(col_s, col_e)

    local _, text = get_incremented_text_fullmatch(1, text, addend, search_augends)

    -- 対象行の内容及びカーソル位置を更新
    if text ~= nil then
        local line = string.sub(line, 1, col_s - 1) .. text .. string.sub(line, col_e + 1)
        vim.fn.setline('.', newline)
        vim.fn.setpos("'<", {pos_s[1], pos_s[2], pos_s[3], pos_s[4]})
        vim.fn.setpos("'>", {pos_s[1], pos_s[2], pos_s[3] + #text - 1, pos_s[4]})
    end
end

local function increment_visual_block(addend, override_searchlist, additional)

    if override_searchlist then
        searchlist = override_searchlist
    else
        searchlist = default.searchlist.visual
    end
    local search_augends = assert(util.try_get_keys(augends, searchlist))

    -- 選択範囲の取得
    local pos_s = vim.fn.getpos("'<")
    local pos_e = vim.fn.getpos("'>")
    local row_s, row_e, col_s, col_e
    if pos_s[2] < pos_e[2] then
        row_s = pos_s[2]
        row_e = pos_e[2]
    else
        row_s = pos_e[2]
        row_e = pos_s[2]
    end
    if pos_s[3] < pos_e[3] then
        col_s = pos_s[3]
        col_e = pos_e[3]
    else
        col_s = pos_e[3]
        col_e = pos_s[3]
    end

    if addend == nil then
        addend = 1
    end

    local cursor = col_s

    for row=row_s,row_e do
        local line = vim.fn.getline(row)
        local text = line:sub(col_s, col_e)

        if additional then
            actual_addend = addend * (row - row_s + 1)
        else
            actual_addend = addend
        end

        local _, text = get_incremented_text(1, text, actual_addend, search_augends)
        local line = string.sub(line, 1, s - 1) .. text .. string.sub(line, e + 1)

        -- 行編集、カーソル位置のアップデート
        vim.fn.setline(row, line)
    end
end


-- cursor 入力が与えられたとき、
-- 自らのスパンが cursor に対してどのような並びになっているか出力する。
-- span が cursor を含んでいるときは0、
-- span が cursor より前方にあるときは 1、
-- span が cursor より後方にあるときは 2 を出力する。
-- この数字は採用する際の優先順位に相当する。
local function status(span, cursor)
    -- type check
    vim.validate{
        span = {span, "table"},
        ["span.from"] = {span.from, "number"},
        ["span.to"] = {span.to, "number"},
        cursor = {cursor, "number"},
    }

    local s, e = span.from, span.to
    if cursor < s then
        return 1
    elseif cursor > e then
        return 2
    else
        return 0
    end
end

-- 現在の cursor 位置をもとに、
-- span: {augend: augend, from: int, to:int} を要素に持つ配列 lst から
-- 適切な augend を一つ取り出す。
function M.pickup_augend(lst, cursor)
    -- type check
    vim.validate{
        lst = {lst, "table"},
        cursor = {cursor, "number"},
    }

    local function comp(span1, span2)
        -- span1 の優先順位が span2 よりも高いかどうか。
        -- まずは status（カーソルとspanの位置関係）に従って優先順位を決定する。
        -- 両者の status が等しいときは、開始位置がより手前にあるものを選択する。
        -- 開始位置も等しいときは、終了位置がより奥にあるものを選択する。
        if status(span1, cursor) ~= status(span2, cursor) then
            return status(span1, cursor) < status(span2, cursor)
        else
            local s1, e1 = span1.from, span1.to
            local s2, e2 = span2.from, span2.to
            if s1 ~= s2 then
                return s1 < s2
            else
                return e1 > e2
            end
        end
    end

    local span = lst[1]
    if span == nil then
        return nil
    end
    vim.validate{
        ["span.from"] = {span.from, "number"},
        ["span.to"] = {span.to, "number"},
    }

    for _, s in ipairs(lst) do
        vim.validate{
            ["s.from"] = {s.from, "number"},
            ["s.to"] = {s.to, "number"},
        }
        if comp(s, span) then
            span = s
        end
    end
    return span
end

-- -- Increment/Decrement function in normal mode. This edits the current buffer.
-- function M.increment(addend, override_searchlist)
--     -- type check
--     vim.validate{
--         addend = {addend, "number"},
--         override_searchlist = {override_searchlist, "table", true}
--     }
-- 
--     if override_searchlist then
--         searchlist = override_searchlist
--     else
--         searchlist = default.searchlist.normal
--     end
--     local search_augends = assert(util.try_get_keys(augends, searchlist))
-- 
--     -- type check
--     util.validate_list("search_augends", search_augends, util.has_augend_field, "is augend")
-- 
--     -- 現在のカーソル位置、カーソルのある行、加数の取得
--     local curpos = vim.call('getcurpos')
--     local cursor = curpos[3]
--     local line = vim.fn.getline('.')
-- 
--     -- 数字の検索
--     local augendlst = util.filter_map(
--         function(aug)
--             span = aug.find(cursor, line)
--             if span == nil then
--                 return nil
--             end
--             return {augend = aug, from = span.from, to = span.to}
--         end,
--         search_augends
--     )
-- 
--     -- 優先順位が最も高い augend を選択
--     local elem = M.pickup_augend(augendlst, cursor)
--     if elem == nil then
--         return
--     end
-- 
--     -- 加算後のテキストの作成
--     local aug = elem.augend
--     local s = elem.from
--     local e = elem.to
--     local rel_cursor = cursor - s + 1
--     local text = string.sub(line, s, e)
--     local newcol, text = aug.add(rel_cursor, text, addend)
--     local newline = string.sub(line, 1, s - 1) .. text .. string.sub(line, e + 1)
--     newcol = newcol + s - 1
-- 
--     -- 行編集、カーソル位置のアップデート
--     vim.fn.setline('.', newline)
--     vim.fn.setpos('.', {curpos[1], curpos[2], newcol, curpos[4], curpos[5]})
-- 
-- end
-- 
-- local function increment_v_block(addend, override_searchlist, additional)
--     -- 選択範囲の取得
--     local pos_s = vim.fn.getpos("'<")
--     local pos_e = vim.fn.getpos("'>")
--     local row_s, row_e, col_s, col_e
--     if pos_s[2] < pos_e[2] then
--         row_s = pos_s[2]
--         row_e = pos_e[2]
--     else
--         row_s = pos_e[2]
--         row_e = pos_s[2]
--     end
--     if pos_s[3] < pos_e[3] then
--         col_s = pos_s[3]
--         col_e = pos_e[3]
--     else
--         col_s = pos_e[3]
--         col_e = pos_s[3]
--     end
-- 
--     if override_searchlist then
--         searchlist = override_searchlist
--     else
--         searchlist = default.searchlist.visual
--     end
--     local search_augends = assert(util.try_get_keys(augends, searchlist))
-- 
--     if addend == nil then
--         addend = 1
--     end
-- 
--     local cursor = col_s
-- 
--     for row=row_s,row_e do
--         local line = vim.fn.getline(row)
--         local text = line:sub(col_s, col_e)
-- 
--         -- 数字の検索
--         local augendlst = util.filter_map(
--             function(aug)
--                 -- 選択範囲に含まれるもののみ検索
--                 span = aug.find(1, text)
--                 if span == nil then
--                     return nil
--                 end
--                 return {augend = aug, from = cursor + span.from - 1, to = cursor + span.to - 1}
--             end,
--             search_augends
--             )
-- 
--         -- 優先順位が最も高い augend を選択
--         local elem = M.pickup_augend(augendlst, cursor)
-- 
--         if elem ~= nil then
-- 
--             -- addend の計算
--             if additional then
--                 actual_addend = addend * (row - row_s + 1)
--             else
--                 actual_addend = addend
--             end
-- 
--             -- 加算後のテキストの作成
--             local aug = elem.augend
--             local s = elem.from
--             local e = elem.to
--             text = line:sub(s, e)
--             local newcol, text = aug.add(nil, text, actual_addend)
--             local newline = string.sub(line, 1, s - 1) .. text .. string.sub(line, e + 1)
--             newcol = newcol + s - 1
-- 
--             -- 行編集、カーソル位置のアップデート
--             vim.fn.setline(row, newline)
--         end
--     end
-- 
-- end
-- 
-- -- Increment/Decrement function for specified line. This edits the current buffer.
-- local function increment_range(addend, override_searchlist, row_s, row_e, additional)
--     vim.validate{
--         addend = {addend, "number"},
--         override_searchlist = {override_searchlist, "table", true},
--         row_s = {row_s, "number"},
--         row_e = {row_e, "number"},
--         additional = {additional, "boolean"}
--     }
-- 
--     if addend == nil then
--         addend = 1
--     end
-- 
--     if override_searchlist then
--         searchlist = override_searchlist
--     else
--         searchlist = default.searchlist.normal
--     end
--     local search_augends = assert(util.try_get_keys(augends, searchlist))
-- 
--     -- type check
--     util.validate_list("search_augends", search_augends, util.has_augend_field, "is augend")
-- 
--     for row=row_s,row_e do
--         local f = function()
--             local line = vim.fn.getline(row)
--             if line == "" then
--                 return
--             end
--             -- 数字の検索
--             local augendlst = util.filter_map(
--                 function(aug)
--                     span = aug.find(1, line)
--                     if span == nil then
--                         return nil
--                     end
--                     return {augend = aug, from = span.from, to = span.to}
--                 end,
--                 search_augends
--                 )
-- 
--             -- 優先順位が最も高い augend を選択
--             local elem = M.pickup_augend(augendlst, 1)
--             if elem == nil then
--                 return
--             end
-- 
--             -- addend の計算
--             if additional then
--                 actual_addend = addend * (row - row_s + 1)
--             else
--                 actual_addend = addend
--             end
-- 
--             -- 加算後のテキストの作成
--             local aug = elem.augend
--             local s = elem.from
--             local e = elem.to
--             local rel_cursor = 2 - s
--             local text = string.sub(line, s, e)
--             local newcol, text = aug.add(rel_cursor, text, actual_addend)
--             local newline = string.sub(line, 1, s - 1) .. text .. string.sub(line, e + 1)
--             newcol = newcol + s - 1
-- 
--             -- 行編集、カーソル位置のアップデート
--             vim.fn.setline(row, newline)
--         end
--         f()
--     end
-- 
-- end
-- 
-- -- tbl = {hoge = {fuga = 1}} のとき get_nested(tbl, "hoge.fuga") == 1 となるようなイメージ
-- local function get_nested(tbl, key)
--     keys = util.split(key, ".")
--     elem = tbl
--     for _, k in ipairs(keys) do
--         elem = elem[k]
--         if elem == nil then
--             return nil
--         end
--     end
--     return elem
-- end
-- 
-- -- Increment/Decrement function with command.
-- function M.increment_command_with_range(addend, searchlist, range, additional)
--     vim.validate{
--         addend = {addend, "number"},
--         searchlist = {searchlist, "table"},
--         range = {range, "table"},
--         additional = {additional, "boolean", true},
--     }
--     util.validate_list("searchlist", searchlist, "string")
--     util.validate_list("range", range, "number")
--     if additional == nil then
--         additional = false
--     end
-- 
--     row_s = range[1]
--     row_e = range[2]
--     increment_range(addend, searchlist, row_s, row_e, additional)
-- end
-- 
-- -- Increment/Decrement function in visual mode.
-- function M.increment_visual(addend, override_searchlist, additional)
--     vim.validate{
--         addend = {addend, "number"},
--         override_searchlist = {override_searchlist, "table", true},
--         additional = {additional, "boolean", true},
--     }
--     if additional == nil then
--         additional = false
--     end
-- 
--     -- 現在のカーソル位置、カーソルのある行、加数の取得
--     local mode = vim.fn.visualmode()
--     if mode == "v" then
--         increment_v(addend, override_searchlist)
--     elseif mode == "V" then
--         -- 選択範囲の取得
--         local row_s = vim.fn.line("'<")
--         local row_e = vim.fn.line("'>")
--         increment_range(addend, override_searchlist, row_s, row_e, additional)
--     elseif mode == "" then
--         increment_v_block(addend, override_searchlist, additional)
--     end
-- end
-- 
-- -- list normal searchlist up
-- function M.print_searchlist()
--     local len_names = vim.tbl_map(
--         function(aug)
--             return vim.fn.strdisplaywidth(aug.name)
--         end,
--         default.searchlist.normal
--         )
--     local max_names = vim.fn.max(len_names)
-- 
--     print("[Normal mode]")
--     for _, aug in ipairs(default.searchlist.normal) do
--         print(("%-" .. max_names .. "s : %s"):format(aug.name, aug.desc))
--     end
--     print("")
-- 
--     local len_names = vim.tbl_map(
--         function(aug)
--             return vim.fn.strdisplaywidth(aug.name)
--         end,
--         default.searchlist.visual
--         )
--     local max_names = vim.fn.max(len_names)
-- 
--     print("[Visual mode]")
--     for _, aug in ipairs(default.searchlist.visual) do
--         print(("%-" .. max_names .. "s : %s"):format(aug.name, aug.desc))
--     end
-- end
-- 
-- return M
