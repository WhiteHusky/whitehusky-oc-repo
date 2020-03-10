--[[
        Given a table and a stream to write to, a table is converted to binary
    data that can be reversed to recreate the table.

        Use case is where the goal is to transmit a table but low memory
    systems make it impossible to seralize the response through typical
    libaries. Or limits of the means to transmit cannot allow transmission of
    a serialized table as a whole.

    x0000000 = end table
    x0000001 = boolean
    x0000010 = float
    x0000011 = integer
    x0000100 = string
    x0000101 = table

    booleans use the 8th bit to determine if it is true or false.
    numbers are followed by a eight bytes containing the number in binary lua
        number format
    strings are followed by a four byte unsigned integer describing the length
        of the string followed by those characters
    tables simply starts the same function on the nested table.
]]--

local allowedTableKeys = {
    boolean=true,
    number=true,
    string=true
}

local allowedTableValues = {
    boolean=true,
    number=true,
    string=true,
    table=true
}

local streamingSerialization = {}

local function thingToBinary(strm, thing)
    local thingType = type(thing)
    if thingType == "boolean" then
        local d = 1
        if thing then
            d = 128 | d
        end
        strm:write(string.pack("B", d))
    elseif thingType == "number" then
        if math.type(thing) == "float" then
            strm:write(string.pack("B", 2))
            strm:write(string.pack("<n", thing))
        else
            strm:write(string.pack("B", 3))
            strm:write(string.pack("<j", thing))
        end
    elseif thingType == "string" then
        strm:write(string.pack("B", 4))
        strm:write(string.pack("<I4", thing:len()))
        strm:write(thing)
    end
end

function streamingSerialization.pack(strm, t)
    for key, value in pairs(t) do
        local keyType = type(key)
        local valueType = type(value)
        if allowedTableKeys[keyType] and allowedTableValues[valueType] then
            thingToBinary(strm, key)
            if valueType == "table" then
                strm:write(string.pack("B", 5))
                streamingSerialization.pack(strm, value)
            else
                thingToBinary(strm, value)
            end
        end
    end
    strm:write("\0")
end

local function binaryToThing(strm)
    local raw = string.unpack("B", strm:read(1))
    local rawType = raw & 7
    local thing = nil
    if rawType == 1 then -- boolean
        thing = false
        if (raw & 128) > 0 then
            thing = true
        end
    elseif rawType == 2 then -- float
        thing = string.unpack("<n", strm:read(8))
    elseif rawType == 3 then -- integer
        thing = string.unpack("<j", strm:read(8))
    elseif rawType == 4 then -- string
        local length = string.unpack("<I4", strm:read(4))
        thing = strm:read(length)
    elseif rawType == 5 then -- table
        thing = streamingSerialization.unpack(strm)
    end
    return thing
end

function streamingSerialization.unpack(strm)
    local t = {}
    local key = binaryToThing(strm)
    while key do
        t[key] = binaryToThing(strm)
        key = binaryToThing(strm)
    end
    return t
end

return streamingSerialization
