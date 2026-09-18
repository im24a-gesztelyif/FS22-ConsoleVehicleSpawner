-- Console Vehicle Spawner for Farming Simulator 22.
-- Loads registered vehicle store items with their default configuration and
-- charges the active farm only after FS22 reports a successful async load.

-- Capture GIANTS' implementation while mod scripts are being sourced, before
-- savegame vehicles run onLoad. Several converted FS19 vehicle mods overwrite
-- this global function from each vehicle instance and thereby break animated
-- loading for unrelated base-game vehicles as well.
local GIANTS_ANIMATED_VEHICLE_UPDATE = AnimatedVehicle ~= nil and AnimatedVehicle.updateAnimation or nil

ConsoleVehicleSpawner = {
    VERSION = "1.2.0.0",
    DEFAULT_DISTANCE = 8,
    MIN_DISTANCE = 4,
    MAX_DISTANCE = 50,
    LOAD_TIMEOUT_MS = 30000,
    pendingSpawn = nil,
    animationEngineRepairCount = 0
}

local COMMANDS = {
    {"listSpawnVehicles", "List spawnable shop items: listSpawnVehicles [filter]", "consoleCommandList"},
    {"spawnVehicle", "Spawn an item: spawnVehicle STORE_INDEX [distance] [free]", "consoleCommandSpawn"}
}

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function getItemLabel(item)
    local brand = ""
    if item.brandIndex ~= nil and g_brandManager ~= nil then
        local brandData = g_brandManager:getBrandByIndex(item.brandIndex)
        if brandData ~= nil and brandData.title ~= nil then
            brand = tostring(brandData.title) .. " "
        end
    end
    return brand .. tostring(item.name or item.xmlFilename or "unnamed item")
end

function ConsoleVehicleSpawner:loadMap()
    for _, command in ipairs(COMMANDS) do
        addConsoleCommand(command[1], command[2], command[3], self)
    end
    Logging.info("[ConsoleVehicleSpawner] Loaded v%s", self.VERSION)
end

function ConsoleVehicleSpawner:deleteMap()
    for _, command in ipairs(COMMANDS) do
        removeConsoleCommand(command[1])
    end
    self.pendingSpawn = nil
end

function ConsoleVehicleSpawner:update(dt)
    if GIANTS_ANIMATED_VEHICLE_UPDATE ~= nil
        and AnimatedVehicle.updateAnimation ~= GIANTS_ANIMATED_VEHICLE_UPDATE then
        AnimatedVehicle.updateAnimation = GIANTS_ANIMATED_VEHICLE_UPDATE
        self.animationEngineRepairCount = self.animationEngineRepairCount + 1
        Logging.warning("[ConsoleVehicleSpawner] Restored GIANTS AnimatedVehicle.updateAnimation after an incompatible mod replaced it globally (repair %d).",
            self.animationEngineRepairCount)
    end

    local pending = self.pendingSpawn
    if pending ~= nil then
        pending.elapsedMs = (pending.elapsedMs or 0) + dt
        if pending.elapsedMs >= self.LOAD_TIMEOUT_MS then
            Logging.error("[ConsoleVehicleSpawner] Timed out loading index=%d '%s' after %.0f seconds. The vehicle mod likely failed during async loading; farm was not charged.",
                pending.storeIndex, getItemLabel(pending.item), self.LOAD_TIMEOUT_MS / 1000)
            self.pendingSpawn = nil
        end
    end
end

function ConsoleVehicleSpawner:getVehicleItems()
    local result = {}
    if g_storeManager == nil then
        return result
    end

    for storeIndex, item in ipairs(g_storeManager:getItems()) do
        if StoreItemUtil.getIsVehicle(item) and g_storeManager:getIsItemUnlocked(item) then
            result[#result + 1] = {storeIndex=storeIndex, item=item}
        end
    end
    return result
end

function ConsoleVehicleSpawner:getDefaultConfigurations(item)
    local configurations = {}
    if item.configurations ~= nil then
        for configurationName, _ in pairs(item.configurations) do
            local defaultId = nil
            if item.defaultConfigurationIds ~= nil then
                defaultId = item.defaultConfigurationIds[configurationName]
            end
            configurations[configurationName] = defaultId or StoreItemUtil.getDefaultConfigId(item, configurationName)
        end
    end
    return configurations
end

function ConsoleVehicleSpawner:getDefaultPrice(item, configurations)
    configurations = configurations or self:getDefaultConfigurations(item)
    return math.max(0, math.floor(StoreItemUtil.getDefaultPrice(item, configurations) or item.price or 0))
end

function ConsoleVehicleSpawner:consoleCommandList(filter)
    if g_currentMission == nil then
        return "Load a savegame first."
    end

    local needle = trim(filter):lower()
    local count = 0
    Logging.info("[ConsoleVehicleSpawner] Spawnable vehicles and trailers%s:",
        needle == "" and "" or string.format(" matching '%s'", needle))

    for _, entry in ipairs(self:getVehicleItems()) do
        local item = entry.item
        local label = getItemLabel(item)
        local haystack = (label .. " " .. tostring(item.xmlFilename or "")):lower()
        if needle == "" or haystack:find(needle, 1, true) ~= nil then
            local price = self:getDefaultPrice(item)
            Logging.info("[ConsoleVehicleSpawner] index=%d | %s | price=%s | xml=%s",
                entry.storeIndex, label, g_i18n:formatMoney(price, 0, true, true), tostring(item.xmlFilename))
            count = count + 1
        end
    end

    return string.format("Found %d item(s). See log.txt/console; use: spawnVehicle STORE_INDEX [distance] [free]", count)
end

function ConsoleVehicleSpawner:getFarmId()
    local mission = g_currentMission
    if mission == nil then return nil end

    if mission.player ~= nil and mission.player.farmId ~= nil then
        return mission.player.farmId
    end
    if mission.controlledVehicle ~= nil and mission.controlledVehicle.getOwnerFarmId ~= nil then
        return mission.controlledVehicle:getOwnerFarmId()
    end
    return nil
end

function ConsoleVehicleSpawner:getSpawnLocation(distance)
    local mission = g_currentMission
    if mission == nil or g_dedicatedServer ~= nil then
        return nil, "This command needs a local host player; it cannot determine a position from a dedicated-server console."
    end

    local object = mission.controlledVehicle or mission.player
    if object == nil or object.rootNode == nil or object.rootNode == 0 or not entityExists(object.rootNode) then
        return nil, "No local player or controlled vehicle position is available."
    end

    local x, y, z = getWorldTranslation(object.rootNode)
    local dirX, _, dirZ = localDirectionToWorld(object.rootNode, 0, 0, 1)
    local length = math.sqrt(dirX * dirX + dirZ * dirZ)
    if length < 0.001 then
        dirX, dirZ, length = 0, 1, 1
    end
    dirX, dirZ = dirX / length, dirZ / length
    x, z = x + dirX * distance, z + dirZ * distance

    if mission.terrainRootNode ~= nil and getTerrainHeightAtWorldPos ~= nil then
        y = math.max(y, getTerrainHeightAtWorldPos(mission.terrainRootNode, x, 0, z))
    end

    return {x=x, y=y + 0.5, z=z, yRot=MathUtil.getYRotationFromDirection(dirX, dirZ)}
end

function ConsoleVehicleSpawner:consoleCommandSpawn(indexText, distanceText, paymentText)
    if g_currentMission == nil then return "Load a savegame first." end
    if g_server == nil then return "Run this command on the host/server console." end
    if self.pendingSpawn ~= nil then return "A vehicle is already loading; wait for it to finish." end

    local storeIndex = tonumber(indexText)
    if storeIndex == nil or storeIndex < 1 or storeIndex % 1 ~= 0 then
        return "Usage: spawnVehicle STORE_INDEX [distance] [free]. Find indices with listSpawnVehicles [filter]."
    end

    local distance = distanceText == nil and self.DEFAULT_DISTANCE or tonumber(distanceText)
    if distance == nil or distance < self.MIN_DISTANCE or distance > self.MAX_DISTANCE then
        return string.format("Distance must be between %d and %d metres.", self.MIN_DISTANCE, self.MAX_DISTANCE)
    end

    local paymentMode = trim(paymentText):lower()
    local isFree = paymentMode == "free" or paymentMode == "true" or paymentMode == "1" or paymentMode == "yes"
    if paymentMode ~= "" and not isFree then
        return "Unknown payment option. Omit it for a paid spawn, or use 'free'."
    end

    local item = g_storeManager:getItemByIndex(storeIndex)
    if item == nil or not StoreItemUtil.getIsVehicle(item) then
        return string.format("Store index %d is not a vehicle or trailer. Run listSpawnVehicles first.", storeIndex)
    end
    if not g_storeManager:getIsItemUnlocked(item) then
        return "That store item is locked or unavailable."
    end

    local farmId = self:getFarmId()
    local farm = farmId ~= nil and g_farmManager:getFarmById(farmId) or nil
    if farm == nil then return "Could not determine the active player's farm." end

    local configurations = self:getDefaultConfigurations(item)
    local price = self:getDefaultPrice(item, configurations)
    if not isFree and farm:getBalance() < price then
        return string.format("Not enough money: %s costs %s (farm balance %s).",
            getItemLabel(item), g_i18n:formatMoney(price), g_i18n:formatMoney(farm:getBalance()))
    end

    local location, locationError = self:getSpawnLocation(distance)
    if location == nil then return locationError end

    self.pendingSpawn = {item=item, farmId=farmId, price=price, storeIndex=storeIndex,
        elapsedMs=0, isFree=isFree}
    VehicleLoadingUtil.loadVehicle(item.xmlFilename, location, true, price,
        Vehicle.PROPERTY_STATE_OWNED, farmId, configurations, nil,
        self.onVehicleLoaded, self, nil)

    Logging.info("[ConsoleVehicleSpawner] Loading index=%d '%s' for farm=%d at (%.2f %.2f %.2f), price=%d, free=%s",
        storeIndex, getItemLabel(item), farmId, location.x, location.y, location.z, price, tostring(isFree))
    if isFree then
        return string.format("Loading %s for free...", getItemLabel(item))
    end
    return string.format("Loading %s... The farm will be charged only if spawning succeeds.", getItemLabel(item))
end

function ConsoleVehicleSpawner:onVehicleLoaded(vehicle, loadingState)
    local pending = self.pendingSpawn
    self.pendingSpawn = nil
    if pending == nil then
        Logging.warning("[ConsoleVehicleSpawner] Received a load callback without a pending purchase.")
        return
    end

    if vehicle == nil or loadingState ~= VehicleLoadingUtil.VEHICLE_LOAD_OK then
        Logging.error("[ConsoleVehicleSpawner] Failed to spawn index=%d '%s'; farm was not charged (state=%s).",
            pending.storeIndex, getItemLabel(pending.item), tostring(loadingState))
        return
    end

    if pending.isFree then
        Logging.info("[ConsoleVehicleSpawner] Spawned '%s' for farm %d for free (normal value %s).",
            getItemLabel(pending.item), pending.farmId, g_i18n:formatMoney(pending.price))
    else
        local moneyType = MoneyType.NEW_VEHICLES or MoneyType.SHOP_VEHICLE_BUY or MoneyType.OTHER
        g_currentMission:addMoney(-pending.price, pending.farmId, moneyType, true, true)
        Logging.info("[ConsoleVehicleSpawner] Spawned '%s' and charged farm %d %s.",
            getItemLabel(pending.item), pending.farmId, g_i18n:formatMoney(pending.price))
    end
end

addModEventListener(ConsoleVehicleSpawner)
