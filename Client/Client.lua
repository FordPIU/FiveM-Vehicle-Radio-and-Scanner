-- Client/Client.lua

local ResourceName = GetCurrentResourceName()
local isNuiOpen = false
local currentVehicle = 0
local lastVehicle = 0 -- Keep track of the last vehicle player was in
local radioPlaying = false
local currentVolume = Config.DefaultVolume
local currentDistance = Config.DefaultDistance
local currentUrl = ""
local currentSoundId = nil      -- Track the sound ID client-side too
local hasRadioControl = true    -- Assume player has control unless engine off
local lastSetDynamicState = nil -- Track the last dynamic state set for the current sound ID (true=dynamic, false=non-dynamic)

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


-- === NUI Functions === (Keep As Is)

function OpenRadioUI()
    if isNuiOpen then return end
    local ped = PlayerPedId()
    currentVehicle = GetVehiclePedIsIn(ped, false)
    if currentVehicle == 0 then
        Notify(-1, "You must be in a vehicle to open the radio.")
        DebugPrint("OpenRadioUI cancelled: Not in vehicle.")
        return
    end

    isNuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = "ui", display = true })
    DebugPrint("UI Opened")

    -- Request current state and favorites from server/state
    if Config.EnableFavorites then
        TriggerServerEvent("CRRadio:RequestFavorites") -- Ask server for favorites
    end
    SyncStateFromEntity()                              -- Get current radio state from vehicle entity to update UI
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

-- === NUI Callback Handlers === (Keep As Is)

RegisterNUICallback("close", function(data, cb)
    CloseRadioUI()
    cb({ ok = true }) -- NUI expects a JSON response
end)

RegisterNUICallback("play", function(data, cb)
    -- Now expects the direct URL from the UI
    if data and data.url and data.volume ~= nil then
        local volume = tonumber(data.volume) or Config.DefaultVolume
        volume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume)) -- Clamp
        DebugPrint("NUI requested Play URL:", data.url, "Volume:", volume)
        TriggerServerEvent("CRRadio:Play", data.url, volume)                    -- Send direct URL
        cb({ ok = true })
        CloseRadioUI()                                                          -- Optionally close UI after action
    else
        DebugPrint("NUI Play callback received invalid data:", json.encode(data or {}))
        cb({ ok = false, error = "Invalid data received" })
    end
end)

RegisterNUICallback("stop", function(data, cb)
    DebugPrint("NUI requested Stop")
    TriggerServerEvent("CRRadio:Stop")
    cb({ ok = true })
    CloseRadioUI() -- Optionally close UI after action
end)

RegisterNUICallback("setVolume", function(data, cb)
    if data and data.volume ~= nil then
        local volume = tonumber(data.volume) or Config.DefaultVolume
        volume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume)) -- Clamp
        DebugPrint("NUI requested SetVolume:", volume)
        TriggerServerEvent("CRRadio:SetVolume", volume)
        cb({ ok = true })
        -- Keep UI open when changing volume
    else
        DebugPrint("NUI SetVolume callback received invalid data:", json.encode(data or {}))
        cb({ ok = false, error = "Invalid volume data" })
    end
end)

RegisterNUICallback("saveFavorite", function(data, cb)
    -- Expects nickname and url
    if Config.EnableFavorites and data and data.nickname and data.url then
        DebugPrint("NUI requested SaveFavorite:", data.nickname, data.url)
        TriggerServerEvent("CRRadio:SaveFavorite", data.nickname, data.url) -- Pass nickname and url
        cb({ ok = true })
    else
        if not Config.EnableFavorites then DebugPrint("NUI SaveFavorite ignored: Disabled in config") end
        DebugPrint("NUI SaveFavorite callback received invalid data:", json.encode(data or {}))
        cb({ ok = false, error = "Invalid data or favorites disabled" })
    end
end)

RegisterNUICallback("deleteFavorite", function(data, cb)
    -- Expects the unique favUUID
    if Config.EnableFavorites and data and data.favUUID then
        DebugPrint("NUI requested DeleteFavorite:", data.favUUID)
        TriggerServerEvent("CRRadio:DeleteFavorite", data.favUUID) -- Pass favUUID
        cb({ ok = true })
    else
        if not Config.EnableFavorites then DebugPrint("NUI DeleteFavorite ignored: Disabled in config") end
        DebugPrint("NUI DeleteFavorite callback received invalid data:", json.encode(data or {}))
        cb({ ok = false, error = "Invalid data or favorites disabled" })
    end
end)


-- === Event Handlers === (Keep As Is)

-- Receive Favorites List from Server
RegisterNetEvent("CRRadio:ReceiveFavorites", function(favoritesList)
    if not Config.EnableFavorites then return end
    if isNuiOpen then
        DebugPrint("Received favorites list from server, sending to UI")
        -- Send the potentially complex structure as is to JS
        SendNUIMessage({ type = "favorites", favorites = favoritesList or {} })
    else
        DebugPrint("Received favorites list but UI is closed.")
    end
end)

-- Update UI State (Generic, called by SyncStateFromEntity)
function UpdateUIState()
    if isNuiOpen then
        SendNUIMessage({
            type = "updateState",
            state = {
                playing = radioPlaying,
                url = currentUrl, -- Send current URL to potentially fill input
                volume = currentVolume,
            }
        })
        -- DebugPrint("Sent state update to UI:", radioPlaying, currentUrl, currentVolume) -- Can be noisy
    end
end

-- Get current radio state from the vehicle entity's state bag
-- This function runs frequently, keep it efficient
function SyncStateFromEntity()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = lastVehicle end -- Use last vehicle if not in one currently

    local needsUiUpdate = false

    if DoesEntityExist(veh) then
        local state = Entity(veh).state
        -- Use default values if state bag items are nil
        local playingState = state.CrRadioPlaying or false
        local urlState = state.CrRadioURL or ""
        local volumeState = state.CrRadioVolume or Config.DefaultVolume
        local soundIdState = state.CrRadioSoundID or nil
        local distanceState = state.CrRadioDistance or Config.DefaultDistance

        -- Reset dynamic state tracker if sound ID changes or stops playing
        if soundIdState ~= currentSoundId or not playingState then
            lastSetDynamicState = nil
        end

        -- Check if anything relevant changed
        if radioPlaying ~= playingState or currentUrl ~= urlState or currentVolume ~= volumeState or currentSoundId ~= soundIdState or currentDistance ~= distanceState then
            -- DebugPrint("Syncing state from entity | Playing:", playingState, "| URL:", urlState, "| Vol:", volumeState, "| ID:", soundIdState, "| Dist:", distanceState)
            radioPlaying = playingState
            currentUrl = urlState
            currentVolume = volumeState
            currentSoundId = soundIdState
            currentDistance = distanceState -- Update local distance state
            needsUiUpdate = true
        end
    elseif radioPlaying then
        -- Vehicle doesn't exist (or lastVehicle doesn't) but we thought radio was playing? Reset state.
        DebugPrint("Monitored vehicle gone, resetting radio state.")
        radioPlaying = false
        currentUrl = ""
        currentVolume = Config.DefaultVolume
        currentSoundId = nil
        currentDistance = Config.DefaultDistance
        lastSetDynamicState = nil -- Reset dynamic state tracker
        needsUiUpdate = true
    end

    -- Update UI only if needed
    if needsUiUpdate then
        UpdateUIState()
    end
end

-- === Main Logic Thread ===

Citizen.CreateThread(function()
    -- Wait a bit for other resources like xsound to potentially load
    Wait(5000)
    DebugPrint("Client script started. Keybind:", Config.Keybind)

    -- Register Keybind
    if Config.Keybind and Config.Keybind ~= '' then
        local keybindCmd = "+openRadioUI_" .. GetCurrentResourceName() -- Make command unique
        RegisterCommand(keybindCmd, ToggleRadioUI, false)              -- Don't restrict command
        RegisterKeyMapping(keybindCmd, 'Open Vehicle Radio', 'keyboard', Config.Keybind)
        DebugPrint("Keybind registered:", keybindCmd, Config.Keybind)
    else
        DebugPrint("Keybind disabled in config.")
    end

    local xsound = exports.xsound -- Get export once if possible (might need refresh if resource restarts)

    while true do
        local sleep = 500                                -- Default sleep time
        local ped = PlayerPedId()
        local currentVeh = GetVehiclePedIsIn(ped, false) -- Check if player is IN a vehicle NOW
        local engineRunning = true
        local windowsDown = false

        if currentVeh ~= 0 then
            -- Update last vehicle if we are in one
            lastVehicle = currentVeh
        end

        -- Use lastVehicle for most checks to allow sound to persist/adjust after exit
        local vehicleToCheck = lastVehicle -- Primarily monitor the last known vehicle

        if DoesEntityExist(vehicleToCheck) and not IsEntityDead(vehicleToCheck) then
            sleep = 250 -- Check more frequently when near/in a relevant vehicle

            -- Check windows (simplified check - any window broken/down or door open?)
            windowsDown = false -- Reset check each loop
            for i = 0, 3 do
                if not IsVehicleWindowIntact(vehicleToCheck, i) then
                    windowsDown = true
                    break
                end
            end
            if not windowsDown then
                for i = 0, GetNumberOfVehicleDoors(vehicleToCheck) do
                    if GetVehicleDoorAngleRatio(vehicleToCheck, i) > 0.1 then
                        windowsDown = true
                        break
                    end
                end
            end

            -- Sync state from entity bag (includes setting radioPlaying, currentSoundId etc.)
            SyncStateFromEntity()

            -- Perform checks ONLY if radio is supposed to be playing
            if radioPlaying and currentSoundId then
                -- 1. Engine Check (Only stop if player *is currently in* the vehicle and turns off engine)
                if currentVeh ~= 0 and not engineRunning and hasRadioControl then
                    DebugPrint("Engine turned off while player inside, stopping radio.")
                    TriggerServerEvent("CRRadio:Stop")
                    hasRadioControl = false   -- Prevent trying to stop again immediately
                    lastSetDynamicState = nil -- Reset dynamic state as sound is stopping
                elseif currentVeh ~= 0 and engineRunning and not hasRadioControl then
                    DebugPrint("Engine turned back on while player inside, radio control restored.")
                    hasRadioControl = true -- Allow player to start radio again
                end

                -- 2. Window Check (adjust distance based on state)
                local targetDistance = windowsDown and Config.RolledDownDistance or Config.DefaultDistance
                if targetDistance ~= currentDistance then
                    DebugPrint("Window/Door state changed (Windows/Doors Open:", windowsDown, "), setting distance to:",
                        targetDistance)
                    TriggerServerEvent("CRRadio:SetDistance", targetDistance)
                    -- State sync will update currentDistance when state bag updates
                end

                -- 3. Dynamic Sound Check (NEW)
                local shouldBeDynamic = (currentVeh == 0) -- True if player is OUTSIDE the currentVeh, false if inside
                if shouldBeDynamic ~= lastSetDynamicState then
                    -- Check if xsound export is available
                    if xsound and xsound.setSoundDynamic then
                        DebugPrint("Setting dynamic state for SoundID:", currentSoundId, "to:", shouldBeDynamic)
                        xsound:setSoundDynamic(currentSoundId, shouldBeDynamic)
                        lastSetDynamicState = shouldBeDynamic -- Update the tracked state
                    else
                        -- Attempt to get export again if it wasn't available initially
                        xsound = exports.xsound
                        if not xsound or not xsound.setSoundDynamic then
                            DebugPrint("xsound or xsound:setSoundDynamic export not available!")
                            -- Prevent spamming this message
                            lastSetDynamicState = -1 -- Use a placeholder to show we checked and failed
                        else
                            -- Retry immediately if export just became available
                            DebugPrint("Setting dynamic state for SoundID (retry):", currentSoundId, "to:",
                                shouldBeDynamic)
                            xsound:setSoundDynamic(currentSoundId, shouldBeDynamic)
                            lastSetDynamicState = shouldBeDynamic
                        end
                    end
                end
            end -- End if radioPlaying

            -- Reset radio control flag if player is not *currently* in vehicle
            if currentVeh == 0 then
                hasRadioControl = true
            end
        else
            -- Vehicle doesn't exist anymore
            if isNuiOpen then
                DebugPrint("Monitored vehicle gone, closing UI.")
                CloseRadioUI()
            end
            -- Force state sync which should reset playing status etc.
            SyncStateFromEntity()
            lastVehicle = 0 -- Clear last vehicle ref if it no longer exists
        end

        -- If player is far from last vehicle (and not in one), clear lastVehicle ref
        if currentVeh == 0 and lastVehicle ~= 0 and DoesEntityExist(lastVehicle) and DoesEntityExist(ped) then
            if #(GetEntityCoords(ped) - GetEntityCoords(lastVehicle)) > (currentDistance * 1.75) then -- Increase distance slightly
                DebugPrint("Player far from last vehicle, clearing lastVehicle ref.")
                lastVehicle = 0
                -- Force state sync which should reset playing status if needed
                SyncStateFromEntity()
            end
            -- Also clear if last vehicle somehow becomes invalid but wasn't caught above
        elseif currentVeh == 0 and lastVehicle ~= 0 and not DoesEntityExist(lastVehicle) then
            lastVehicle = 0
            SyncStateFromEntity()
        end


        Wait(sleep)
    end
end)

-- Initial state sync attempt shortly after start
Citizen.CreateThread(function()
    Wait(8000) -- Wait a bit longer
    SyncStateFromEntity()
end)


print(string.format("[%s] [Client] Client.lua loaded.", ResourceName))
