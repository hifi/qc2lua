package.path = package.path .. ';./id1/?.lua'

require "defs"
require "subs"
require "combat"
require "items"
require "weapons"
require "world"
require "client"
require "spectate"
require "player"
require "doors"
require "buttons"
require "triggers"
require "plats"
require "misc"
require "server"

function qtrue(x)
    if type(x) == 'userdata' then
        return x.classname ~= 'worldspawn'
    end

    return not (x == 0 or x == false or x == '' or x == nil)
end

function stof(s)
    return tonumber(s) or 0
end

function aim(e, speed)
    return (makevectors(self.v_angle))
end

function find(start, field, value)
    local found_start = false

    if type(field) ~= 'string' then
        error('find field needs to be a string')
    end

    local e = entities(function(e)
        if not found_start then
            if e == start then
                found_start = true
            end
            return false
        end

        if e[field] and e[field] == value then
            return true
        end

        return false
    end)()

    return e or world
end

function rint(num)
    if num > 0 then
        return math.floor(num + 0.5)
    else
        return math.ceil(num - 0.5)
    end
end
