-- Server/Server.lua

local ResourceName = GetCurrentResourceName()
-- New Favorites Structure: { [license] = { [favUUID] = { nickname = "...", url = "..." }, ... } }
local Favorites = {}
local FavoriteFiles = {} -- Still tracks which licenses have files { [license] = true }

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

-- Function to generate a simple unique-ish ID for favorites
local function GenerateFavoriteUUID()
    -- Simple combination of time and random number (not truly UUID)
    return string.format("fav_%d_%d", os.time(), math.random(10000, 99999))
end

-- Load Favorites on Start (Updated to handle new structure)
Citizen.CreateThread(function()
    if not Config.EnableFavorites then
        print(string.format("[%s] [Server] Favorites system disabled in config.", ResourceName))
        return
    end

    local fileData = LoadResourceFile(ResourceName, "Favorites/_FILES.json")
    if fileData then
        local success, decodedData = pcall(json.decode, fileData)
        if success and type(decodedData) == 'table' then
            FavoriteFiles = decodedData
            DebugPrint("Loaded _FILES.json index.")

            for userId, _ in pairs(FavoriteFiles) do
                local favFilePath = "Favorites/" .. userId .. ".json"
                local favData = LoadResourceFile(ResourceName, favFilePath)
                if favData then
                    local favSuccess, favDecoded = pcall(json.decode, favData)
                    -- Basic validation for new structure (check if first item has nickname/url)
                    local isValidStructure = false
                    if favSuccess and type(favDecoded) == 'table' then
                        -- Check if it's empty or if the first element looks correct
                        local firstKey = next(favDecoded)
                        if not firstKey or (type(favDecoded[firstKey]) == 'table' and favDecoded[firstKey].nickname and favDecoded[firstKey].url) then
                            isValidStructure = true
                        end
                    end

                    if isValidStructure then
                        Favorites[userId] = favDecoded
                        DebugPrint("Loaded favorites for:", userId)
                    else
                        DebugPrint("Failed to decode favorites for:", userId,
                            "or structure is outdated/invalid from file:", favFilePath, ". Error/Data:",
                            favDecoded or "Unknown Decode Error")
                        -- Handle outdated structure? Maybe backup and reset?
                        -- os.rename(GetCurrentResourcePath() .. "/" .. favFilePath, GetCurrentResourcePath() .. "/" .. favFilePath .. ".old")
                        -- Favorites[userId] = {}
                        -- SaveUserFavorites(userId) -- This would create a new empty file
                    end
                else
                    DebugPrint("Could not load favorites file for:", userId, "(referenced in index at path:", favFilePath,
                        ")")
                end
            end
        else
            DebugPrint("Failed to decode _FILES.json or it's not a table. Error:", decodedData or "Unknown Decode Error")
        end
    else
        DebugPrint("_FILES.json not found. Starting fresh.")
    end
    print(string.format("[%s] [Server] Favorites system initialized.", ResourceName))
end)

-- Save Favorites Function
local function SaveUserFavorites(userId)
    if not Config.EnableFavorites or not userId or not Favorites[userId] then
        DebugPrint("SaveUserFavorites skipped: Favorites disabled, no userId, or no favorites data for user:", userId)
        return
    end

    local favFilePath = "Favorites/" .. userId .. ".json"
    -- Ensure the Favorites directory exists (optional but good practice)
    -- CreateDirectory(GetCurrentResourcePath() .. "/Favorites") -- Requires server permissions

    local success, encodedData = pcall(json.encode, Favorites[userId])
    if success then
        if SaveResourceFile(ResourceName, favFilePath, encodedData, -1) then
            DebugPrint("Saved favorites for:", userId, "to", favFilePath)
            -- Update and save the index file
            FavoriteFiles[userId] = true
            local indexSuccess, indexEncoded = pcall(json.encode, FavoriteFiles)
            if indexSuccess then
                if SaveResourceFile(ResourceName, "Favorites/_FILES.json", indexEncoded, -1) then
                    DebugPrint("Updated _FILES.json index.")
                else
                    DebugPrint("!!! Failed to save _FILES.json index.")
                end
            else
                DebugPrint("!!! Failed to encode _FILES.json. Error:", indexEncoded or "Unknown Encode Error")
            end
        else
            DebugPrint("!!! Failed to save favorites file:", favFilePath)
        end
    else
        DebugPrint("!!! Failed to encode favorites for:", userId, "- Error:", encodedData or "Unknown Encode Error")
    end
end

-- === Network Events from Client UI ===

-- Request to Play Radio (Now expects only a direct URL)
RegisterNetEvent("CRRadio:Play", function(url, volume)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        DebugPrint("Play request failed: Could not get player ped for source:", src)
        return
    end

    local veh = GetVehiclePedIsIn(ped, false) -- Only if currently in vehicle
    if not veh or veh == 0 then
        Notify(src, "You must be in a vehicle to use the radio.")
        DebugPrint("Play request failed: Player", src, "not in a vehicle.")
        return
    end

    local finalUrl = url -- No more favorite ID lookup here
    local finalVolume = tonumber(volume) or Config.DefaultVolume

    DebugPrint("Processing Play request | Source:", src, "| URL:", finalUrl, "| Volume:", finalVolume)

    -- Basic URL validation
    if not finalUrl or not string.match(finalUrl, "^http[s]?://") then
        Notify(src, "Invalid radio URL format.")
        DebugPrint("Play request failed: Invalid URL format:", finalUrl)
        return
    end

    -- Let SoundManager handle creation
    local soundId = SoundManager:CreateRadio(veh, finalUrl, finalVolume, Config.DefaultDistance)

    if soundId then
        Notify(src, "Radio started playing.")
        DebugPrint("Radio play successful | Source:", src, "| Vehicle:", NetworkGetNetworkIdFromEntity(veh), "| SoundID:",
            soundId)
    else
        Notify(src, "Failed to start radio. Check URL/stream or server console.")
        DebugPrint("!!! Radio play failed | Source:", src, "| Vehicle:", NetworkGetNetworkIdFromEntity(veh), "| URL:",
            finalUrl)
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
        DebugPrint("Stop request ignored: No current or last vehicle found for source:", src)
        return
    end

    DebugPrint("Processing Stop request | Source:", src, "| Vehicle:", NetworkGetNetworkIdFromEntity(veh))
    SoundManager:DeleteRadio(veh)
    Notify(src, "Radio stopped.")
end)

-- Request to Set Volume
RegisterNetEvent("CRRadio:SetVolume", function(volume)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        DebugPrint("SetVolume request ignored: Player", src, "not in a vehicle.")
        return
    end -- Only set volume if currently inside

    local finalVolume = tonumber(volume)
    if finalVolume == nil then
        Notify(src, "Invalid volume value.")
        DebugPrint("SetVolume request failed: Invalid volume value:", volume)
        return
    end

    finalVolume = math.max(Config.MinVolume, math.min(Config.MaxVolume, finalVolume)) -- Clamp volume

    DebugPrint("Processing SetVolume request | Source:", src, "| Vehicle:", NetworkGetNetworkIdFromEntity(veh),
        "| Volume:", finalVolume)
    SoundManager:SetVolume(veh, finalVolume)
    Notify(src, string.format("Radio volume set to %.0f%%", finalVolume * 100))
end)

-- Request to Set Distance (Called by client based on window/engine state)
RegisterNetEvent("CRRadio:SetDistance", function(distance)
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    -- Use last vehicle in case player just exited but sound is still playing
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
    if not veh or veh == 0 then
        DebugPrint("SetDistance request ignored: No current or last vehicle found for source:", src)
        return
    end

    local finalDistance = tonumber(distance)
    if not finalDistance then
        DebugPrint("SetDistance request failed: Invalid distance value:", distance)
        return
    end

    DebugPrint("Processing SetDistance request | Source:", src, "| Vehicle:", NetworkGetNetworkIdFromEntity(veh),
        "| Distance:", finalDistance)
    SoundManager:SetDistance(veh, finalDistance)
end)


-- Request to Save Favorite (Updated)
RegisterNetEvent("CRRadio:SaveFavorite", function(nickname, url)
    if not Config.EnableFavorites then
        Notify(src, "Favorites system is disabled on the server.")
        return
    end

    local src = source
    local userId = GetUserID(src)
    if not userId then
        Notify(src, "Error retrieving user ID. Cannot save favorite.")
        DebugPrint("SaveFavorite failed: Could not get UserID for source", src)
        return
    end

    -- Validate inputs
    if not nickname or nickname == "" or not url or not string.match(url, "^http[s]?://") then
        Notify(src, "Invalid Nickname or URL format for favorite.")
        DebugPrint("SaveFavorite failed: Invalid nickname or URL format | Nickname:", nickname, "| URL:", url)
        return
    end

    if Favorites[userId] == nil then Favorites[userId] = {} end

    -- Check for duplicate nicknames (optional, but good UX)
    for favUUID, favData in pairs(Favorites[userId]) do
        if favData.nickname == nickname then
            Notify(src, string.format("A favorite with the nickname '%s' already exists.", nickname))
            DebugPrint("SaveFavorite failed: Duplicate nickname found | User:", userId, "| Nickname:", nickname)
            return
        end
    end

    local favUUID = GenerateFavoriteUUID() -- Generate a unique ID for this favorite
    Favorites[userId][favUUID] = { nickname = nickname, url = url }
    DebugPrint("Saving new favorite | User:", userId, "| UUID:", favUUID, "| Nickname:", nickname, "| URL:", url)
    SaveUserFavorites(userId)

    Notify(src, string.format("Favorite '%s' saved.", nickname))
    -- Send updated list back to the client's UI
    TriggerClientEvent("CRRadio:ReceiveFavorites", src, Favorites[userId])
end)

-- Request to Delete Favorite (Updated to use favUUID)
RegisterNetEvent("CRRadio:DeleteFavorite", function(favUUID)
    if not Config.EnableFavorites then
        Notify(src, "Favorites system is disabled on the server.")
        return
    end

    local src = source
    local userId = GetUserID(src)

    -- Check if favorite exists before trying to delete
    if not userId or not Favorites[userId] or not Favorites[userId][favUUID] then
        Notify(src, "Favorite not found or already deleted.")
        DebugPrint("DeleteFavorite failed: FavUUID", favUUID, "not found for user", userId)
        -- Optionally send updated list back even if not found, to ensure client UI is correct
        if userId and Favorites[userId] then TriggerClientEvent("CRRadio:ReceiveFavorites", src, Favorites[userId]) end
        return
    end

    local deletedNickname = Favorites[userId][favUUID].nickname -- Get name for notification
    DebugPrint("Deleting favorite | User:", userId, "| UUID:", favUUID, "| Nickname:", deletedNickname)
    Favorites[userId][favUUID] = nil                            -- Remove the favorite entry
    SaveUserFavorites(userId)

    Notify(src, string.format("Favorite '%s' deleted.", deletedNickname))
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
    elseif userId then
        DebugPrint("No favorites found for user:", userId, "when requested.")
    else
        DebugPrint("Could not get UserID for source", src, "when requesting favorites.")
    end

    DebugPrint("Sending favorites list to source:", src)
    TriggerClientEvent("CRRadio:ReceiveFavorites", src, userFavorites)
end)

print(string.format("[%s] [Server] Server.lua loaded.", ResourceName))
