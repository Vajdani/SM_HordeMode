Player = class( nil )

local airControlImpulse = 30
local dashCooldown = 40
local dashImpulse = 2500
local armourDamageReduction = 0.75
local PoisonDamage = 10
local PoisonDamageCooldown = 40
local queuedMsgRemoveTime = 60

--Server
function Player.server_onCreate( self )
	self.sv = {}
	self.sv.stats = {
		health = 100, maxhealth = 200,
		armour = 0, maxarmour = 150,
		ammo = 100, maxammo = 1000,
	}
	self.sv.dead = false
	self.sv.statsTimer = Timer()
	self.sv.statsTimer:start( 40 )

	self.sv.poisonDamageCooldown = Timer()
	self.sv.poisonDamageCooldown:start()

	self.network:setClientData( self.sv )
	self.player:setPublicData( self.sv )
end

function Player:server_onFixedUpdate( dt )
	self.sv.poisonDamageCooldown:tick()

	self.sv.statsTimer:tick()
	if self.sv.statsTimer:done() then
		self.sv.statsTimer:start( 40 )

		self.network:setClientData( self.sv )
		self.player:setPublicData( self.sv )
	end
end

function Player:sv_applyImpulse( dir )
	sm.physics.applyImpulse(self.player.character, dir, true)
end

function Player.server_onProjectile( self, position, airTime, velocity, projectileName, attacker, damage, customData, normal, uuid )
	self:sv_takeDamage(damage, attacker)
end

function Player.server_onMelee( self, position, attacker, damage, power, direction, normal )
	self:sv_takeDamage(damage, attacker)

	if attacker then
		ApplyKnockback( self.player.character, direction, power )
	end
end

function Player.server_onExplosion( self, center, destructionLevel )
	self:sv_takeDamage(destructionLevel * 2, nil)
	if self.player.character:isTumbling() then
		local knockbackDirection = ( self.player.character.worldPosition - center ):normalize()
		ApplyKnockback( self.player.character, knockbackDirection, 5000 )
	end
end

function Player.sv_e_onStayPesticide( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function Player.sv_takeDamage( self, damage, source )
	if damage > 0 and not g_god then
		damage = damage * GetDifficultySettings().playerTakeDamageMultiplier

		local healthDamageIfTooMuchForArmour = 0
		if self.sv.stats.armour > 0 then
			self.sv.stats.armour = self.sv.stats.armour - damage * armourDamageReduction

			if self.sv.stats.armour < 0 then
				healthDamageIfTooMuchForArmour = math.abs(self.sv.stats.armour)
				self.sv.stats.armour = 0
			end
		else
			self.sv.stats.health = math.max( self.sv.stats.health - damage, 0 )
		end

		self.sv.stats.health = math.max( self.sv.stats.health - healthDamageIfTooMuchForArmour, 0 )

		print( "Player took damage:", damage)

		--self.player:sendCharacterEvent( "hit" )

		if self.sv.stats.health <= 0 then
			self.player.character:setTumbling( true )
			self.player.character:setDowned( true )
			self.sv.dead = true
		end

		self.network:setClientData( self.sv )
		self.player:setPublicData( self.sv )
	end
end

function Player:sv_restorehealth( amount )
	local prevHealth = self.sv.stats.health
	self.sv.stats.health = sm.util.clamp(self.sv.stats.health + amount, 0, self.sv.stats.maxhealth)

	local restored = self.sv.stats.health - prevHealth
	--self.network:sendToClient(self.player, "cl_displayMsg", { msg = "#"..g_pickupColours.health:getHexStr():sub(1,6).."Restored "..tostring(restored).." health", dur = 2.5 } )
	self.network:sendToClient(self.player, "cl_queueMsg", "#"..g_pickupColours.health:getHexStr():sub(1,6).."Restored "..tostring(restored).." health")
	self.network:setClientData( self.sv )
end

function Player:sv_restorearmour( amount )
	local prevArmour = self.sv.stats.armour
	self.sv.stats.armour = sm.util.clamp(self.sv.stats.armour + amount, 0, self.sv.stats.maxarmour)

	local restored = self.sv.stats.armour - prevArmour
	--self.network:sendToClient(self.player, "cl_displayMsg", { msg = "#"..g_pickupColours.armour:getHexStr():sub(1,6).."Restored "..tostring(restored).." armour", dur = 2.5 } )
	self.network:sendToClient(self.player, "cl_queueMsg", "#"..g_pickupColours.armour:getHexStr():sub(1,6).."Restored "..tostring(restored).." armour" )
	self.network:setClientData( self.sv )
end

function Player:sv_restoreammo( amount )
	local container = self.player:getInventory()
	sm.container.beginTransaction()
	local potatoes = sm.container.totalQuantity( container, obj_plantables_potato )
	local tocollect = potatoes + amount > self.sv.stats.maxammo and amount - (potatoes + amount - self.sv.stats.maxammo) or amount
	sm.container.collect( container, obj_plantables_potato, tocollect )
	sm.container.endTransaction()

	--self.network:sendToClient(self.player, "cl_displayMsg", { msg = "#"..g_pickupColours.ammo:getHexStr():sub(1,6).."Picked up "..tostring(tocollect).." ammunition", dur = 2.5 } )
	self.network:sendToClient(self.player, "cl_queueMsg", "#"..g_pickupColours.ammo:getHexStr():sub(1,6).."Picked up "..tostring(tocollect).." ammunition" )
	self.network:setClientData( self.sv )
end

function Player:sv_resetPlayer()
	self.sv.stats = {
		health = 100, maxhealth = 200,
		armour = 0, maxarmour = 150,
		ammo = 100, maxammo = 1000,
	}

	local container = self.player:getInventory()
	sm.container.beginTransaction()
    for i = 1, container:getSize() do
        local item = container:getItem( i - 1 )
	    if item.uuid ~= sm.uuid.getNil() then
            sm.container.spend( container, item.uuid, item.quantity )
        end
    end

	sm.container.collect( container, g_spudgun, 1 )
	sm.container.collect( container, g_shotgun, 1 )
	sm.container.collect( container, obj_plantables_potato, 100 )
	sm.container.endTransaction()

	local newChar = sm.character.createCharacter(self.player, self.player.character:getWorld(), sm.vec3.new(0,0,10))
	self.player:setCharacter(newChar)
	self.player.character:setMovementSpeedFraction( 1 )
end

function Player:sv_queueMsg(msg)
	self.network:sendToClient(self.player, "cl_queueMsg", msg)
end

function Player:sv_displayMsg( args )
	self.network:sendToClient(self.player, "cl_displayMsg", args)
end

function Player:sv_chatMsg(msg)
	self.network:sendToClient(self.player, "cl_chatMsg", msg)
end

function Player:sv_toggleAirControl()
	self.network:sendToClient(self.player, "cl_toggleAirControl")
end

function Player:sv_respawn( sendToClients )
	if not self.sv.dead then return end

	local everyoneDied = true
    for v, k in pairs(sm.player.getAllPlayers()) do
        if sm.exists(k.character) and not k.character:isDowned() then
            everyoneDied = false
        end
    end

	local char = self.player:getCharacter()
	if #sm.player.getAllPlayers() == 1 or sm.isHost and everyoneDied then
		local world = char:getWorld()
		sm.event.sendToWorld( world, "sv_resetWaves" )

		if sendToClients then
			for v, k in pairs(sm.player.getAllPlayers()) do
				if k.id ~= self.player.id then
					sm.event.sendToPlayer(k, "sv_respawn", false)
				end
			end

			self.network:sendToClients("cl_fade", 80)
		end

		self.sv.dead = false
		self.sv.stats = {
			health = 100, maxhealth = 200,
			armour = 0, maxarmour = 100,
			ammo = 100, maxammo = 1000,
		}

		self.network:setClientData( self.sv )
		self.player:setPublicData( self.sv )
		self:sv_displayMsg( { msg = "Restarted!", dur = 2.5 } )
	else
		local container = self.player:getInventory()
		sm.container.beginTransaction()
		for i = 1, container:getSize() do
			container:setItem( i-1, sm.uuid.getNil(), -1 )
		end
		sm.container.endTransaction()

		char:setTumbling( false )
		char:setSwimming( true )
		char:setDiving( true )
		char:setMovementSpeedFraction( 2.5 )
		self.sv.dead = false
		self:sv_displayMsg( { msg = "Entered #df7f00Spectator Mode#ffffff!", dur = 2.5 } )
	end
end

function Player.server_onShapeRemoved( self, items )

end

--Client
function Player:client_onCreate()
	local player = sm.localPlayer.getPlayer()
	if player ~= self.player then return end

	self.cl = {}
	self.cl.data = nil

	self.cl.survivalHud = sm.gui.createSurvivalHudGui()
	self.cl.survivalHud:setVisible("WaterBar", false)
	--self.cl.survivalHud:setImage("FoodIcon", )
	self.cl.survivalHud:open()

	self.cl.extraHud = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/extraHud.layout", false,
		{
			isHud = true,
			isInteractive = false,
			needsCursor = false
		}
	)
	self.cl.extraHud:setIconImage( "ammoIcon", obj_plantables_potato)
	self.cl.extraHud:open()

	self.cl.airControl = true

	self.cl.dash = {
		useCD = {
			active = false,
			count = dashCooldown
		},
		hasTriggered = false
	}

	self.cl.queuedMsgs = {}
	self.cl.queuedMsgRemoveTimer = Timer()
	self.cl.queuedMsgRemoveTimer:start(queuedMsgRemoveTime)

	player:setClientPublicData(
		{
			weaponMod = {

			},
			input = {
				[sm.interactable.actions.forward] = false,
                [sm.interactable.actions.backward] = false,
                [sm.interactable.actions.left] = false,
                [sm.interactable.actions.right] = false,
				[sm.interactable.actions.jump] = false,
                [sm.interactable.actions.use] = false,
			},
			meathookState = false
		}
	)
end

function Player.client_onClientDataUpdate( self, data )
	if sm.localPlayer.getPlayer() ~= self.player then return end

	self.cl.data = data

	if data.dead then
		sm.camera.setCameraState( sm.camera.state.forcedTP )
	elseif sm.camera.getCameraState() == sm.camera.state.forcedTP then
		sm.camera.setCameraState( sm.camera.state.default )
	end

	self.cl.survivalHud:setSliderData( "Health", data.stats.maxhealth * 10 + 1, data.stats.health * 10 )
	self.cl.survivalHud:setSliderData( "Food", data.stats.maxarmour * 10 + 1, data.stats.armour * 10 )
end

function Player:client_onFixedUpdate( dt )
	local player = sm.localPlayer.getPlayer()
	if player ~= self.player then return end

	if #self.cl.queuedMsgs > 0 then
		self.cl.queuedMsgRemoveTimer:tick()

		if self.cl.queuedMsgRemoveTimer:done() then
			local new = {}
			for i = 2, #self.cl.queuedMsgs  do
				new[i-1] = self.cl.queuedMsgs[i]
			end
			self.cl.queuedMsgs = new
			self.cl.queuedMsgRemoveTimer:start(queuedMsgRemoveTime)
		end

		local message = ""
		for i = sm.util.clamp(#self.cl.queuedMsgs-1, 1, 10000), #self.cl.queuedMsgs do
			message = message..self.cl.queuedMsgs[i].."\n"
		end
		self:cl_displayMsg( { msg = message, dur = 2.5 } )
	end

	local clientData = self.player:getClientPublicData()
	if clientData.weaponMod.name == nil then return end

	local weaponModName = "#df7f00"..clientData.weaponMod.name --"#"..clientData.weaponMod.colour:getHexStr():sub(1,6)..clientData.weaponMod.name
	self.cl.extraHud:setText("weaponMod", weaponModName)


	--movement
	if self.cl.dash.useCD.active then
		self.cl.dash.useCD.count = self.cl.dash.useCD.count - 1
		if self.cl.dash.useCD.count <= 0 then
			self.cl.dash.useCD.count = dashCooldown
			self.cl.dash.useCD.active = false
		end
	end

	local char = player.character
	if char == nil then return end

	local moveDir = self:cl_getMoveDir( char )
	if moveDir == sm.vec3.zero() then return end

	if self.cl.airControl then
		if not char:isOnGround() and char:getVelocity():length2() < 64 then
			self.network:sendToServer("sv_applyImpulse", moveDir * airControlImpulse)
		end
	end

	if char:isCrouching() and not self.cl.dash.hasTriggered and not self.cl.dash.useCD.active then
		self.network:sendToServer("sv_applyImpulse", moveDir * dashImpulse)
		self.cl.dash.hasTriggered = true
		self.cl.dash.useCD.active = true
	elseif not char:isCrouching() then
		self.cl.dash.hasTriggered = false
	end
end

function Player:client_onUpdate()
	if sm.localPlayer.getPlayer() ~= self.player then return end

	if sm.camera.getCameraState() == sm.camera.state.forcedTP then
		local keyBindingText =  sm.gui.getKeyBinding( "Use", true )

		local option = #sm.player.getAllPlayers() == 1 and "Restart from the beginning" or "Spectate"
		sm.gui.setInteractionText( "", keyBindingText, option)
	end

	local container = sm.localPlayer.getInventory()
	self.cl.extraHud:setText("ammoAmount", "#df7f00"..tostring(sm.container.totalQuantity( container, obj_plantables_potato )).." #ffffff/ "..tostring(self.cl.data.stats.maxammo) )
end

function Player:cl_getMoveDir( char )
	local moveDir = sm.vec3.zero()

	local dir = char:getDirection()
	local camUp = dir:rotate(math.rad(90), dir:cross(g_up))

	local left = camUp:cross(dir)
	local right = left * -1
	local fwd = g_up:cross(right)
	local bwd = fwd * -1

	local moveDirs = {
		{ id = sm.interactable.actions.forward, dir = fwd },
		{ id = sm.interactable.actions.backward, dir = bwd },
		{ id = sm.interactable.actions.left, dir = left },
		{ id = sm.interactable.actions.right, dir = right },
	}

	local publicData = sm.localPlayer.getPlayer():getClientPublicData()
	for v, k in pairs(moveDirs) do
		if publicData.input[k.id] then
			moveDir = moveDir + k.dir
		end
	end

	return moveDir
end

function Player:cl_toggleAirControl()
	self.cl.airControl = not self.cl.airControl
	self:cl_queueMsg("Air Control: #df7f00"..(self.cl.airControl and "ON" or "OFF"))
end

function Player:cl_vis( dir )
	sm.particle.createParticle("paint_smoke", self.player:getCharacter():getWorldPosition() + dir)
end

function Player:cl_queueMsg(msg)
	table.insert(self.cl.queuedMsgs, msg)
	self.cl.queuedMsgRemoveTimer:reset()
end

function Player:cl_displayMsg( args )
	sm.gui.displayAlertText(args.msg, args.dur)
end

function Player:cl_chatMsg(msg)
	sm.gui.chatMessage( msg )
end

function Player:client_onInteract( char, state )
	if state then
		self.network:sendToServer("sv_respawn", true)
	end
end

function Player:cl_fade( dur )
	sm.gui.startFadeToBlack( dur, 0 )
end