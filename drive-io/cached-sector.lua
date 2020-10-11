local CachedSector = {}

function CachedSector:new(sectorData)
    local o = {
        dirty=false,
        sectorData=sectorData,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function CachedSector:read(index, count)
    return self.sectorData:sub(index, index+count-1)
end

function CachedSector:write(index, data)
    local dataLen = data:len()
    local sectorDataLen = self.sectorData:len()
    -- This needs to subtracted 1 since we're writing to the index's position
    -- The woes of "start at 1"
    if index + dataLen - 1 > self.sectorData:len() then
        return false, tostring(dataLen + index - sectorDataLen) .. " bytes short on " .. sectorDataLen .. " byte sector, did not write anything"
    end
    self.dirty = true
    self.sectorData = self.sectorData:sub(1, index-1) .. data .. self.sectorData:sub(index+dataLen)
    return true
end

return CachedSector