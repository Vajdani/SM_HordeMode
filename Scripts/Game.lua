Game = class( nil )
Game.enableLimitedInventory = true
Game.enableRestrictions = true
Game.enableFuelConsumption = true
Game.enableAmmoConsumption = true
Game.enableUpgrade = true

dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )

g_disableScrapHarvest = true
g_god = false
g_pvp = false
g_up = sm.vec3.new(0,0,1)
---@type Shape[]
g_coins = {}
g_spudgun = sm.uuid.new("c5ea0c2f-185b-48d6-b4df-45c386a575cc")
g_shotgun = sm.uuid.new("f6250bf4-9726-406f-a29a-945c06e460e5")
g_gatling = sm.uuid.new("9fde0601-c2ba-4c70-8d5c-2a7a9fdd122b")
g_hammer = sm.uuid.new("bb641a4f-e391-441c-bc6d-0ae21a069476")

function Game.server_onCreate( self )
	print("Game.server_onCreate")

	g_arenaData = sm.json.open("$CONTENT_DATA/Scripts/arenas.json")
    g_currentArena = sm.storage.load( "CURRENTARENA" ) or 1

	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.world = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "World" )
		self.sv.saved.world:setTerrainScriptData( { path = g_arenaData[g_currentArena].path } )
		self.storage:save( self.sv.saved )
	end

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate( self.sv.saved.overworld )

	self.network:sendToClients("cl_bindCommands")
end

function Game:cl_bindCommands()
	if sm.isHost then
		sm.game.bindChatCommand( "/god", {}, "cl_onChatCommand", "Mechanic characters will take no damage" )
		sm.game.bindChatCommand( "/start", {}, "cl_onChatCommand", "start waves" )
		sm.game.bindChatCommand( "/stop", {}, "cl_onChatCommand", "stop waves" )
		sm.game.bindChatCommand( "/restart", {}, "cl_onChatCommand", "Restarts waves" )
		sm.game.bindChatCommand( "/inv", {}, "cl_onChatCommand", "Toggle limited inv" )
		sm.game.bindChatCommand( "/pvp", {}, "cl_onChatCommand", "Toggle pvp" )
		sm.game.bindChatCommand( "/goto",
			{
				{
					"int",
					"wave",
					true
				}
			},
			"cl_onChatCommand",
			"go to specified wave"
		)
		sm.game.bindChatCommand( "/arena",
			{
				{
					"int",
					"wave",
					true
				}
			},
			"cl_onChatCommand",
			"load into another arena"
		)
		sm.game.bindChatCommand( "/aggro", {}, "cl_onChatCommand", "Toggle bot aggro" )
	end

	sm.game.bindChatCommand( "/aircontrol", {}, "cl_onChatCommand", "Toggle air control(more effective movement in the air)" )
	sm.game.bindChatCommand( "/movement", {}, "cl_onChatCommand", "Toggle advanced movement(dashing, etc)" )
end

function Game:cl_onChatCommand( params )
	local player = sm.localPlayer.getPlayer()
	local commandName = params[1]
	if commandName == "/god" then
		self.network:sendToServer( "sv_switchGodMode" )
	elseif commandName == "/start" then
		self.network:sendToServer( "sv_startWaves" )
	elseif commandName == "/stop" then
		self.network:sendToServer( "sv_stopWaves" )
	elseif commandName == "/restart" then
		self.network:sendToServer( "sv_restartWaves" )
	elseif commandName == "/inv" then
		self.network:sendToServer( "sv_toggleInv" )
	elseif commandName == "/pvp" then
		self.network:sendToServer( "sv_togglePvp" )
	elseif commandName == "/goto" then
		if g_waves == nil or #g_waves == 0 then
			sm.gui.displayAlertText("#df7f00Start the waves first!", 5)
			return
		end

		if params[2] <= #g_waves and params[2] > 0 then
			self.network:sendToServer( "sv_gotoWave", params[2] )
		else
			sm.gui.displayAlertText("#df7f00Invalid wave number specified! It must be between #ffffff1 #df7f00and #ffffff"..tostring(#g_waves), 5)
		end
	elseif commandName == "/arena" then
		print(#g_arenaData)
		if g_arenaData == nil or #g_arenaData == 0 then
			return
		end

		if params[2] <= #g_arenaData and params[2] > 0 then
			self.network:sendToServer( "sv_changeArenaTo", params[2] )
		else
			sm.gui.displayAlertText("#df7f00Invalid arena index specified! It must be between #ffffff1 #df7f00and #ffffff"..tostring(#g_arenaData), 5)
		end
	elseif commandName == "/aggro" then
		self.network:sendToServer( "sv_toggleAggro" )
	elseif commandName == "/aircontrol" then
		self.network:sendToServer( "sv_toggleAirControl", player )
	elseif commandName == "/movement" then
		self.network:sendToServer( "sv_toggleMovement", player )
	end
end

function Game:sv_switchGodMode()
	g_god = not g_god

	local mode = g_god and "ON" or "OFF"
	for v, k in pairs(sm.player.getAllPlayers()) do
		sm.event.sendToPlayer(k, "sv_chatMsg", "God mode is now #df7f00"..mode)
	end
end

function Game:sv_startWaves()
	sm.event.sendToWorld( self.sv.saved.world, "sv_startWaves" )
end

function Game:sv_stopWaves()
	sm.event.sendToWorld( self.sv.saved.world, "sv_stopWaves" )
end

function Game:sv_restartWaves()
	sm.event.sendToWorld( self.sv.saved.world, "sv_resetWaves" )
end

function Game:sv_toggleInv()
	sm.game.setLimitedInventory( not sm.game.getLimitedInventory() )

	local mode = sm.game.getLimitedInventory() and "ON" or "OFF"
	for v, k in pairs(sm.player.getAllPlayers()) do
		sm.event.sendToPlayer(k, "sv_chatMsg", "Limited inventory mode is now #df7f00"..mode)
	end
end

function Game:sv_togglePvp()
	g_pvp = not g_pvp

	local mode = g_pvp and "ON" or "OFF"
	for v, k in pairs(sm.player.getAllPlayers()) do
		sm.event.sendToPlayer(k, "sv_chatMsg", "PVP is now #df7f00"..mode)
	end
end

function Game:sv_gotoWave( wave )
	sm.event.sendToWorld( self.sv.saved.world, "sv_gotoWave", wave )
end

function Game:sv_toggleAggro()
	local aggro = not sm.game.getEnableAggro()
	sm.game.setEnableAggro( aggro )

	local mode = aggro and "ON" or "OFF"
	for v, k in pairs(sm.player.getAllPlayers()) do
		sm.event.sendToPlayer(k, "sv_chatMsg", "Aggro is now #df7f00"..mode)
	end
end

function Game:sv_toggleAirControl( player )
	sm.event.sendToPlayer(player, "sv_toggleAirControl")
end

function Game:sv_toggleMovement( player )
	if not g_inputManager then return end
	sm.event.sendToInteractable(g_inputManager, "sv_manageIgnoredPlayer", player)
end

function Game.server_onPlayerJoined( self, player, isNewPlayer )
	print("Game.server_onPlayerJoined")

	if isNewPlayer then
        if not sm.exists( self.sv.saved.world ) then
            sm.world.loadWorld( self.sv.saved.world )
        end
        self.sv.saved.world:loadCell( 0, 0, player, "sv_createPlayerCharacter" )
    end

	local container = player:getInventory()
	sm.container.beginTransaction()
	sm.container.spend( container, obj_plantables_potato, sm.container.totalQuantity( container, obj_plantables_potato ) )
	sm.container.spend( container, g_hammer, sm.container.totalQuantity( container, g_hammer ) )
	sm.container.spend( container, g_spudgun, sm.container.totalQuantity( container, g_spudgun ) )
	sm.container.spend( container, g_shotgun, sm.container.totalQuantity( container, g_shotgun ) )
	sm.container.spend( container, g_gatling, sm.container.totalQuantity( container, g_gatling ) )

	sm.container.collect( container, g_hammer, 1 )
	sm.container.collect( container, g_spudgun, 1 )
	sm.container.collect( container, g_shotgun, 1 )
	sm.container.collect( container, g_gatling, 1 )
	sm.container.collect( container, obj_plantables_potato, 100 )
	sm.container.endTransaction()

	if #sm.player.getAllPlayers() == 1 then
		sm.gui.chatMessage("Type #df7f00/start #ffffffin chat to start the game!")
	end

	g_unitManager:sv_onPlayerJoined( player )
end

function Game:sv_onPlayerDeath()
	sm.event.sendToWorld(self.sv.saved.world, "sv_onPlayerDeath")
end

function Game.sv_createPlayerCharacter( self, world, x, y, player, params )
	local character = sm.character.createCharacter( player, world, sm.vec3.new( 0, 0, 5 ), 0, 0 )
	player:setCharacter( character )

	--sm.event.sendToWorld(self.sv.saved.world, "sv_resetPlayerInv", player)
end

function Game:sv_changeArenaTo( index )
	g_currentArena = index
	sm.storage.save( "CURRENTARENA", g_currentArena )

	--thanks MrCrackx for the kewl coed
	local newWorld = sm.world.createWorld( "$CONTENT_DATA/Scripts/World.lua", "World" )
	local arena = g_arenaData[g_currentArena]
	newWorld:setTerrainScriptData( { path = arena.path } )

	if not sm.exists( newWorld ) then
		sm.world.loadWorld( newWorld )
	end

	for k, player in pairs( sm.player.getAllPlayers() ) do
		local playerChar = player:getCharacter()
		if sm.exists( playerChar ) then
			local newChar = sm.character.createCharacter( player, newWorld, sm.vec3.new( 32, 32, 5 ) )
			player:setCharacter( nil )
			player:setCharacter( newChar )
		end
	end

	self.sv.saved.world:destroy()
	self.sv.saved.world = newWorld

	self.storage:save( self.sv.saved )

	sm.event.sendToWorld( self.sv.saved.world, "sv_resetWaves" )
end

function Game:server_onFixedUpdate( dt )
	g_unitManager:sv_onFixedUpdate()

	for v, k in ipairs(g_coins) do
		if not sm.exists(k) then
			table.remove(g_coins, v)
		end
	end
end

function Game:client_onCreate()
	if g_unitManager == nil then
		assert( not sm.isHost )
		g_unitManager = UnitManager()
	end
	g_unitManager:cl_onCreate()
end