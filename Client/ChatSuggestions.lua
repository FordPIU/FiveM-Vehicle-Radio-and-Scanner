TriggerEvent("chat:addSuggestion", "/PlayRadio", "Play In-car Radio", {
    { name = "Link", help = "Link to the radio station" },
    { name = "Volume", help = "Volume of the radio station (Between 0.0 and 1.0)" }
})

TriggerEvent("chat:addSuggestion", "/SetRadio", "Set In-car Radio Variables", {
    { name = "Command", help = "Command to set the radio station, Example: Volume" },
    { name = "Value", help = "Value of the command" }
})

TriggerEvent("chat:addSuggestion", "/StopRadio", "Stop In-car Radio")

TriggerEvent("chat:addSuggestion", "/SetScanner", "Set In-car Scanner Variables", {
    { name = "Command", help = "Command to set the radio station, Example: Volume" },
    { name = "Value", help = "Value of the command" }
})

TriggerEvent("chat:addSuggestion", "/FavoriteRadio", "Add Favorite In-car Radio Stations", {
    { name = "URL", help = "URL of the radio station" },
    { name = "ID", help = "ID of the radio station" }
})

TriggerEvent("chat:addSuggestion", "/FavoritesPrint", "Print your Favorite Stations to the Console")