local DriveIO = require('drive-io')
local component = require('component')
local term = require('term')
local shell = require('shell')
local computer = require('computer')
local str = tostring
local fmt = string.format

local args, ops = shell.parse(...)

if not ops.drive then
    print("specify a drive with --drive")
    return
end

local driveUUID = component.get(ops.drive)
local drive = component.proxy(driveUUID)

if not drive then
    print("unable to find drive")
    return
end

print("wiping: " .. driveUUID)

local driveIO = DriveIO:new(drive)

driveIO.debugEnabled = true
driveIO.debugPrint = true
driveIO.debugVerbosity = 0

local blankSector = string.rep("\0", driveIO.sectorSize)

driveIO:seek("set", 1)
local sectorsToWipe = math.floor(driveIO.capacity / driveIO.sectorSize)
term.write("Wiping " .. tostring(sectorsToWipe) .. " sectors... ")
local x, _ = term.getCursor()
local thisUptime = computer.uptime()
local lastUptime = thisUptime
for i = 1, sectorsToWipe, 1 do
    local result, err = driveIO:write(blankSector)
    local _, y = term.getCursor()
    term.setCursor(x,y)
    term.write(fmt("%d", math.ceil((i/sectorsToWipe) * 100)) .. "% " .. str(i) .. "/" .. str(sectorsToWipe))
    if not result then
        print("")
        print("Error: " .. err)
        break
    end
    -- for emulators
    thisUptime = computer.uptime()
    if thisUptime > lastUptime + 1 then
        os.sleep(0)
        lastUptime = thisUptime
    end
end
print("")
term.write("Writing changes to disk...")
driveIO:flush()
term.write("Done!")