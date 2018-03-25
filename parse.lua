#!/usr/bin/lua5.3

local lex = require 'lex'
local l
local current

local function get(type)
    local token = current or l:next()

    if type ~= nil and token.type ~= type then
        error(string.format("Expected type '%s' on %d:%d but got '%s' (%s)", type, current.line, current.character, current.type, current.value))
    end

    current = nil
    return token
end

local function check(value, peek)
    current = current or l:next()

    if current.value == value then
        if peek ~= true then
            current = nil
        end
        return true
    end

    return false
end

local function checkt(type, peek)
    current = current or l:next()

    if current.type == type then
        if peek ~= true then
            current = nil
        end
        return true
    end

    return false
end

local function expect(value)
    current = current or l:next()

    if current.value ~= value then
        error(string.format("Expected '%s' on %d:%d but got '%s'", value, current.line, current.character, current.value))
    end

    current = nil
end

local ParseExpr
local function ParseParms()
    local t = {}

    repeat
        t[#t + 1] = ParseExpr()
    until not check(',')

    return t
end

local function ParseType()
    local type

    -- special case for field types
    if checkt('field', true) then
        type = get()
    elseif checkt('eof', true) then
        return nil
    else
        type = get('name')
    end

    local t = {
        type = 'type',
        name = type.value
    }

    if check('(') then
        t.value = ParseParms()
        expect(')')
    end

    return t
end

local function ParseExprComponent()
    if checkt('name', true) then
        local t = get()
        if check('(') then -- a function call
            t.type = 'call'
            t.name = t.value
            t.value = ParseParms()
            expect(')')
        end
        return t
    elseif checkt('number', true) then
        return get()
    elseif checkt('string', true) then
        return get()
    elseif checkt('vector', true) then
        return get()
    elseif checkt('field', true) then
        return get()
    elseif checkt('not', true) then
        return get()
    elseif checkt('and', true) then
        return get()
    elseif checkt('or', true) then
        return get()
    elseif checkt('band', true) then
        return get()
    elseif checkt('bor', true) then
        return get()
    elseif checkt('eq', true) then
        return get()
    elseif checkt('ne', true) then
        return get()
    elseif checkt('gt', true) then
        return get()
    elseif checkt('lt', true) then
        return get()
    elseif checkt('ge', true) then
        return get()
    elseif checkt('le', true) then
        return get()
    elseif check('+', true) then
        return get()
    elseif check('-', true) then
        return get()
    elseif check('*', true) then
        return get()
    elseif check('/', true) then
        return get()
    elseif checkt('pragma', true) then
        return get()
    elseif check('(') then
        local e = ParseExpr()
        expect(')')
        return e
    end
end

ParseExpr = function()
    local e = {
        type = 'expr',
        value = {}
    }

    local c
    repeat
        c = ParseExprComponent()
        e.value[#e.value + 1] = c
    until c == nil

    return e
end

local function ParseStatement()
    -- if statement
    if check('if') then
        local t = {
            type = 'if',
            value = nil,
            body = {}
        }

        expect('(')
        t.value = ParseExpr()
        expect(')')

        if check('{') then
            while not check('}') do
                t.body[#t.body + 1] = ParseStatement()
            end
        else
            t.body[#t.body + 1] = ParseStatement()
        end

        return t
    end

    -- else statement
    if check('else') then
        local t = {
            type = 'else',
            body = {}
        }

        if check('{') then
            while not check('}') do
                t.body[#t.body + 1] = ParseStatement()
            end
        else
            t.body[#t.body + 1] = ParseStatement()
        end

        return t
    end

    -- local var def
    if check('local') then
        local t = {
            type = 'local',
            ctype = ParseType(),
            value = {}
        }

        repeat
            t.value[#t.value + 1] = get('name').value
        until not check(',')

        expect(';')
        return t
    end

    -- do..while
    if check('do') then
        local t = {
            type = 'do-while',
            value = nil,
            body = {}
        }

        expect('{')
        while not check('}') do
            t.body[#t.body + 1] = ParseStatement()
        end

        expect('while')
        expect('(')
        t.value = ParseExpr()
        expect(')')

        return t
    end

    -- while
    if check('while') then
        expect('(')

        local t = {
            type = 'while',
            value = ParseExpr(),
            body = {}
        }

        expect(')')

        if check('{') then
            while not check('}') do
                t.body[#t.body + 1] = ParseStatement()
            end
        else
            t.body[#t.body + 1] = ParseStatement()
        end

        return t
    end

    -- return
    if check('return') then
        local t = {
            type = 'return',
            value = ParseExpr()
        }
        expect(';')
        return t
    end

    -- eat nops
    if check(';') then
        io.stderr:write('Warning: eating no-op and returning nil\n')
        return nil
    end

    -- function call or assignment
    local name = get('name')

    -- function call
    if check('(') then
        local t = {
            type = 'call',
            name = name.value,
            value = ParseParms()
        }
        expect(')')
        expect(';')
        return t
    end

    local t = {
        type = 'assign',
        name = name.value,
        value = {}
    }

    -- assignment
    repeat
        if check('==') then
            -- this is a no-op and we should emit a warning
            io.stderr:write('Warning: assignment looks like an expression\n')
            t.value[#t.value + 1] = ParseExpr()
        else
            expect('=')
            t.value[#t.value + 1] = ParseExpr()
        end
    until check(';')

    return t
end

function ParseBlock(p)
    local t = {}
    expect('{')

    while not check('}') do
        t[#t + 1] = ParseStatement()
    end

    return t
end

local function ParseDefs(p)

    while checkt('pragma', true) do
        p.body[#p.body + 1] = get()
    end

    local type = ParseType()

    if type == nil then
        return
    end

    repeat
        local t = {
            type = 'const',
            ctype = type,
            name = get('name').value,
            value = nil,
            body = {}
        }

        if type.value ~= nil then
            t.type = 'fdef'
        end

        if check('=') then
            if check('{', true) then
                t.type = 'func'
                t.body = ParseBlock()
            elseif check('[') then
                t.type = 'ffunc'
                t.value = ParseParms(),
                expect(']')
                t.body = ParseBlock()
            elseif checkt('builtin') then
                -- skipped builtin
                t.type = 'builtin'
            else
                -- constant assignment
                t.value = ParseExpr()
            end
        end

        p.body[#p.body + 1] = t
    until not check(',')

    check(';')
end

return function(lexer)
    l = lexer

    local ast = {
        type = 'root',
        body = {}
    }

    while not checkt('eof') do
        ParseDefs(ast)
    end

    return ast
end
