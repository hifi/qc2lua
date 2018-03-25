local frames = {}
local nframes = 0
local level = 1
local out = {
    '-- qc2lua'
}

local var = function(v)
    if v == 'end' then
        return '_end'
    elseif v == 'or' then
        return '_or'
    elseif v == 'TRUE' then
        return '1 --[[ TRUE ]]'
    elseif v == 'FALSE' then
        return '0 --[[ FALSE ]]'
    end

    -- trace variables
    if v:match('^trace_') ~= nil then
        v = v:gsub('_', '.')
    end

    -- vectors are tables in lua
    v = v:gsub('_([xyz])$', '.%1')

    return v
end

local function emit(...)
    local args = {}
    for n=1, select('#', ...) do
        args[#args + 1] = select(n, ...)
    end

    local indent = {}
    for i=2,level do
        indent[#indent + 1] = '    '
    end

    out[#out + 1] = table.concat(indent, '') .. table.concat(args, ' ')
end

local function EmitFunction(root)
    local t = {}
    for i,v in ipairs(root.ctype.value) do
        if #v.value == 2 then
            t[#t + 1] = v.value[2].value
        end
    end

    emit('function', root.name, '(' .. table.concat(t, ', ') .. ')')
    handleAll(root)
    emit('end')
    emit()
end

local BarfExprComponent

local function EmitFrameFunction(root)
    emit('function', root.name, '()')

    level = level + 1
    emit('self.frame', '=', BarfExprComponent(root.value[1].value[1]))
    emit('self.nextthink', '=', 'time + 0.1')
    emit('self.think', '=', root.value[2].value[1].value)
    emit()
    level = level - 1

    handleAll(root)
    emit('end')
    emit()
end

local BarfExpr

BarfExprComponent = function(t)
    if t.type == 'expr' then
        return '(' .. BarfExpr(t) .. ')'
    elseif t.type == 'string' then
        return '"' .. t.value .. '"'
    elseif t.type == 'number' then
        return t.value
    elseif t.type == 'vector' then
        local p = {}
        for v in string.gmatch(t.value, '[^%s]+') do
            p[#p+1] = v
        end
        return 'vec3(' .. table.concat(p, ',') .. ')'
    elseif t.type == 'name' then
        return var(t.value)
    elseif t.type == 'call' then
        local p = {}
        local n = t.name

        for i,v in ipairs(t.value) do
            p[i] = BarfExpr(v)
        end

        -- some simple equivalents
        if n == 'fabs' then
            n = 'math.abs'
        elseif n == 'floor' then
            n = 'math.floor'
        elseif n == 'ceil' then
            n = 'math.ceil'
        elseif n == 'ftos' then
            n = 'tostring'
        elseif n == 'makevectors' then
            -- not local because qw source expects these to be globally set at some points
            n = 'v_forward, v_right, v_up = makevectors'
        elseif n == 'traceline' then
            -- not local because qw source expects these to be globally set at some points
            n = 'trace = traceline'
        elseif n == 'vlen' then
            if #t.value[1].value > 1 then
                return '#(' .. p[1] .. ')'
            else
                return '#' .. p[1]
            end
        elseif n == 'find' then
            p[2] = '"' .. p[2] .. '"'
        end

        return n .. '(' .. table.concat(p, ', ') .. ')'
    elseif t.type == 'not' then
        return 'not'
    elseif t.value == '!=' then
        return '~='
    elseif t.value == '&&' then
        return 'and'
    elseif t.value == '||' then
        return 'or'
    elseif t.value == '+'
            or t.value == '-'
            or t.value == '*'
            or t.value == '/'
            or t.value == '=='
            or t.value == '>'
            or t.value == '<'
            or t.value == '<='
            or t.value == '>='
            or t.value == '|'
            or t.value == '&'
            then
        return t.value
    elseif t.type == 'pragma' then
        return frames[t.value] .. ' --[[' .. t.value .. ']]'
    else
        dump(t)
        error ('Unknown expr component: ' .. t.type)
    end
end

BarfExpr = function(e, boolean)
    local t = {}
    local parts = {}

    if boolean == true then
        -- group until boolean operator
        local expr = {}
        local skip = false
        for i,v in ipairs(e.value) do
            if skip then
                skip = false
                parts[#parts + 1] = v
            elseif v.type == 'not' then
                parts[#parts + 1] = v
            elseif v.type == 'eq'
                    or v.type == 'ne'
                    or v.type == 'gt'
                    or v.type == 'lt'
                    or v.type == 'ge'
                    or v.type == 'le'
                    or v.type == 'sym'
                    then
                skip = true
                for j,p in ipairs(expr) do
                    parts[#parts + 1] = p
                end
                parts[#parts + 1] = v
                expr = {}
            elseif v.type == 'or' or v.type == 'and' or i == #e.value then
                if i == #e.value then
                    expr[#expr + 1] = v
                end
                if #expr > 0 then
                    parts[#parts + 1] = {
                        type = 'call',
                        name = 'qtrue',
                        value = {
                            {
                                type = 'expr',
                                value = expr
                            }
                        }
                    }
                end

                expr = {}

                if i ~= #e.value then
                    parts[#parts + 1] = v
                end
            else
                expr[#expr+1] = v
            end
        end
    else
        parts = e.value
    end

    for i,v in ipairs(parts) do
        t[#t+1] = BarfExprComponent(v)
    end

    return table.concat(t, ' ')
end

local function EmitAssign(root)
    local stack = root.value

    emit(var(root.name), '=', BarfExpr(table.remove(stack)))

    for i,v in ipairs(stack) do
        if i == 1 then
            emit(var(v.value[1].value), '=', var(root.name))
        else
            emit(var(v.value[1].value), '=', var(stack[i - 1].value[1].value))
        end
    end
end

local function EmitIf(root, previous, next)

    if previous ~= nil then
        emit()
    end

    emit('if', BarfExpr(root.value, true), 'then')

    handleAll(root)
    if next == nil or next.type ~= 'else' then
        emit('end')
    end
end

local function EmitElse(root, previous, next)
    if #root.body == 1 and root.body[1].type == 'if' then
        emit('elseif', BarfExpr(root.body[1].value, true), 'then')
        handleAll(root.body[1])
    else
        emit('else')
        handleAll(root)
    end
    if next == nil or next.type ~= 'else' then
        emit('end')
    end
end

local function EmitReturn(root)
    if root.value ~= nil then
        emit('return', BarfExpr(root.value))
    else
        emit('return')
    end
end

local function EmitLocal(root)
    if root.ctype.name == 'vector' then
        for i,v in ipairs(root.value) do
            emit('local', var(v), '=',  'vec3(0,0,0)')
        end
    elseif root.ctype.name == 'float' then
        for i,v in ipairs(root.value) do
            emit('local', var(v), '=',  '0')
        end
    elseif root.ctype.name == 'string' then
        for i,v in ipairs(root.value) do
            emit('local', var(v), '=',  '""')
        end
    else
        local t = {}
        for i,v in ipairs(root.value) do
            t[i] = var(v)
        end
        emit('local', table.concat(t, ', '))
    end
end

local function EmitConst(root)
    -- field constants and empty definitions can be ignored
    if root.ctype.name:sub(1, 1) == '.' then
        emit('field("' .. root.name .. '", "' .. root.ctype.name:sub(2) ..'")')
        return
    end
    -- these are dangerous to exist
    if root.name == 'TRUE' or root.name == 'FALSE' then
        return
    end
    if root.value ~= nil then
        emit(root.name, '=', BarfExpr(root.value))
    elseif root.ctype.name == 'float' then
        emit(root.name, '=', 0)
    elseif root.ctype.name == 'string' then
        emit(root.name, '=', '""')
    elseif root.ctype.name == 'entity' then
        emit(root.name, '=', 'world')
    elseif root.ctype.name == 'vector' then
        emit(root.name, '=', 'vec3(0,0,0)')
    end
end

local function EmitFunctionDef(root)
    if root.ctype.name:sub(1, 1) ~= '.' then
        return
    end
    emit('field("' .. root.name .. '", "function")')
end

local function EmitWhile(root)
    emit('while', BarfExpr(root.value, true), 'do')
    handleAll(root)
    emit('end')
end

local function EmitDo(root)
    emit('repeat')
    handleAll(root)
    emit('until', 'not (' .. BarfExpr(root.value, true) .. ')')
end

local function HandlePragma(root)
    if root.value ~= '$frame' then
        return
    end

    for v in string.gmatch(root.body, '[^%s]+') do
        frames['$' .. v] = nframes
        nframes = nframes + 1
    end
end

handleAll = function(root)
    level = level + 1
    for i,v in ipairs(root.body) do
        handle(v, root.body[i - 1], root.body[i + 1])

        -- quakec allows code after return, lua doesn't
        if v.type == 'return' then
            break
        end
    end
    level = level - 1
end

handle = function(root, previous, next)
    if root.type == 'func' then
        EmitFunction(root)
    elseif root.type == 'ffunc' then
        EmitFrameFunction(root)
    elseif root.type == 'assign' then
        EmitAssign(root)
    elseif root.type == 'if' then
        EmitIf(root, previous, next)
    elseif root.type == 'else' then
        EmitElse(root, previous, next)
    elseif root.type == 'call' then
        emit(BarfExprComponent(root))
    elseif root.type == 'return' then
        EmitReturn(root)
    elseif root.type == 'local' then
        EmitLocal(root)
    elseif root.type == 'const' then
        EmitConst(root)
    elseif root.type == 'while' then
        EmitWhile(root)
    elseif root.type == 'do-while' then
        EmitDo(root)
    elseif root.type == 'fdef' then
        EmitFunctionDef(root)
    elseif root.type == 'builtin' then
        -- ignore
    elseif root.type == 'pragma' then
        HandlePragma(root)
    else
        error("Unhandled type: " .. root.type)
    end
end

return function(ast)
    for i,v in ipairs(ast.body) do
        handle(v)
    end

    return table.concat(out, '\n')
end
