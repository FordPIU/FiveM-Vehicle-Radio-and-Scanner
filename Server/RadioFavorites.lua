ResourceName = GetCurrentResourceName()
Favorites = {}
Files = {}

function GetUserID(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, identifier in ipairs(identifiers) do
        if string.match(identifier, "^license:") then
            return string.sub(identifier, 9)
        end
    end
    return nil
end

RegisterCommand("FavoriteRadio", function(src, args, raw)
    local srcData = SrcFuncts:GetAll(src)

    if srcData[2] == false and srcData[4] == false then
        local url = args[1]
        local ide = args[2]

        if url ~= nil and ide ~= nil then
            local UserID = GetUserID(src)

            if UserID == nil then
                TriggerClientEvent("CRRadio:Notify", src, "User ID Is Somehow Nil")
                return
            end

            if Favorites[UserID] == nil then Favorites[UserID] = {} end
            if Files[UserID] == nil then Files[UserID] = true end

            Favorites[UserID][ide] = url

            SaveResourceFile(ResourceName, "Favorites/" .. UserID .. ".json", json.encode(Favorites[UserID]), -1)
            SaveResourceFile(ResourceName, "Favorites/_FILES.json",
                json.encode(Files),
            -1)

            TriggerClientEvent("CRRadio:Notify", src, "Favorite Radio Added!")
        else
            TriggerClientEvent("CRRadio:Notify", src, "Invalid Arguments!")
        end
    end
end)

RegisterCommand("FavoritesPrint", function(src, args, raw)
    local srcData = SrcFuncts:GetAll(src)

    if srcData[2] == false and srcData[4] == false then
        for i,v in pairs(Favorites[GetUserID(src)]) do
            print("Favorite " .. i .. " is URL " .. v)
        end
    end
end, false)

Citizen.CreateThread(function()
    local UserIDs = json.decode(LoadResourceFile(ResourceName, "Favorites/_FILES.json"))

    if UserIDs ~= nil then
        for UserID,_ in pairs(UserIDs) do
            local UserData = json.decode(LoadResourceFile(ResourceName, "Favorites/" .. UserID .. ".json"))
            Favorites[UserID] = UserData
        end
    end
end)