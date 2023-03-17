RegisterCommand("PlayRadio", function(src, args, raw)
    -- Get Source
    local srcData = SrcFuncts:GetAll(src)
    local pednil = srcData[2]
    local veh = srcData[3]
    local vehnil = srcData[4]

    -- Check Nils
    if pednil == false and vehnil == false then
        local Coords = GetEntityCoords(veh)
        local Link  = tostring(args[1])
        if Favorites[GetUserID(src)] ~= nil then
            if Favorites[GetUserID(src)][tostring(args[1])] ~= nil then
                Link = Favorites[GetUserID(src)][tostring(args[1])]
            end
        end
        local Volume = tonumber(args[2])
        local Distance = 4.0

        -- Check Args
        if Link ~= nil and Volume ~= nil then
            Sound:Create(veh, "Radio", Link, Volume, Coords, Distance)
            TriggerClientEvent("CRRadio:Notify", src, "Radio Playing!")
        end
    end
end, false)

RegisterCommand("StopRadio", function(src, args, raw)
    -- Get Source
    local srcData = SrcFuncts:GetAll(src)
    local pednil = srcData[2]
    local veh = srcData[3]
    local vehnil = srcData[4]

    -- Check Nils
    if pednil == false and vehnil == false then
        Sound:Delete(veh, "Radio")
        TriggerClientEvent("CRRadio:Notify", src, "Stopped Radio!")
    end
end, false)

RegisterCommand("SetRadio", function(src, args, raw)
    -- Get Source
    local srcData = SrcFuncts:GetAll(src)
    local pednil = srcData[2]
    local veh = srcData[3]
    local vehnil = srcData[4]

    -- Check Nils
    if pednil == false and vehnil == false then
        if string.lower(args[1]) == "volume" then
            local Volume = tonumber(args[2])
            if Volume ~= nil then
                if Volume >= 1 then Volume = 1 end
                if Volume <= 0 then Volume = 0.001 end
                Sound:SetVolume(veh, "Radio", Volume)
                TriggerClientEvent("CRRadio:Notify", src, "Set Volume to " .. Volume)
            end
        end
    end
end, false)

local short_term = {}
RegisterNetEvent("CR.Radio:RestartRadio", function(SoundID)
    local SoundInfo = short_term[SoundID]

    if SoundInfo == nil then return end

    if SoundInfo.isDynamic then
        exports.xsound:PlayUrlPos(-1, SoundID, SoundInfo.url, SoundInfo.volume, SoundInfo.position, SoundInfo.loop)
    else
        exports.xsound:PlayUrl(-1, SoundID, SoundInfo.url, SoundInfo.volume, SoundInfo.loop)
    end
end)

RegisterNetEvent("CR.Radio:PauseRadio", function(SoundID, SoundInfo)
    short_term[SoundID] = SoundInfo
    exports.xsound:Destroy(-1, SoundID)
end)

RegisterNetEvent("CR.Radio:DoubleDistance", function(SoundID, DefaultDistance)
    if DefaultDistance == nil or DefaultDistance == 0 then DefaultDistance = 4 end
    local Distance = DefaultDistance * 3
    exports.xsound:Distance(-1, SoundID, Distance)
end)

RegisterNetEvent("CR.Radio:ResetDistance", function(SoundID, DefaultDistance)
    if DefaultDistance == nil or DefaultDistance == 0 then DefaultDistance = 4 end
    exports.xsound:Distance(-1, SoundID, DefaultDistance)
end)