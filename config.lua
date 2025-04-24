-- config.lua
Config = {}

Config.DefaultVolume = 0.2       -- Default radio volume (0.0 to 1.0)
Config.DefaultDistance = 2.0     -- Default sound distance when windows are closed/intact
Config.RolledDownDistance = 10.0 -- Sound distance when windows are rolled down
Config.MaxVolume = 1.0           -- Maximum allowed volume
Config.MinVolume = 0.0           -- Minimum allowed volume (0 = off)

Config.Keybind =
'F9'                          -- Default keybind to open the radio UI (Use FiveM key names: https://docs.fivem.net/docs/game-references/controls/)

Config.EnableFavorites = true -- Set to false to disable the JSON-based favorite system

Config.NotificationSystem =
"native" -- Use "native" for built-in GTA V notifications, or specify framework (e.g., "qbcore", "esx") - requires adding framework-specific notification code in Client/Server.lua if not "native"

-- Debug setting
Config.DebugPrint = true -- Set to true to enable verbose printing for debugging

-- Function to handle notifications (adapt for your framework if not native)
function Notify(source, message)
    if Config.NotificationSystem == "native" then
        if source == -1 or source == nil then -- Client-side native notification
            SetNotificationTextEntry("STRING")
            AddTextComponentString(message)
            DrawNotification(false, true)
        else -- Server-side native notification (requires client event trigger)
            TriggerClientEvent("CRRadio:ShowNotification", source, message)
        end
    elseif Config.NotificationSystem == "qbcore" then
        -- Add QBCore notification logic here if needed
        -- TriggerClientEvent('QBCore:Notify', source, message, 'primary') -- Example
    elseif Config.NotificationSystem == "esx" then
        -- Add ESX notification logic here if needed
        -- TriggerClientEvent('esx:showNotification', source, message) -- Example
    else
        print("CRRadio: Unknown notification system configured.")
    end
end

-- Add a client event for server-to-client native notifications
if IsDuplicityVersion() then -- Server side check
    RegisterNetEvent("CRRadio:ShowNotification", function(message)
        -- This event needs to be registered on the client as well to receive the message
    end)
else -- Client side check
    RegisterNetEvent("CRRadio:ShowNotification", function(message)
        SetNotificationTextEntry("STRING")
        AddTextComponentString(message)
        DrawNotification(false, true)
    end)
end
