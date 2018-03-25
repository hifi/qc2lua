local lexer = require 'lex'
local parser = require 'parse'
local luafy = require 'luafy'

local s = io.open(arg[1]):read('a')
local l = lexer:new(s)
local ast = parser(l)

local output = luafy(ast)
print(output)
