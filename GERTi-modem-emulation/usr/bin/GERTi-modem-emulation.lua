--[[
    Exposes the GERTi client as a modem device as a compatibility layer for
    programs written for a traditional modem.
]]

local GERTi = require("GERTiClient")
local event = require("event")
local buffer = require("buffer")
local streamingTable = require("streaming-tables")
local component = require("component")
local thread = require("thread")
local serialization = require("serialization")
local servicePort = 5050
local openConnections = {}
local vbuf = 512
GERTi_MODEM = GERTi_MODEM or nil

local fauxStream = {}

local function debug_print(...)
    event.push("debug", "GERTiModem", ...)
end

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

function GERTiStream:new(socket, address)
    local o = {
        socket = socket,
        internalString = "",
        writeBuf = nil,
        address = address
    }
    setmetatable(o, self)
    self.__index = self
    o.writeBuf = buffer.new("w", socket)
    o.writeBuf:setvbuf("full", vbuf)
    return o
end

function GERTiStream:close()
    return self.socket:close()
end

function GERTiStream:write(str)
    return self.writeBuf:write(str)
end

function GERTiStream:flush()
    return self.writeBuf:flush()
end

function GERTiStream:read(n)
    local chunk = nil
    while self.internalString:len() < n do
        event.pull("GERTData", self.address)
        local chunks = self.socket:read()
        if chunks ~= nil then
            local processed = 0
            for _, value in pairs(chunks) do
                self.internalString = self.internalString .. value
                processed = processed + 1
            end
        else
            break
        end
        os.sleep()
    end
    if #self.internalString > 0 then
        chunk = self.internalString:sub(1,n)
        self.internalString = self.internalString:sub(n+1)
    end
    os.sleep()
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

function GERTiModem.send(addr, port, ...)
    openConnections[addr] = true
    local success = false
    local socket = GERTi.openSocket(addr, servicePort)
    local buf = GERTiStream:new(socket, addr)
    debug_print("Waiting for acknowledgement...")
    local response = streamingTable.unpack(buf)
    if response.connection then
        debug_print("Sending connection request...")
        streamingTable.pack(buf, {port=port})
        buf:flush()
        debug_print("Waiting for response...")
        response = streamingTable.unpack(buf)
        if response.accept then
            success = true
            debug_print("Request accepted, sending data...")
            streamingTable.pack(buf, {...})
            debug_print("Sent.")
        else
            debug_print("Request declined.")
        end
    end
    openConnections[addr] = nil
    buf:close()
    return success
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
            debug_print("Request incoming...")
            local socket = GERTi.openSocket(originAddress, connectionID)
            local buf = GERTiStream:new(socket, originAddress)
            debug_print("Socket open, sending acknowledgement...")
            streamingTable.pack(buf, {connection=true})
            buf:flush()
            debug_print("Waiting for response...")
            local request = streamingTable.unpack(buf)
            debug_print("Unpacked... ".. request.port)
            if ports[request.port] then
                debug_print("Port accepted, sending clearance...")
                streamingTable.pack(buf, {accept=true})
                buf:flush()
                debug_print("Receiving payload...")
                local payload = streamingTable.unpack(buf)
                event.push("modem_message", GERTi.getAddress(), originAddress, request.port, table.unpack(payload))
            else
                debug_print("Request declined")
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
component.setPrimary("modem", GERTi_MODEM)

events.GERTiConnection = event.listen("GERTConnectionID", handleGERTiConnection)
--events.GERTiData = event.listen("GERTData", print)
--events.modem_message = event.listen("modem_message", print)
--events.GERTiConnection_Debug = event.listen("GERTConnectionID", print)