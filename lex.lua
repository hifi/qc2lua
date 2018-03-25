local lex = {}

local function preprocess(s)
    return s
end

function lex:new(s)
    o = {
        data      = preprocess(s),
        position  = 1,
        line      = 1,
        character = 1,
        buf       = '',
    }

    setmetatable(o, self)
    self.__index = self
    return o
end

function lex:eof()
    return self.position >= self.data:len()
end

function lex:getc(pattern)
    local c = self.data:sub(self.position, self.position)

    if pattern ~= nil and not c:match(pattern) then
        return false
    end

    if c == '\n' then
        self.line = self.line + 1
        self.character = 1
    else
        self.character = self.character + 1
    end

    self.position = self.position + 1
    self.buf = self.buf .. c

    if pattern ~= nil then
        return true
    end

    return c
end

function lex:getall(pattern)
    local got = false

    while self:getc(pattern) do
        got = true
    end

    return got
end

function lex:getbuf()
    local buf = self.buf
    self.buf = ''
    return buf
end

function lex:skip(pattern)
    local skipped = false
    repeat
        local c = self.data:sub(self.position, self.position)
        if not c:match(pattern) then
            return skipped
        end

        if c == '\n' then
            self.line = self.line + 1
            self.character = 1
        else
            self.character = self.character + 1
        end

        self.position = self.position + 1
        skipped = true
    until false
end

function lex:skipWhitespace()
    return self:skip('[%s]')
end

function lex:skipComment()
    if not self:getc('/') then
        return false
    end

    if self:getc('/') then
        -- single line comment
        self:skip('[^\n]')
        self:getc()
    elseif self:getc('%*') then
        -- multi line comment
        local c
        repeat
            self:skip('[^%*]')
            self:getc()
            c = self:getc()
        until c == nil or c == '/'
    else
        -- not a comment, abort
        self.position = self.position - 1
        self.character = self.character - 1
        return false
    end

    return true
end

-- this is (still) completely fucked up but works
function lex:readPragma()
    local args = {}

    repeat
        local c = self:getc()
        if c == '/' then
            self.position = self.position - 1
            self.character = self.character - 1
            if not self:skipComment() then
                c = self:getc()
            end
        end
        if c == '\n' or c == ',' or c == ';' then
            self.position = self.position - 1
            self.character = self.character - 1
            break
        end
        if c ~= ' ' or #args > 0 then
            args[#args + 1] = c
        end
    until false

    return table.concat(args, '')
end

function lex:next()
    local skipped
    repeat
        skipped = false
        if self:skipWhitespace() then
            skipped = true
        end
        if self:skipComment() then
            skipped = true
        end
    until skipped == false

    local token = {
        type        = nil,
        value       = nil,
        line        = self.line,
        character   = self.character
    }

    self:getbuf() -- discard buffer
    local c = self:getc()

    if c == '-' and self:getall('[0-9%.]') then
        token.type = 'number'
    elseif c:match('[0-9]') then
        token.type = 'number'
        self:getall('[0-9%.]')
    elseif c:match('[A-Za-z]') then
        token.type = 'name'
        self:getall('[A-Za-z0-9_%.]')
        -- hack to support 'foo. bar'
        if self.buf:sub(-1) == '.' and self:getc(' ') then
            self:getall('[A-Za-z0-9_%.]')
        end
    elseif c:match('%.') then
        token.type = 'field'
        self:getall('[A-Za-z0-9_%.]')
    elseif c == '$' then
        token.type = 'pragma'
        self:getall('[A-Za-z0-9_]')
        token.value = self:getbuf()
        token.body = self:readPragma()
        return token
        -- return self:next() -- skip pragmas for now
    elseif c == '|' then
        if self:getc('|') then
            token.type = 'or'
        else
            token.type = 'bor'
        end
    elseif c == '&' then
        if self:getc('&') then
            token.type = 'and'
        else
            token.type = 'band'
        end
    elseif c == '=' then
        if self:getc('=') then
            token.type = 'eq'
        else
            token.type = 'assign'
        end
    elseif c == '!' then
        if self:getc('=') then
            token.type = 'ne'
        else
            token.type = 'not'
        end
    elseif c == '<' then
        if self:getc('=') then
            token.type = 'le'
        else
            token.type = 'lt'
        end
    elseif c == '>' then
        if self:getc('=') then
            token.type = 'ge'
        else
            token.type = 'gt'
        end
    elseif c == '#' then
        token.type = 'builtin'
        self:getall('[0-9]')
    elseif c == '"' then
        token.type = 'string'
        repeat
            local c = self:getc()
            if c == '\\' then
                self:getc()
            end
        until c == '"'
        token.value = self:getbuf():sub(1, -2):sub(2)
        return token
    elseif c == "'" then
        token.type = 'vector'
        self:getbuf() -- discard '
        self:getall("[^']")
        token.value = self:getbuf()
        self:getc() -- discard '
        return token
    elseif c:match('[%[%]%(%){};,%+%-%*%$/%?:]') then -- a symbol
        token.type = 'sym'
    elseif c == '' then
        token.type = 'eof'
    else
        error(string.format("Syntax error on line %d character %d, unexpected '%s'", self.line, self.character, self:getbuf()))
    end

    token.value = self:getbuf()

    return token
end

return lex
