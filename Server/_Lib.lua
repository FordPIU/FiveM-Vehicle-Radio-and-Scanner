-- Local Vars
local SoundIDs = {}
local Sounds = {}
local SoundLinks = {}
local StackedPrints = {}

-- Local Functs
local function prints(ent)
    -- Check if Exact Position is given
    for _,v in pairs(StackedPrints) do
        if v == ent then
            return
        end
    end

    -- Insert
    StackedPrints[#StackedPrints+1] = ent
end
local function print_prints()
    if #StackedPrints > 0 then
        local str = ""
        for _,e in pairs(StackedPrints) do
            str = str .. e .. ", "
        end

        --print("Updated Positions for Entities: " .. str)
    end
end
Citizen.CreateThread(function() while true do Wait(5000) print_prints() end end)

-- Source Info
SrcFuncts = {}

function SrcFuncts:GetAll(src)
    local ped = GetPlayerPed(src)
    local pednil = true
    local veh = GetVehiclePedIsIn(ped, false)
    local vehnil = true

    if ped ~= nil and ped ~= 0 and GetEntityHealth(ped) ~= 0 then
        pednil = false
    end

    if veh ~= 0 and GetVehicleBodyHealth(veh) ~= 0 then
        vehnil = false
    end

    return {ped, pednil, veh, vehnil}
end

-- Tracker
Tracker = {}

function Tracker:Add(Ent, Type, SoundID)
    -- Verify
    if Sounds[Ent] == nil then Sounds[Ent] = {} end
    -- Set
    Sounds[Ent][Type] = SoundID
end

function Tracker:Remove(Ent, Type)
    -- Verify
    if Sounds[Ent] == nil then return end
    -- Remove
    Sounds[Ent][Type] = nil
end

function Tracker:Tick()
    for Ent, Data in pairs(Sounds) do
        if not DoesEntityExist(Ent) or GetVehicleBodyHealth(Ent) == 0 then
            for Type, SoundID in pairs(Data) do
                exports.xsound:Destroy(-1, SoundID)
                SoundIDs[SoundID] = nil
                Sounds[Ent][Type] = nil
                SoundLinks[SoundID] = nil
                --print("Destroyed Sound for " .. Ent .. " because Entity no longer Exists")
            end
        else
            for _, SoundID in pairs(Data) do
                local Coords = GetEntityCoords(Ent)
                exports.xsound:Position(-1, SoundID, Coords)
                --print(Ent, Coords)
            end
        end
    end
end
Citizen.CreateThread(function() while true do Wait(0) Tracker:Tick() end end)

-- Sound
Sound = {}

function Sound:GetUID()
    local soundId = math.random(0, 999999)

    while SoundIDs[soundId] ~= nil do
        Wait(1)
        soundId = math.random(0, 999999)
    end

    SoundIDs[soundId] = true

    return tostring(soundId)
end

function Sound:Delete(Ent, Type)
    local entState = Entity(Ent).state
    local rltState = entState[Type]

    if rltState ~= nil then
        exports.xsound:Destroy(-1, rltState)

        Tracker:Remove(Ent, Type)

        --SoundIDs[rltState] = nil
        SoundLinks[rltState] = nil

        Entity(Ent).state[Type] = nil

        --print("Deleted " .. Type .. " for " .. Ent)
    end
end

function Sound:Create(Ent, Type, Link, Volume, Coords, Distance)
    local entState = Entity(Ent).state
    local rltState = entState[Type]

    if rltState == nil then
        --print("Creating Sound || " .. Type .. " || " .. Ent .. " || " .. Link .. " || " .. Volume .. " || " .. Coords .. " || " .. Distance)
        local SID = Sound:GetUID()

        exports.xsound:PlayUrlPos(-1, SID, Link, Volume, Coords, true)
        exports.xsound:Distance(-1, SID, Distance)

        SoundLinks[SID] = {Link, Volume, Distance}

        Tracker:Add(Ent, Type, SID)

        Entity(Ent).state[Type] = SID
    else
        --print("Overriding Sound, Repassing")
        Sound:Delete(Ent, Type)
        Sound:Create(Ent, Type, Link, Volume, Coords, Distance)
    end
end

function Sound:SetVolume(Ent, Type, Volume)
    local entState = Entity(Ent).state
    local rltState = entState[Type]

    if rltState ~= nil then
        exports.xsound:setVolume(-1, rltState, Volume)
    end
end



-- On Start, Delete Every Entity's Sound
Citizen.CreateThread(function()
    for _,v in pairs(GetAllVehicles()) do
        Sound:Delete(v, "Radio")
        Sound:Delete(v, "Scanner")
    end
end)


RegisterNetEvent("CR.Radio:Sync", function()
    for SoundID, Data in pairs(SoundLinks) do
        exports.xsound:Destroy(-1, SoundID)
        exports.xsound:PlayUrlPos(-1, SoundID, Data[1], Data[2], vector3(0.0, 0.0, 0.0), true)
        exports.xsound:Distance(-1, SoundID, Data[3])
    end
end)