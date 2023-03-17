Citizen.CreateThread(function()
    Wait(2000)
    while true do
        Wait(0)

        -- Vehicle Loop
        for _,v in pairs(GetAllVehicles()) do
            -- Setup Variables
            local vPoliceRadio = PoliceRadios[GetEntityModel(v)]
            local vPoliceState = Entity(v).state.Scanner
            local vCoords = GetEntityCoords(v)

            -- Police Radio
            if vPoliceRadio ~= nil and GetVehicleBodyHealth(v) ~= 0 then
                -- Create Sound
                if vPoliceState == nil then
                    Sound:Create(v, "Scanner", vPoliceRadio.Link, vPoliceRadio.Volume, vCoords, vPoliceRadio.Distance)
                end
            end
        end
    end
end)

RegisterCommand("SetScanner", function(src, args, raw)
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
                Sound:SetVolume(veh, "Scanner", Volume)
                TriggerClientEvent("QBCore:Notify", src, "Set Volume to " .. Volume)
            end
        end
    end
end, false)