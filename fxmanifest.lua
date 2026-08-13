fx_version "cerulean"
game "gta5"
author "Pickle Mods#0001"
description "A multi-framework farming resource with synced growth."
version "v1.0.8"

shared_scripts {
	"@ox_lib/init.lua", -- COMMENT THIS OUT IF NOT USING OX_LIB.
	"config.lua",
	"bridge/**/shared.lua",
	"modules/**/shared.lua",
	"core/shared.lua",
	"locales/locale.lua",
	"locales/translations/*.lua"
}

client_scripts {
	"bridge/**/client.lua",
	"modules/**/client.lua",
	"core/client.lua"
}

server_scripts {
	"bridge/**/server.lua",
	"modules/**/server.lua",
	"core/server.lua"
}

lua54 'yes'
