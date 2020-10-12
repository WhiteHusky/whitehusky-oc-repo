local DriveIO = {}
local CachedSector = require('cached-sector')
local event = require('event')
local computer = require('computer')

local NONE = -1
local ERROR = 0
local INFO = 1
local VERBOSE = 2

local LOG_TO_STRING = {
    [ERROR] = "ERROR",
    [INFO] = "INFO",
    [VERBOSE] = "VERBOSE"
}

local lastUptime = computer.uptime()
local function emulatorHangPrevention()
    local thisUptime = computer.uptime()
    if thisUptime > lastUptime + 1 then
        os.sleep(0)
        lastUptime = thisUptime
    end
end

function DriveIO:new(drive)
    -- Check for buggy emulators
    if drive.readSector(2):len() > drive.getSectorSize() then
        error("buggy emulator (sector size mismatch)\ncheck for updates")
    end
    local o = {
        drive=drive,
        seekPos=1,
        capacity=drive.getCapacity(),
        sectorSize=drive.getSectorSize(),
        sectorCache={},
        sectorCacheAccessTime={},
        sectorCacheCount=0,
        cacheLimit=4,
        immediateFlush=false,
        timer=nil,
        flushTime=1,
        debugEnabled=false,
        debugPrint=false,
        debugVerbosity=NONE,
        timedFlush=false
    }
    o.sectors = o.capacity/o.sectorSize
    setmetatable(o, self)
    self.__index = self
    return o
end

function DriveIO:debug(verbosity, message)
    if self.debugEnabled then
        if verbosity <= self.debugVerbosity then
            message = "[" .. LOG_TO_STRING[verbosity] .. "] " .. tostring(message)
            if self.debugPrint then
                print(message)
            end
            computer.pushSignal("debug", "DriveIO", message)
        end
    end
end

function DriveIO:timerCommitCallback()
    self:flush()
    self.timer=nil
end

function DriveIO:commit()
    if self.immediateFlush then
        self:flush()
    else
        if self.timedFlush then
            -- schedule a flush
            if not self.timer then
                self.timer = event.timer(self.flushTime, function() self:timerCommitCallback() end)
            end
        end
    end
end

function DriveIO:discardSectorCache(sector)
    self.sectorCache[sector] = nil
    self.sectorCacheAccessTime[sector] = nil
    self.sectorCacheCount = self.sectorCacheCount - 1
end

function DriveIO:expireSectorCache(sector)
    self:debug(INFO, "expiring sector " .. tostring(sector))
    if not self.sectorCache[sector] then
        error("cache already expired")
    else
        self:flushSector(sector)
        self:discardSectorCache(sector)
    end
end

function DriveIO:cacheSector(sector)
    self:debug(INFO, "caching sector " .. tostring(sector))
    self:freeSectorCache()
    local sectorData = self.drive.readSector(sector)
    self.sectorCache[sector] = CachedSector:new(sectorData)
    self.sectorCacheAccessTime[sector] = computer.uptime()
    self.sectorCacheCount = self.sectorCacheCount + 1
    emulatorHangPrevention()
end

function DriveIO:freeSectorCache()
    while self.sectorCacheCount > math.max(self.cacheLimit - 1, 0) do
        local age = math.huge
        local oldestSector = nil
        for sector, time in pairs(self.sectorCacheAccessTime) do
            if time < age then
                age = time
                oldestSector = sector
            end
        end
        self:expireSectorCache(oldestSector)
    end
end

function DriveIO:flushSectorCache(sector, cache)
    if cache and cache.dirty then
        self:debug(INFO, "flushing dirty sector " .. tostring(sector))
        self.drive.writeSector(sector, cache.sectorData)
        self.sectorCacheAccessTime[sector] = computer.uptime()
        cache.dirty = false
        emulatorHangPrevention()
    end
end

function DriveIO:flushSector(sector)
    local cache = self.sectorCache[sector]
    self:flushSectorCache(sector, cache)
end

function DriveIO:flush()
    self:debug(INFO, "flushing changes")
    for sector, cache in pairs(self.sectorCache) do
        self:flushSectorCache(sector, cache)
    end
end

function DriveIO:getCachedSector(sector)
    if self.sectorCache[sector] then
        self.sectorCacheAccessTime[sector] = computer.uptime()
    else
        self:cacheSector(sector)
    end
    return self.sectorCache[sector]
end

function DriveIO:getCurrentSector()
    return math.floor((self.seekPos - 1) / self.sectorSize) + 1
end

function DriveIO:getCurrentSectorPosition()
    return ((self.seekPos - 1) % self.sectorSize) + 1
end

function DriveIO:sectorToOffset()
    return ((self:getCurrentSectorPosition() - 1) * self.sectorSize) + 1
end

function DriveIO:leftInSector()
    return self.sectorSize - self:getCurrentSectorPosition() + 1
end

-- Interface methods.

function DriveIO:close()
    self:flush()
    return true
end

function DriveIO:write(data)
    local dataLen = data:len()
    -- Same issue with cached sectors. We write including the current seek position.
    if dataLen + self.seekPos - 1 > self.capacity then
        return false, tostring(dataLen + self.seekPos - self.capacity) .. " bytes short on medium, did not write anything"
    end
    while data:len() > 0 do
        -- translate pos to sector
        local sector = self:getCurrentSector()
        -- position in sector
        local sectorPos = self:getCurrentSectorPosition()
        local cachedSector = self:getCachedSector(sector)
        local leftInSector = self:leftInSector()
        -- get actual data we can write
        local dataSubset = data:sub(1,leftInSector)
        -- update data
        data = data:sub(dataSubset:len() + 1, data:len())
        self:debug(VERBOSE, "writing `" .. dataSubset .. "` to sector " .. tostring(sector) .. " at " .. tostring(sectorPos))
        local writeResult, writeError = cachedSector:write(sectorPos, dataSubset)
        -- bubble error
        if not writeResult then
            self:debug(ERROR, writeError)
            return writeResult, writeError
        end
        self.seekPos = self.seekPos + dataSubset:len()
    end
    -- re-clamp seekPos
    self:seek("cur", 0)
    self:commit()
    return true
end

function DriveIO:read(n)
    local data = ""
    local left = n
    while data:len() < n do
        if self.seekPos > self.capacity then
            if data:len() == 0 then
                data = nil
            end
            break
        end
        -- translate pos to sector
        local sector = self:getCurrentSector()
        -- position in sector
        local sectorPos = self:getCurrentSectorPosition()
        local cachedSector = self:getCachedSector(sector)
        local leftInSector = self:leftInSector()
        -- determine if we read the rest of the sector or what's left to obtain
        local reading = math.min(left, leftInSector)
        self:debug(VERBOSE, "reading " .. reading .. " bytes from sector " .. tostring(sector) .. " at " .. tostring(sectorPos))
        data = data .. cachedSector:read(sectorPos, reading)
        -- update left and seekPos
        self.seekPos = self.seekPos + reading
        left = left - reading
    end
    -- re-clamp seekPos
    self:seek("cur", 0)
    return data
end

function DriveIO:seek(whence, offset)
    if not whence then
        return self.seekPos
    end
    local newOffset = 0
    if whence == "cur" then
        newOffset = self.seekPos + offset
    elseif whence == "set" then
        newOffset = offset
    elseif whence == "end" then
        newOffset = self.capacity + offset + 1
    end
    self.seekPos = math.max(1, math.min(newOffset, self.capacity + 1))
    return self.seekPos
end

return DriveIO