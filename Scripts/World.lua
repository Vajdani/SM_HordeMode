World = class( nil )
World.terrainScript = "$CONTENT_DATA/Scripts/terrain.lua"
World.cellMinX = -1
World.cellMaxX =  1
World.cellMinY = -1
World.cellMaxY =  1
World.worldBorder = true

dofile( "$SURVIVAL_DATA/Scripts/game/managers/PesticideManager.lua" )

g_potatoProjectiles = {
    projectile_potato,
    projectile_fries,
    projectile_smallpotato
}

local pickupSize = sm.vec3.one() / 2
g_pickupColours = {
    health = sm.color.new(0,0.5,1),
    armour = sm.color.new(0,1,0),
	ammo = sm.color.new(1,1,0)
}

local waveCountDown = 200
local mapBounds = {
    { -20, 20 },
    { -20, 20 }
}
local minWaves = 12
local maxWaves = 20
local spawnChanceIncrease = 0.01

local totebotWavesStart = 1
local totebotPerWave = 2
local totebotChance = 0.8

local haybotWavesStart = 3
local haybotPerWave = 2
local haybotChance = 0.6

local tapebotWavesStart = 6
local tapebotPerWave = 1
local tapebotChance = 0.3

local farmbotWavesStart = 9
local farmbotPerWave = 0.5
local farmbotChance = 0.1

function World.server_onCreate( self )
    print("World.server_onCreate")

    self.sv = {}
    g_pesticideManager = PesticideManager()
	g_pesticideManager:sv_onCreate()

    self.sv.arenaData = sm.json.open("$CONTENT_DATA/Scripts/arenas.json").arenaList
    self.sv.currentArena = 1

	self.sv.pickups = {}

    self.sv.currentWave = 0
    self.sv.waveCountDown = waveCountDown
    self.sv.unitsInCurrentWave = {}
    self.sv.hasSentCompleteMessage = false
    self.sv.progressWaves = false
    self.sv.sendDeadMessage = true


    local manager = sm.storage.load( "INPUTMANAGER" )
    if manager == nil then
        manager = sm.shape.createPart( sm.uuid.new("8d3c62be-852d-475e-a8d1-f9cacf88cbf9"), sm.vec3.new(0,0,1000), sm.quat.identity(), false, true ):getInteractable()
        sm.storage.save( "INPUTMANAGER", manager )
    end

    g_inputManager = manager
end

function World:server_onFixedUpdate( dt )
    g_pesticideManager:sv_onWorldFixedUpdate( self )

	if not self.sv.progressWaves then return end

    self:sv_handleWaves()

    local everyoneDied = true
    for v, k in pairs(sm.player.getAllPlayers()) do
        if sm.exists(k.character) and not k.character:isDowned() then
            everyoneDied = false
        end
    end

    if everyoneDied and self.sv.sendDeadMessage then
        self.sv.sendDeadMessage = false
        for v, k in pairs(sm.player.getAllPlayers()) do
            sm.event.sendToPlayer(k, "sv_queueMsg", "#ffffffEveryone is dead! #df7f00Game over. #ffffffYou survived for #df7f00"..tostring(self.sv.currentWave).." #ffffffwaves out of #df7f00"..tostring(#g_waves))
        end
        self.sv.progressWaves = false
    end

    if self.sv.pickups == nil or #self.sv.pickups == 0 then return end
    for v, k in pairs(self.sv.pickups) do
        if not k.active and k.remainingUses > 0 then
            k.cd = k.cd - 1
            if k.cd <= 0 then
                k.active = true
                k.cd = k.respawnTime
                self.network:sendToClients("cl_managePickupEffect", { id = v, active = k.active, pos = k.pos })
            end
        end
    end
end

function World:sv_pickup_onPickup( trigger, result )
    local pickupData = {}
    local index = 0
    for v, k in pairs(self.sv.pickups) do
        if k.trigger == trigger then
            pickupData = k
            index = v
            break
        end
    end

    if not pickupData.active or pickupData.remainingUses == 0 then return end

    local playersEntered = 0
    for v, k in pairs(result) do
        if sm.exists(k) then
            local player = k:getPlayer()
            if player ~= nil and not player.character:isDowned() and not player.character:isSwimming() and not player.character:isDiving() then
                local publicData = player:getPublicData()
                local compare = pickupData.type == "ammo" and sm.container.totalQuantity( player:getInventory(), obj_plantables_potato ) or publicData.stats[pickupData.type]
                if compare < publicData.stats["max"..pickupData.type] then
                    sm.event.sendToPlayer(player, "sv_restore"..pickupData.type, pickupData.amount)
                    playersEntered = playersEntered + 1
                end
            end
        end
    end

    if playersEntered > 0 then
        pickupData.active = false
        pickupData.remainingUses = pickupData.remainingUses - 1
        self.network:sendToClients("cl_managePickupEffect", { id = index, active = pickupData.active, pos = pickupData.pos })
    end
end

function World:sv_createPickups()
    local pickups = self.sv.arenaData[self.sv.currentArena].pickups

    local dataToSend = {}
    for v, k in pairs(pickups) do
        local pickup = k
        pickup.pos = sm.vec3.new(pickup.pos.x, pickup.pos.y, pickup.pos.z)
        pickup.trigger = sm.areaTrigger.createBox( pickupSize, pickup.pos, sm.quat.identity(), sm.areaTrigger.filter.character )
        pickup.trigger:bindOnStay( "sv_pickup_onPickup" )
        pickup.active = true
        pickup.cd = k.respawnTime
        pickup.remainingUses = pickup.maxUses
        self.sv.pickups[#self.sv.pickups+1] = pickup

		dataToSend[#dataToSend+1] = { pos = pickup.pos, type = pickup.type }
    end

    self.network:sendToClients("cl_createPickups", dataToSend)
end

function World:sv_resetPickups()
    for v, k in pairs(self.sv.pickups) do
        k.active = true
        k.remainingUses = k.maxUses

        self.network:sendToClients("cl_managePickupEffect", { id = v, active = k.active, pos = k.pos })
    end
end

function World:sv_deletePickups()
    for v, k in pairs(self.sv.pickups) do
        self.sv.pickups[v] = nil

        self.network:sendToClients("cl_managePickupEffect", { id = v, active = false, delete = true })
    end
end

function World:sv_generateWaves()
    g_waves = {}
    for i = 1, math.random(minWaves, maxWaves) do
        local possibleEnemies = {}

        if i >= totebotWavesStart then
            for j = 1, math.floor(totebotPerWave * (i / 2)) do
                if math.random() < totebotChance then
                    possibleEnemies[#possibleEnemies+1] = unit_totebot_green
                end
            end
        end

        if i >= haybotWavesStart then
            for j = 1, math.floor(haybotPerWave * (i / 2)) do
                if math.random() < haybotChance then
                    possibleEnemies[#possibleEnemies+1] = unit_haybot
                end
            end
        end

        if i >= tapebotWavesStart then
            for j = 1, math.floor(tapebotPerWave * (i / 2)) do
                if math.random() < tapebotChance + spawnChanceIncrease * i then
                    possibleEnemies[#possibleEnemies+1] = unit_tapebot
                end
            end
        end

        if i >= farmbotWavesStart then
            for j = 1, math.floor(farmbotPerWave * (i / 2)) do
                if math.random() < farmbotChance + spawnChanceIncrease * i then
                    possibleEnemies[#possibleEnemies+1] = unit_farmbot
                end
            end
        end


        local wave = {}
        for j = 1, #possibleEnemies do
            wave[#wave+1] = { unit = possibleEnemies[j], pos = function () return sm.vec3.new(math.random(mapBounds[1][1],mapBounds[1][2]),math.random(mapBounds[2][1],mapBounds[2][2]),0) end }
        end

        g_waves[#g_waves+1] = wave
    end
end

function World:sv_yeetBots()
    for v, k in pairs(sm.unit.getAllUnits()) do
        k:destroy()
    end
end

function World:sv_handleWaves()
    local remainingUnits = {}
    for v, k in pairs(self.sv.unitsInCurrentWave) do
        if sm.exists(k) then
            remainingUnits[#remainingUnits+1] = k
        end
    end

    if self.sv.currentWave == #g_waves and #remainingUnits == 0 then
        if not self.sv.hasSentCompleteMessage then
            for v, k in pairs(sm.player.getAllPlayers()) do
                sm.event.sendToPlayer(k, "sv_queueMsg", "#df7f00Congratulations! You survived all waves.")
            end
        end
        self.sv.hasSentCompleteMessage = true
        self.sv.progressWaves = false

        return
    end

    if #remainingUnits == 0 then
        self.sv.waveCountDown = self.sv.waveCountDown - 1
        if self.sv.waveCountDown <= 0 then
            self.sv.waveCountDown = waveCountDown

            if self.sv.currentWave < #g_waves then
                self.sv.currentWave = self.sv.currentWave + 1

                self.sv.unitsInCurrentWave = {}
                local hostPos = sm.player.getAllPlayers()[1].character:getWorldPosition()
                for v, k in pairs(g_waves[self.sv.currentWave]) do
                    local pos = type(k.pos) == "function" and k.pos() or k.pos
                    local dir = hostPos - pos
                    self.sv.unitsInCurrentWave[#self.sv.unitsInCurrentWave+1] = sm.unit.createUnit( k.unit, pos, math.atan2( dir.y, dir.x ) - math.pi / 2 )
                end

                local bewareMsg = ""
                if self.sv.currentWave == tapebotWavesStart then
                    bewareMsg = "#0044ccBeware of tapebots!"
                elseif self.sv.currentWave == farmbotWavesStart then
                    bewareMsg = "#dd0000Beware of farmbots!"
                end

                for v, k in pairs(sm.player.getAllPlayers()) do
                    sm.event.sendToPlayer(k, "sv_queueMsg", "#ffffffWAVE #df7f00"..tostring(self.sv.currentWave).."#ffffff/#df7f00"..tostring(#g_waves).."\t"..bewareMsg)
                end
                self:sv_resetPickups()
            end
        end
    end
end

function World:sv_startWaves()
    if not self.sv.progressWaves and self.sv.currentWave == 0 then
        self.sv.progressWaves = true --not self.sv.progressWaves
        for v, k in pairs(sm.player.getAllPlayers()) do
            sm.event.sendToPlayer(k, "sv_queueMsg", "#df7f00Let the waves begin!")
        end

        self:sv_generateWaves()
        self:sv_createPickups()
    else
        for v, k in pairs(sm.player.getAllPlayers()) do
            sm.event.sendToPlayer(k, "sv_queueMsg", "Use #df7f00/restart #ffffffto restart the waves!")
        end
    end
end

function World:sv_resetWaves()
    self.sv.currentWave = 0
    self.sv.waveCountDown = waveCountDown
    self.sv.hasSentCompleteMessage = false
    self.sv.progressWaves = false
    self.sv.sendDeadMessage = true

    for v, k in pairs(sm.player.getAllPlayers()) do
        sm.event.sendToPlayer(k, "sv_resetPlayer")
    end

    self:sv_yeetBots()
    self:sv_deletePickups()
    self:sv_startWaves()
end

function World.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, target, projectileUuid )
	-- Notify units about projectile hit
	if isAnyOf( projectileUuid, g_potatoProjectiles ) then
		local units = sm.unit.getAllUnits()
		for i, unit in ipairs( units ) do
			if InSameWorld( self.world, unit ) then
				sm.event.sendToUnit( unit, "sv_e_worldEvent", { eventName = "projectileHit", hitPos = hitPos, hitTime = hitTime, hitVelocity = hitVelocity, attacker = attacker, damage = damage })
			end
		end
	end

	if projectileUuid == projectile_pesticide then
		local forward = sm.vec3.new( 0, 1, 0 )
		local randomDir = forward:rotateZ( math.random( 0, 359 ) )
		local effectPos = hitPos
		local success, result = sm.physics.raycast( hitPos + sm.vec3.new( 0, 0, 0.1 ), hitPos - sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 ), nil, sm.physics.filter.static + sm.physics.filter.dynamicBody )
		if success then
			effectPos = result.pointWorld + sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.5 )
		end
		g_pesticideManager:sv_addPesticide( self, effectPos, sm.vec3.getRotation( forward, randomDir ) )
	end

	if projectileUuid == projectile_glowstick then
		sm.harvestable.createHarvestable( hvs_remains_glowstick, hitPos, sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), hitVelocity:normalize() ) )
	end

	if projectileUuid == projectile_explosivetape or projectileUuid == sm.uuid.new("2abc4c0c-dd91-48be-96a6-4d69bc5d8276") then
		sm.physics.explode( hitPos, 7, 2.0, 6.0, 25.0, "RedTapeBot - ExplosivesHit" )
	end
end

function World:server_onProjectileFire( self, firePos, fireVelocity, _, attacker, projectileUuid )
	if isAnyOf( projectileUuid, g_potatoProjectiles ) then
		local units = sm.unit.getAllUnits()
		for i, unit in ipairs( units ) do
			if InSameWorld( self.world, unit ) then
				sm.event.sendToUnit( unit, "sv_e_worldEvent", { eventName = "projectileFire", firePos = firePos, fireVelocity = fireVelocity, projectileUuid = projectileUuid, attacker = attacker })
			end
		end
	end
end

function World:client_onCreate()
    self.cl = {}

    if g_pesticideManager == nil then
		assert( not sm.isHost )
		g_pesticideManager = PesticideManager()
	end
	g_pesticideManager:cl_onCreate()

	self.cl.pickups = {}
	self.cl.hitscanEffects = {}
end

function World:cl_createPickups( data )
    for v, k in pairs(data) do
        local pickup = sm.effect.createEffect("ShapeRenderable")
        pickup:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
        pickup:setParameter("color", g_pickupColours[k.type])
        pickup:setPosition( k.pos )
        pickup:setScale(pickupSize)
        pickup:start()

        self.cl.pickups[#self.cl.pickups+1] = pickup
    end
end

function World:cl_managePickupEffect( args )
    if args.active then
		sm.effect.playEffect( "Part - Upgrade", args.pos, sm.vec3.zero(), sm.vec3.getRotation( sm.vec3.new(0,1,0), sm.vec3.new(0,0,1) ) )
        self.cl.pickups[args.id]:start()
    else
        self.cl.pickups[args.id]:stop()
    end

    if args.delete then
        self.cl.pickups[args.id] = nil
    end
end

function World:sv_onHitscanShot( args )
	self.network:sendToClients("cl_onHitscanShot", args)
end

function World:cl_onHitscanShot( args )
	local effect = sm.effect.createEffect( "HitscanShot" )
	effect:setPosition(args.pos)
	effect:setScale(sm.vec3.new(args.scale,0.25,0.25)/4)
	effect:setRotation( sm.vec3.getRotation( sm.vec3.new(1,0,0), args.dir ) )
	effect:setParameter("color", sm.color.new(1,1,0))
	effect:start()

	self.cl.hitscanEffects[#self.cl.hitscanEffects+1] = { effect = effect, cd = 0.1 }
end

function World:client_onUpdate( dt )
	for v, k in pairs(self.cl.hitscanEffects) do
		k.cd = k.cd - dt
		if k.cd <= 0 then
			k.effect:stopImmediate()
			k = nil
		end
	end
end

function World.cl_n_pesticideMsg( self, msg )
	g_pesticideManager[msg.fn]( g_pesticideManager, msg )
end