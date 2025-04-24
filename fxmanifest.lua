-- fxmanifest.lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Caleb B.'
description 'Vehicle Radio with UI and Realism Features'
version '2.0.0'

-- UI File
ui_page 'html/ui.html'

-- Shared Scripts
shared_script 'config.lua'

-- Server Scripts
server_scripts {
    'Server/Lib.lua',
    'Server/Server.lua'
}

-- Client Scripts
client_scripts {
    'Client/Client.lua'
}

-- NUI Related Files
files {
    'html/ui.html',
    'html/style.css',
    'html/script.js',
    'Favorites/*.json'
}

-- Dependencies
dependencies {
    'xsound'
}
