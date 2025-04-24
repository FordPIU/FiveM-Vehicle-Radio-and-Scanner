-- Server/_Lib.lua

-- Ensure Config is loaded (may require adding `shared_script 'config.lua'` to fxmanifest)
-- If not using shared_script, you might need to pass config values through events

local SoundIDs = {}       -- Tracks active sound IDs { [soundId] = true }
local Sounds = {}         -- Tracks sounds per entity { [entityNetId] = { radioSoundId = "...", currentVolume = 0.5, currentDistance = 10.0, url = "..." } }
local EntitySoundMap = {} -- Maps sound ID back to entity { [soundId] = entityNetId }

local ResourceName = GetCurrentResourceName()

-- Debug Print Helper
local function DebugPrint(...)
    if Config.DebugPrint then
        local args = { ... }
        local printArgs = { string.format("[%s] [Server]", ResourceName) }
        for _, v in ipairs(args) do
            table.insert(printArgs, tostring(v))
        end
        print(table.unpack(printArgs))
    end
end

-- Sound Management Object
SoundManager = {}

-- Generate a unique sound ID
function SoundManager:GetUID()
    local soundId = ResourceName .. ":" .. math.random(10000, 99999)
    while SoundIDs[soundId] ~= nil do
        Wait(1) -- Prevent potential infinite loop in extreme cases
        soundId = ResourceName .. ":" .. math.random(10000, 99999)
    end
    SoundIDs[soundId] = true
    DebugPrint("Generated Sound ID:", soundId)
    return soundId
end

-- Create or Replace Radio Sound for an Entity
function SoundManager:CreateRadio(entity, url, volume, distance)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId then
        DebugPrint("Error creating radio: Could not get Net ID for entity", entity)
        return nil
    end

    -- Clean up existing sound for this entity, if any
    SoundManager:DeleteRadio(entity)

    local coords = GetEntityCoords(entity)
    local soundId = SoundManager:GetUID()
    local safeVolume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume))
    local safeDistance = distance or Config.DefaultDistance

    DebugPrint(string.format(
        "Creating Sound | Entity: %d | NetID: %d | SoundID: %s | URL: %s | Vol: %.2f | Pos: %s | Dist: %.1f",
        entity, netId, soundId, url, safeVolume, coords, safeDistance))

    -- Use xsound export (ensure xsound is running)
    local xsound = exports.xsound
    if not xsound then
        print(string.format("[%s] [Server] Error: xsound export not found!", ResourceName))
        SoundIDs[soundId] = nil -- Release the reserved ID
        return nil
    end

    xsound:PlayUrlPos(-1, soundId, url, safeVolume, coords, true) -- Play for all clients (-1)
    xsound:Distance(-1, soundId, safeDistance)

    -- Store sound information
    Sounds[netId] = {
        radioSoundId = soundId,
        currentVolume = safeVolume,
        currentDistance = safeDistance,
        url = url,
        coords = coords,
        entity = entity -- Store direct entity handle for easier access in Tick
    }
    EntitySoundMap[soundId] = netId

    -- Update entity state (optional, but can be useful for client sync)
    Entity(entity).state:set("CrRadioPlaying", true, true)
    Entity(entity).state:set("CrRadioSoundID", soundId, true)
    Entity(entity).state:set("CrRadioURL", url, true)
    Entity(entity).state:set("CrRadioVolume", safeVolume, true)
    Entity(entity).state:set("CrRadioDistance", safeDistance, true)


    return soundId
end

-- Delete Radio Sound for an Entity
function SoundManager:DeleteRadio(entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or not Sounds[netId] then return end

    local soundData = Sounds[netId]
    local soundId = soundData.radioSoundId

    DebugPrint(string.format("Deleting Sound | Entity: %d | NetID: %d | SoundID: %s", entity, netId, soundId))

    local xsound = exports.xsound
    if xsound then
        xsound:Destroy(-1, soundId)
    else
        print(string.format("[%s] [Server] Error: xsound export not found during delete!", ResourceName))
    end

    -- Clear tracked data
    SoundIDs[soundId] = nil
    EntitySoundMap[soundId] = nil
    Sounds[netId] = nil

    -- Clear entity state
    Entity(entity).state:set("CrRadioPlaying", nil, true)
    Entity(entity).state:set("CrRadioSoundID", nil, true)
    Entity(entity).state:set("CrRadioURL", nil, true)
    Entity(entity).state:set("CrRadioVolume", nil, true)
    Entity(entity).state:set("CrRadioDistance", nil, true)
end

-- Set Radio Volume
function SoundManager:SetVolume(entity, volume)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or not Sounds[netId] then return end

    local soundData = Sounds[netId]
    local soundId = soundData.radioSoundId
    local safeVolume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume))

    if soundData.currentVolume == safeVolume then return end -- No change

    DebugPrint(string.format("Setting Volume | Entity: %d | NetID: %d | SoundID: %s | New Vol: %.2f",
        entity, netId, soundId, safeVolume))

    local xsound = exports.xsound
    if xsound then
        xsound:setVolume(-1, soundId, safeVolume)
        soundData.currentVolume = safeVolume
        Entity(entity).state:set("CrRadioVolume", safeVolume, true) -- Update state
    else
        print(string.format("[%s] [Server] Error: xsound export not found during setVolume!", ResourceName))
    end
end

-- Set Radio Distance (e.g., for window state)
function SoundManager:SetDistance(entity, distance)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or not Sounds[netId] then return end

    local soundData = Sounds[netId]
    local soundId = soundData.radioSoundId
    local safeDistance = distance

    if soundData.currentDistance == safeDistance then return end -- No change

    DebugPrint(string.format("Setting Distance | Entity: %d | NetID: %d | SoundID: %s | New Dist: %.1f",
        entity, netId, soundId, safeDistance))

    local xsound = exports.xsound
    if xsound then
        xsound:Distance(-1, soundId, safeDistance)
        soundData.currentDistance = safeDistance
        Entity(entity).state:set("CrRadioDistance", safeDistance, true) -- Update state
    else
        print(string.format("[%s] [Server] Error: xsound export not found during setDistance!", ResourceName))
    end
end

-- Update sound positions periodically
function SoundManager:Tick()
    local xsound = exports.xsound
    if not xsound then return end -- Don't tick if xsound isn't ready

    local entitiesToDelete = {}

    for netId, soundData in pairs(Sounds) do
        local entity = NetworkGetEntityFromNetworkId(netId) -- More reliable way to get entity handle
        if not DoesEntityExist(entity) or IsEntityDead(entity) or GetVehicleEngineHealth(entity) <= 0 then
            -- Entity gone or destroyed, mark for cleanup
            table.insert(entitiesToDelete, entity)
            DebugPrint(string.format("Marking entity for deletion | Entity: %d | NetID: %d | Reason: %s",
                entity or "N/A", netId, not DoesEntityExist(entity) and "Doesn't Exist" or "Dead/Destroyed"))
        else
            -- Update position if it has changed significantly
            local currentCoords = GetEntityCoords(entity)
            if #(currentCoords - soundData.coords) > 0.1 then -- Check distance moved
                -- DebugPrint(string.format("Updating Position | Entity: %d | NetID: %d | SoundID: %s | Pos: %s",
                --    entity, netId, soundData.radioSoundId, currentCoords))
                xsound:Position(-1, soundData.radioSoundId, currentCoords)
                soundData.coords = currentCoords -- Update stored coords
            end
        end
    end

    -- Perform deletions outside the main loop
    for _, entityHandle in ipairs(entitiesToDelete) do
        SoundManager:DeleteRadio(entityHandle) -- Use the function to ensure proper cleanup
    end
end

-- Start the position update loop
Citizen.CreateThread(function()
    while true do
        SoundManager:Tick()
        Wait(250) -- Update positions 4 times per second, adjust as needed
    end
end)

-- Cleanup sounds on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == ResourceName then
        print(string.format("[%s] [Server] Cleaning up sounds on resource stop...", ResourceName))
        local xsound = exports.xsound
        if xsound then
            for soundId, _ in pairs(SoundIDs) do
                if soundId then -- Check if soundId is valid before attempting destroy
                    DebugPrint("Stopping sound:", soundId)
                    xsound:Destroy(-1, soundId)
                end
            end
        end
        -- Clear tables
        SoundIDs = {}
        Sounds = {}
        EntitySoundMap = {}
        print(string.format("[%s] [Server] Cleanup complete.", ResourceName))
    end
end)

--[[ Handle player leaving vehicle - client should manage this and tell server to stop if needed
RegisterEventHandler('playerDropped', function(reason)
    local src = source
    local ped = GetPlayerPed(src)
    -- Find if this player was associated with any sound (more complex logic needed)
    -- This might be better handled client-side sending a 'stop' event on exit
end)
]] --

print(string.format("[%s] [Server] _Lib.lua loaded.", ResourceName))
