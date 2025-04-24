-- Server/Server.lua

local ResourceName = GetCurrentResourceName()
local Favorites = {}     -- { [license] = { [favId] = url, ... }, ... }
local FavoriteFiles = {} -- { [license] = true, ... } - Tracks which licenses have files

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

-- Get Player License Identifier
local function GetUserID(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, identifier in ipairs(identifiers) do
        if string.match(identifier, "^license:") then
            return identifier -- Return full license identifier
        end
    end
    DebugPrint("Could not get license identifier for source:", src)
    return nil
end

-- Load Favorites on Start
Citizen.CreateThread(function()
    if not Config.EnableFavorites then return end

    local fileData = LoadResourceFile(ResourceName, "Favorites/_FILES.json")
    if fileData then
        local success, decodedData = pcall(json.decode, fileData)
        if success and type(decodedData) == 'table' then
            FavoriteFiles = decodedData
            DebugPrint("Loaded _FILES.json index.")

            for userId, _ in pairs(FavoriteFiles) do
                local favData = LoadResourceFile(ResourceName, "Favorites/" .. userId .. ".json")
                if favData then
                    local favSuccess, favDecoded = pcall(json.decode, favData)
                    if favSuccess and type(favDecoded) == 'table' then
                        Favorites[userId] = favDecoded
                        DebugPrint("Loaded favorites for:", userId)
                    else
                        DebugPrint("Failed to decode favorites for:", userId, "- Error:", favDecoded or "Unknown")
                    end
                else
                    DebugPrint("Could not load favorites file for:", userId, "(referenced in index)")
                end
            end
        else
            DebugPrint("Failed to decode _FILES.json or it's not a table. Error:", decodedData or "Unknown")
        end
    else
        DebugPrint("_FILES.json not found. Starting fresh.")
    end
    print(string.format("[%s] [Server] Favorites system initialized.", ResourceName))
end)

-- Save Favorites Function
local function SaveUserFavorites(userId)
    if not Config.EnableFavorites or not userId or not Favorites[userId] then return end

    local success, encodedData = pcall(json.encode, Favorites[userId])
    if success then
        if SaveResourceFile(ResourceName, "Favorites/" .. userId .. ".json", encodedData, -1) then
            DebugPrint("Saved favorites for:", userId)
            -- Update and save the index file
            FavoriteFiles[userId] = true
            local indexSuccess, indexEncoded = pcall(json.encode, FavoriteFiles)
            if indexSuccess then
                SaveResourceFile(ResourceName, "Favorites/_FILES.json", indexEncoded, -1)
                DebugPrint("Updated _FILES.json index.")
            else
                DebugPrint("Failed to encode _FILES.json. Error:", indexEncoded)
            end
        else
            DebugPrint("Failed to save favorites file for:", userId)
        end
    else
        DebugPrint("Failed to encode favorites for:", userId, "- Error:", encodedData)
    end
end

-- === Network Events from Client UI ===

-- Request to Play Radio
RegisterNetEvent("CRRadio:Play", function(urlOrFavId, volume)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false) -- Only if currently in vehicle
    if not veh or veh == 0 then
        Notify(src, "You must be in a vehicle to use the radio.")
        return
    end

    local userId = GetUserID(src)
    local finalUrl = urlOrFavId
    local finalVolume = tonumber(volume) or Config.DefaultVolume

    -- Check if it's a favorite ID
    if Config.EnableFavorites and userId and Favorites[userId] and Favorites[userId][urlOrFavId] then
        finalUrl = Favorites[userId][urlOrFavId]
        DebugPrint("Playing favorite:", urlOrFavId, "->", finalUrl, "for source:", src)
    else
        DebugPrint("Playing URL:", finalUrl, "for source:", src)
    end

    -- Basic URL validation (very simple)
    if not string.match(finalUrl, "^http[s]?://") then
        Notify(src, "Invalid radio URL format.")
        DebugPrint("Invalid URL format:", finalUrl)
        return
    end

    -- Let SoundManager handle creation and state
    local soundId = SoundManager:CreateRadio(veh, finalUrl, finalVolume, Config.DefaultDistance)

    if soundId then
        Notify(src, "Radio started playing.")
        -- Tell client the state changed (optional, state sync might handle it)
        -- TriggerClientEvent("CRRadio:UpdateState", src, true, finalUrl, finalVolume, Config.DefaultDistance, soundId)
    else
        Notify(src, "Failed to start radio.")
    end
end)

-- Request to Stop Radio
RegisterNetEvent("CRRadio:Stop", function()
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    -- Allow stopping even if player just exited (use last vehicle)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end

    if not veh or veh == 0 then
        -- Notify(src, "No vehicle found to stop radio.") -- Maybe not notify if they aren't in one?
        return
    end

    SoundManager:DeleteRadio(veh)
    Notify(src, "Radio stopped.")
    -- TriggerClientEvent("CRRadio:UpdateState", src, false) -- Tell client state changed
end)

-- Request to Set Volume
RegisterNetEvent("CRRadio:SetVolume", function(volume)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return end -- Only set volume if currently inside

    local finalVolume = tonumber(volume)
    if finalVolume == nil then
        Notify(src, "Invalid volume value.")
        return
    end

    finalVolume = math.max(Config.MinVolume, math.min(Config.MaxVolume, finalVolume)) -- Clamp volume

    SoundManager:SetVolume(veh, finalVolume)
    Notify(src, string.format("Radio volume set to %.0f%%", finalVolume * 100))
    -- TriggerClientEvent("CRRadio:UpdateState", src, true, nil, finalVolume) -- Update client volume state
end)

-- Request to Set Distance (Called by client based on window/engine state)
RegisterNetEvent("CRRadio:SetDistance", function(distance)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    -- Use last vehicle in case player just exited but sound is still playing
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
    if not veh or veh == 0 then return end

    local finalDistance = tonumber(distance)
    if not finalDistance then return end

    SoundManager:SetDistance(veh, finalDistance)
    -- No notification needed for distance change usually
    DebugPrint("Distance updated for vehicle", NetworkGetNetworkIdFromEntity(veh), "to", finalDistance)
    -- TriggerClientEvent("CRRadio:UpdateState", src, true, nil, nil, finalDistance) -- Update client distance state
end)


-- Request to Save Favorite
RegisterNetEvent("CRRadio:SaveFavorite", function(favId, url)
    if not Config.EnableFavorites then return end

    local src = source
    local userId = GetUserID(src)
    if not userId then
        Notify(src, "Error retrieving user ID.")
        return
    end

    if not favId or favId == "" or not url or not string.match(url, "^http[s]?://") then
        Notify(src, "Invalid Favorite ID or URL format.")
        return
    end

    if Favorites[userId] == nil then Favorites[userId] = {} end

    Favorites[userId][favId] = url
    SaveUserFavorites(userId)

    Notify(src, string.format("Favorite '%s' saved.", favId))
    -- Send updated list back to the client's UI
    TriggerClientEvent("CRRadio:ReceiveFavorites", src, Favorites[userId])
end)

-- Request to Delete Favorite
RegisterNetEvent("CRRadio:DeleteFavorite", function(favId)
    if not Config.EnableFavorites then return end

    local src = source
    local userId = GetUserID(src)
    if not userId or not Favorites[userId] or not Favorites[userId][favId] then
        Notify(src, "Favorite not found.")
        return
    end

    Favorites[userId][favId] = nil
    SaveUserFavorites(userId)

    Notify(src, string.format("Favorite '%s' deleted.", favId))
    -- Send updated list back to the client's UI
    TriggerClientEvent("CRRadio:ReceiveFavorites", src, Favorites[userId])
end)


-- Request for Favorites List
RegisterNetEvent("CRRadio:RequestFavorites", function()
    if not Config.EnableFavorites then return end

    local src = source
    local userId = GetUserID(src)
    local userFavorites = {}

    if userId and Favorites[userId] then
        userFavorites = Favorites[userId]
    end

    DebugPrint("Sending favorites list to source:", src)
    TriggerClientEvent("CRRadio:ReceiveFavorites", src, userFavorites)
end)

print(string.format("[%s] [Server] Server.lua loaded.", ResourceName))
