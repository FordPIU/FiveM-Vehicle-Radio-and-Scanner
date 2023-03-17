local vehicleStates = {}

Citizen.CreateThread(function()
    Wait(10000)
    TriggerServerEvent("CR.Radio:Sync")

    while true do
        Wait(100)

        local playerPed = PlayerPedId()
        local currentVehicle = GetVehiclePedIsIn(playerPed, false)
        local lastVehicle = GetVehiclePedIsIn(playerPed, true)
        local vehicleToUpdate = nil
        local dynamicMode = nil

        if currentVehicle ~= nil and currentVehicle ~= 0 then
            vehicleToUpdate = currentVehicle
            dynamicMode = false
        elseif lastVehicle ~= nil and lastVehicle ~= 0 then
            vehicleToUpdate = lastVehicle
            dynamicMode = true
        end

        if vehicleToUpdate ~= nil then
            local entityState = Entity(vehicleToUpdate).state
            local scannerSound = entityState["Scanner"]
            local radioSound = entityState["Radio"]

            vehicleStates[vehicleToUpdate] = vehicleStates[vehicleToUpdate] or {}

            if dynamicMode ~= nil and (scannerSound or radioSound) then
                local shouldUpdate = nil

                if scannerSound ~= nil and (vehicleStates[vehicleToUpdate][2] ~= scannerSound or vehicleStates[vehicleToUpdate][1] ~= dynamicMode) then
                    Wait(1000)
                    exports.xsound:setSoundDynamic(scannerSound, dynamicMode)
                    shouldUpdate = dynamicMode
                    vehicleStates[vehicleToUpdate][2] = scannerSound
                    print("Setting Scanner to Dynamic " .. tostring(dynamicMode))
                end

                if radioSound ~= nil and (vehicleStates[vehicleToUpdate][3] ~= radioSound or vehicleStates[vehicleToUpdate][1] ~= dynamicMode) then
                    Wait(1000)
                    exports.xsound:setSoundDynamic(radioSound, dynamicMode)
                    shouldUpdate = dynamicMode
                    vehicleStates[vehicleToUpdate][3] = radioSound
                    print("Setting Radio to Dynamic " .. tostring(dynamicMode))
                end

                if shouldUpdate ~= nil then
                    vehicleStates[vehicleToUpdate][1] = shouldUpdate
                end
            end
        end
    end
end)



RegisterNetEvent("CRRadio:Notify", function(str)
    print(str)
end)