local DriveIO = require('drive-io')
local component = require('component')
local term = require('term')
local shell = require('shell')

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
for i = 1, sectorsToWipe, 1 do
    local result, err = driveIO:write(blankSector)
    local _, y = term.getCursor()
    term.setCursor(x,y)
    term.write(string.format("%d", math.ceil((i/sectorsToWipe) * 100)) .. "%")
    if not result then
        print("")
        print("Error: " .. err)
        break
    end
    -- for emulators
    if i % 128 == 0 then
        os.sleep(0)
    end
end
print("")
term.write("Writing changes to disk...")
driveIO:flush()
term.write("Done!")