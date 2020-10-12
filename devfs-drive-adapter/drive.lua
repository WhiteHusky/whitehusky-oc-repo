local DriveIO = require("drive-io")

local IO = {}

function IO:new(drive, mode)
    if mode:match("[a]") then
        return nil, "appending to a disk does not make sense"
    end
    local o = {
        drive=drive,
        readable=mode:match("[r]"),
        writable=mode:match("[w]"),
        seekable=mode:match("[rw]")
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function IO:close(...)
    return self.drive:close(...)
end

function IO:seek(...)
    if not self.seekable then
        return false, "incorrect mode for seek"
    end
    return self.drive:seek(...)
end

function IO:read(...)
    if not self.readable then
        return false, "incorrect mode for read"
    end
    return self.drive:read(...)
end

function IO:write(...)
    if not self.writable then
        return false, "incorrect mode for write"
    end
    return self.drive:write(...)
end

local function driveOpen(drive, mode)
    checkArg(2, mode, "string", "nil")
  
    mode = mode or "r"
  
    if not mode:match("[rwa]") then
      return nil, "invalid mode"
    end

    return IO:new(drive, mode)
end

return function(proxy)
    return
    {
        capacity = {proxy.getCapacity()},
        sectorSize = {proxy.getSectorSize()},
        sectors = {proxy.getCapacity()/proxy.getSectorSize()},
        raw = {open = function(mode)
            local drive = DriveIO:new(proxy)
            drive.debugEnabled = true
            drive.debugVerbosity = 0
            return driveOpen(drive, mode)
        end, size = proxy.getCapacity},
    }
end