--[[
    Exposes the GERTi client as a modem device as a compatibility layer for
    programs written for a traditional modem.
]]

local GERTi = require("GERTiClient")
local buffer = require("buffer")
local event = require("event")
local streamingTable = require("streaming-tables")
local component = require("component")
local thread = require("thread")
local servicePort = 5050
local openConnections = {}
local vbuf = 512
GERTi_MODEM = GERTi_MODEM or nil

local fauxStream = {}

function fauxStream:new()
    local o = {
        internalString = ""
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function fauxStream:close()
    self = nil
    return nil
end

function fauxStream:write(str)
    self.internalString = self.internalString .. str
    return true
end

function fauxStream:read(n)
    local chunk = self.internalString:sub(1,n)
    self.internalString = self.internalString:sub(n+1)
    return chunk
end

function fauxStream:seek()
    return nil, "not supported"
end

local GERTiStream = {}

function GERTiStream:new(socket)
    local o = {
        socket = socket,
        internalString = ""
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function GERTiStream:close()
    return self.socket:close()
end

function GERTiStream:write(str)
    print(str)
    return self.socket:write(str)
end

function GERTiStream:read(n)
    local chunk = ""
    print("WANT", n)
    print("HAVE", self.internalString:len())
    if self.internalString:len() < n then
        print("NEED DATA")
        local chunks = self.socket:read()
        local processed = 0
        for _, value in pairs(chunks) do
            print("CHUNK READ")
            self.internalString = self.internalString .. value
            processed = processed + 1
        end
        print("CHUNKS", processed)
    end
    chunk = self.internalString:sub(1,n)
    self.internalString = self.internalString:sub(n+1)
    os.sleep(1)
    if chunk:len() > 0 then
        print(chunk)
    end
    return chunk
end

function GERTiStream:seek()
    return nil, "not supported"
end

local GERTiModem = {}
local ports = {}
local events = {}

function GERTiModem.isWireless()
    return true
end

function GERTiModem.maxPacketSize()
    return math.huge
end

function GERTiModem.isOpen(port)
    checkArg(1, port, "number")
    return ports[port]
end

function GERTiModem.open(port)
    checkArg(1, port, "number")
    assert(port > 0, "port out of range")
    ports[port] = true
    return true
end

function GERTiModem.close(port)
    checkArg(1, port, "number", "nil")
    if port then
        assert(port > 0, "port out of range")
        ports[port] = nil
    else
        ports={}
    end
    return true
end

function GERTiModem.send(...)
    thread.create(function(addr, port, ...)
        print(addr, port, ...)
        openConnections[addr] = true
        local socket = GERTi.openSocket(addr, servicePort)
        local buf = buffer.new("rw", GERTiStream:new(socket))
        buf:setvbuf("full", vbuf)
        print("Waiting for acknowledgement...")
        event.pull("GERTData", addr)
        local response = streamingTable.unpack(buf)
        if response.connection then
            print("Sending connection request...")
            streamingTable.pack(buf, {port=port})
            buf:flush()
            print("Waiting for response...")
            response = streamingTable.unpack(buf)
            local success = false
            if response.accept then
                print("Request accepted, sending data...")
                streamingTable.pack(buf, {...})
                print("Sent.")
            else
                print("Request declined.")
            end
        end
        openConnections[addr] = nil
        buf:close()
    end, ...)
    return true
end

function GERTiModem.broadcast(port, ...)
    for id, _ in pairs(GERTi.getNeighbors()) do
        GERTiModem.send(id, port, ...)
    end
    return true
end

function GERTiModem.getStrength()
    return 255
end

function GERTiModem.setStrength()
    return 255
end

function GERTiModem.getWakeMessage()
    return ""
end

function GERTiModem.setWakeMessage()
    return ""
end

function GERTiModem.__destroy()
    for k, eventId in pairs(events) do
        event.cancel(eventId)
        events[k] = nil
    end
    return
end

local function handleGERTiConnection(...)
    thread.create(function(eventName, originAddress, connectionID)
        if originAddress ~= GERTi.getAddress() and not openConnections[originAddress] and connectionID == servicePort then
            print("Request incoming...")
            local socket = GERTi.openSocket(originAddress, connectionID)
            local buf = buffer.new("rw", GERTiStream:new(socket))
            buf:setvbuf("full", vbuf)
            print("Socket open, sending acknowledgement...")
            streamingTable.pack(buf, {connection=true})
            buf:flush()
            print("Waiting for response...")
            local request = streamingTable.unpack(buf)
            print("Unpacked...")
            if ports[request.port] then
                print("Port accepted, sending clearance...")
                streamingTable.pack(buf, {accept=true})
                buf:flush()
                print("Receiving payload...")
                local payload = streamingTable.unpack(buf)
                event.push("modem_message", GERTi.getAddress(), originAddress, request.port, table.unpack(payload))
            else
                print("Request declined")
                streamingTable.pack(buf, {accept=false})
            end
            buf:close()
        end
    end, ...)
end

if GERTi_MODEM then
    if component.softwareComponents.removeComponent(GERTi_MODEM) then
        print("Old Component Removed")
    end
end

GERTi_MODEM=component.softwareComponents.addComponent("modem", GERTiModem)

events.GERTiConnection = event.listen("GERTConnectionID", handleGERTiConnection)
events.GERTiData = event.listen("GERTData", print)
events.modem_message = event.listen("modem_message", print)
events.GERTiConnection_Debug = event.listen("GERTConnectionID", print)