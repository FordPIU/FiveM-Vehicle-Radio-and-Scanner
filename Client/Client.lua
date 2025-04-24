-- Client/Client.lua

local ResourceName = GetCurrentResourceName()
local isNuiOpen = false
local currentVehicle = 0
local lastVehicle = 0
local radioPlaying = false
local currentVolume = Config.DefaultVolume
local currentDistance = Config.DefaultDistance
local currentUrl = ""
local currentSoundId = nil   -- Track the sound ID client-side too
local hasRadioControl = true -- Assume player has control unless engine off

-- Debug Print Helper
local function DebugPrint(...)
    if Config.DebugPrint then
        local args = { ... }
        local printArgs = { string.format("[%s] [Client]", ResourceName) }
        for _, v in ipairs(args) do
            table.insert(printArgs, tostring(v))
        end
        print(table.unpack(printArgs))
    end
end


-- === NUI Functions ===

function OpenRadioUI()
    if isNuiOpen then return end
    local ped = PlayerPedId()
    currentVehicle = GetVehiclePedIsIn(ped, false)
    if currentVehicle == 0 then
        Notify(-1, "You must be in a vehicle to open the radio.")
        return
    end

    isNuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "ui", display = true })
    DebugPrint("UI Opened")

    -- Request current state and favorites from server/state
    TriggerServerEvent("CRRadio:RequestFavorites") -- Ask server for favorites
    SyncStateFromEntity()                          -- Get current radio state from vehicle entity
end

function CloseRadioUI()
    if not isNuiOpen then return end
    isNuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "ui", display = false })
    DebugPrint("UI Closed")
end

-- Toggle UI
function ToggleRadioUI()
    if isNuiOpen then
        CloseRadioUI()
    else
        OpenRadioUI()
    end
end

-- NUI Callback Handlers
RegisterNUICallback("close", function(data, cb)
    CloseRadioUI()
    cb('ok')
end)

RegisterNUICallback("play", function(data, cb)
    if data and data.url and data.volume ~= nil then
        local volume = tonumber(data.volume) or Config.DefaultVolume
        volume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume)) -- Clamp
        DebugPrint("NUI requested Play:", data.url, "Volume:", volume)
        TriggerServerEvent("CRRadio:Play", data.url, volume)
        -- Assume success for now, state sync will update UI later if needed
        cb('ok')
        CloseRadioUI() -- Optionally close UI after action
    else
        cb('error')
    end
end)

RegisterNUICallback("stop", function(data, cb)
    DebugPrint("NUI requested Stop")
    TriggerServerEvent("CRRadio:Stop")
    -- Assume success for now, state sync will update UI later
    cb('ok')
    CloseRadioUI() -- Optionally close UI after action
end)

RegisterNUICallback("setVolume", function(data, cb)
    if data and data.volume ~= nil then
        local volume = tonumber(data.volume) or Config.DefaultVolume
        volume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume)) -- Clamp
        DebugPrint("NUI requested SetVolume:", volume)
        TriggerServerEvent("CRRadio:SetVolume", volume)
        cb('ok')
        -- Keep UI open when changing volume
    else
        cb('error')
    end
end)

RegisterNUICallback("saveFavorite", function(data, cb)
    if Config.EnableFavorites and data and data.favId and data.url then
        DebugPrint("NUI requested SaveFavorite:", data.favId, data.url)
        TriggerServerEvent("CRRadio:SaveFavorite", data.favId, data.url)
        cb('ok')
    else
        cb('error')
    end
end)

RegisterNUICallback("deleteFavorite", function(data, cb)
    if Config.EnableFavorites and data and data.favId then
        DebugPrint("NUI requested DeleteFavorite:", data.favId)
        TriggerServerEvent("CRRadio:DeleteFavorite", data.favId)
        cb('ok')
    else
        cb('error')
    end
end)


-- === Event Handlers ===

-- Receive Favorites List from Server
RegisterNetEvent("CRRadio:ReceiveFavorites", function(favoritesList)
    if not Config.EnableFavorites then return end
    if isNuiOpen then
        DebugPrint("Received favorites list from server, sending to UI")
        SendNUIMessage({ type = "favorites", favorites = favoritesList or {} })
    end
end)

-- Update UI State (Generic, can be triggered by server or client logic)
function UpdateUIState()
    if isNuiOpen then
        SendNUIMessage({
            type = "updateState",
            state = {
                playing = radioPlaying,
                url = currentUrl,
                volume = currentVolume,
                -- favorites = {} -- Favorites are handled separately via ReceiveFavorites
            }
        })
        DebugPrint("Sent state update to UI:", radioPlaying, currentUrl, currentVolume)
    end
end

-- Get current radio state from the vehicle entity's state bag
function SyncStateFromEntity()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end -- Check last vehicle too

    if DoesEntityExist(veh) then
        local state = Entity(veh).state
        local playingState = state.CrRadioPlaying or false
        local urlState = state.CrRadioURL or ""
        local volumeState = state.CrRadioVolume or Config.DefaultVolume
        local soundIdState = state.CrRadioSoundID or nil
        local distanceState = state.CrRadioDistance or Config.DefaultDistance -- Get distance too

        if radioPlaying ~= playingState or currentUrl ~= urlState or currentVolume ~= volumeState or currentSoundId ~= soundIdState or currentDistance ~= distanceState then
            DebugPrint("Syncing state from entity:", playingState, urlState, volumeState, soundIdState, distanceState)
            radioPlaying = playingState
            currentUrl = urlState
            currentVolume = volumeState
            currentSoundId = soundIdState
            currentDistance = distanceState -- Update local distance
            UpdateUIState()                 -- Update the UI if it's open
        end
    elseif radioPlaying then
        -- Vehicle doesn't exist but we thought radio was playing? Reset state.
        DebugPrint("Vehicle gone, resetting radio state.")
        radioPlaying = false
        currentUrl = ""
        currentVolume = Config.DefaultVolume
        currentSoundId = nil
        UpdateUIState()
    end
end

-- === Main Logic Thread ===

Citizen.CreateThread(function()
    -- Wait for xsound and other resources to be ready (optional safety)
    Wait(5000)
    DebugPrint("Client script started. Keybind:", Config.Keybind)

    -- Register Keybind
    if Config.Keybind and Config.Keybind ~= '' then
        RegisterCommand('+openRadioUI', ToggleRadioUI, false)
        RegisterKeyMapping('+openRadioUI', 'Open Vehicle Radio', 'keyboard', Config.Keybind)
        DebugPrint("Keybind registered.")
    else
        DebugPrint("Keybind disabled in config.")
    end

    while true do
        local sleep = 500 -- Default sleep time
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local engineRunning = false
        local windowsDown = false

        if veh ~= 0 and DoesEntityExist(veh) and not IsEntityDead(veh) then
            sleep = 150                             -- Check more frequently when in a vehicle
            engineRunning = IsVehicleEngineOn(veh)  -- More reliable than GetIsVehicleEngineRunning

            -- Check windows (simplified check - any window broken/down?)
            for i = 0, GetNumberOfVehicleDoors(veh) do  -- Check doors too as they affect sound
                if IsVehicleWindowIntact(veh, i) ~= true or GetVehicleDoorAngleRatio(veh, i) > 0.1 then
                    windowsDown = true
                    break
                end
            end
            -- Optional: More precise check if needed: AreAllWindowsRolledDown(veh) - might not exist or work reliably.

            -- Sync state from entity bag
            SyncStateFromEntity()

            -- Realism Checks
            if radioPlaying then
                -- 1. Engine Check
                if not engineRunning and hasRadioControl then
                    DebugPrint("Engine turned off, stopping radio.")
                    TriggerServerEvent("CRRadio:Stop")
                    hasRadioControl = false  -- Prevent trying to stop again immediately
                elseif engineRunning and not hasRadioControl then
                    DebugPrint("Engine turned back on, radio control restored (won't auto-restart).")
                    hasRadioControl = true   -- Allow player to start radio again
                end

                -- 2. Window Check (only if engine is running)
                if engineRunning then
                    local targetDistance = windowsDown and Config.RolledDownDistance or Config.DefaultDistance
                    if targetDistance ~= currentDistance then
                        DebugPrint("Window state changed (Windows Down:", windowsDown, "), setting distance to:",
                            targetDistance)
                        TriggerServerEvent("CRRadio:SetDistance", targetDistance)
                        -- The state sync will update currentDistance when the server confirms
                    end
                end
            end
        elseif isNuiOpen then
            -- Automatically close UI if player leaves vehicle
            DebugPrint("Player left vehicle, closing UI.")
            CloseRadioUI()
            -- Don't reset radioPlaying here, SyncStateFromEntity handles it if vehicle disappears
        end

        Wait(sleep)
    end
end)

print(string.format("[%s] [Client] Client.lua loaded.", ResourceName))
