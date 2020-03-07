local component = require("component")
local computer = require("computer")
if not SOFT_COMPONENT_UNALTERED then
    SOFT_COMPONENT_UNALTERED = {}
end

local scua = SOFT_COMPONENT_UNALTERED
local softwareComponents = {}
local overrides = {}
local softComponents = {}
softwareComponents.components = softComponents

-- Use existing metatables from proxies
local componentProxy = getmetatable(component.eeprom)
local componentCallback = getmetatable(component.eeprom.get)


local function generateSubAddress(num)
    return string.format("%x", math.random(math.pow(16,num-1)-1, math.pow(16,num)-1))
end

local function generateAddress()
    local addr = generateSubAddress(8) .. "-"
    addr = addr .. generateSubAddress(4) .. "-"
    addr = addr .. generateSubAddress(4) .. "-"
    addr = addr .. generateSubAddress(4) .. "-"
    addr = addr .. "534f46545741" -- SOFTWA[RE]
    return addr
end

function overrides.invoke(address, method, ...)
    local softwareComponent = softComponents[address]
    local values
    if softwareComponent then
        values = {softwareComponent[2][method](...)}
    else
        values = {scua.invoke(address, method, ...)}
    end
    return table.unpack(values)
end

function overrides.list(filter, exact)
    local matches = scua.list(filter, exact)
    for k, v in pairs(softComponents) do
        if not filter or v[1]:find(filter, 1, not exact) then
            matches[k] = v[1]
        end
    end
    return matches
end

function overrides.type(address)
    local softwareComponent = softComponents[address]
    if softwareComponent then
        return softwareComponent[1]
    else
        return scua.type(address)
    end
end

function overrides.slot(address)
    local softwareComponent = softComponents[address]
    if softwareComponent then
        return -1
    else
        return scua.slot(address)
    end
end

function overrides.methods(address)
    local softwareComponent = softComponents[address]
    local methods
    if softwareComponent then
        methods = {}
        for k, v in pairs(softwareComponent[3]) do
            methods[k] = true
        end
    else
        methods = scua.methods(address)
    end
    return methods
end

function overrides.proxy(address)
    local softwareComponent = softComponents[address]
    local proxy
    if softwareComponent then
        proxy = {address = address, type = softwareComponent[1], slot = -1, fields = {}}
        for k, v in pairs(softwareComponent[3]) do
            proxy[k] = setmetatable({address=address,name=k}, componentCallback)
        end
        setmetatable(proxy, componentProxy)
    else
        proxy = scua.proxy(address)
    end
    return proxy
end

function overrides.doc(address, method)
    local softwareComponent = softComponents[address]
    if softwareComponent then
        return softwareComponent[3][method]
    else
        return scua.slot(address)
    end
end

function softwareComponents.addComponent(componentType, methods)
    local newAddress = generateAddress()
    local docs = {}
    for k, v in pairs(methods) do
        if k:sub(-4) ~= "_doc" and not k:find("__") and type(v) == "function" then
            docs[k] = methods[k .. "_doc"] or "no documentation"
        end
    end
    softComponents[newAddress] = {componentType, methods, docs}
    computer.pushSignal("component_added", newAddress, componentType)
    return newAddress
end

function softwareComponents.removeComponent(address)
    if softComponents[address] then
        computer.pushSignal("component_removed", address, softComponents[address][1])
        if softComponents[address][2].__destroy then
            softComponents[address][2].__destroy(address)
        end
        softComponents[address] = nil
        return true
    else
        return false
    end
end

for k, v in pairs(overrides) do
    SOFT_COMPONENT_UNALTERED[k] = SOFT_COMPONENT_UNALTERED[k] or component[k]
    component[k] = v
end

component.softwareComponents = softwareComponents