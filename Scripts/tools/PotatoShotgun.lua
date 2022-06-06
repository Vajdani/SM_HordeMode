dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

local Damage = 16
local autoFireRate = 12 --ticks
local hookRange = 30 --meters?
local hookForceMult = 250
local hookDetachDistance = 1.5
local meathookDetachImpulse = 1250
local hookUseCD = 200
local mods = {
	{
		name = "Full Auto",
		fpCol = sm.color.new(0,0.4,0.9),
		tpCol = sm.color.new(0,0.4,0.9),
		prim_projectile = projectile_fries,
		sec_projectile = projectile_fries,
		fireVels = { 130, 130 },
		auto = true
	},
	{
		name = "Explosive Shot",
		fpCol = sm.color.new(0.78,0.03,0.03),
		tpCol = sm.color.new(0.78,0.03,0.03),
		prim_projectile = projectile_fries,
		sec_projectile = sm.uuid.new("2abc4c0c-dd91-48be-96a6-4d69bc5d8276"),
		fireVels = { 130, 30 },
		auto = false
	},
	{
		name = "Pump",
		fpCol = sm.color.new("#11ab0c"),
		tpCol = sm.color.new("#11ab0c"),
		prim_projectile = projectile_fries,
		sec_projectile = projectile_fries,
		fireVels = { 130, 130 },
		auto = false
	},
	{
		name = "Meathook",
		fpCol = sm.color.new("#e1b40f"),
		tpCol = sm.color.new("#e1b40f"),
		prim_projectile = projectile_fries,
		sec_projectile = "hook",
		fireVels = { 130, 130 },
		auto = false
	}
}

local pumpColours = {
	sm.color.new("#11ab0c"),
	sm.color.new("#decc0d"),
	sm.color.new("#de800d"),
	sm.color.new("#de0d0d")
}
local flashFrequency = 40 / 6
local flashColours = {
	pumpColours[#pumpColours],
	sm.color.new(0,0,0)
}

PotatoShotgun = class()

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",

	--"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_frier/char_spudgun_barrel_frier.rend",
	"$CONTENT_DATA/Characters/char_spudgun_barrel_frier.rend",

	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_basic/char_spudgun_sight_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}

local renderablesTp = {"$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend", "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"}
local renderablesFp = {"$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend"}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function PotatoShotgun.client_onCreate( self )
	self.shootEffect = sm.effect.createEffect( "SpudgunFrier - FrierMuzzel" )
	self.shootEffectFP = sm.effect.createEffect( "SpudgunFrier - FPFrierMuzzel" )
	self.tool:setFpColor(mods[1].fpCol)
	self.tool:setTpColor(mods[1].tpCol)

	self.cl = {}
	self.cl.uuid = g_shotgun
	self.cl.hooks = {}
	self.cl.flashing = false
	self.cl.flashTimer = Timer()
	self.cl.flashTimer:start( flashFrequency )
	self.cl.flashCount = 1

	if not self.tool:isLocal() then return end
	self.cl.mod = 1
	self.cl.primState = nil
	self.cl.secState = nil
	self.cl.autoFire = Timer()
	self.cl.autoFire:start( autoFireRate )
	self.cl.pumpCount = 1

	self.cl.hookGui = sm.gui.createWorldIconGui( 50, 50 )
	self.cl.hookGui:setImage("Icon", "$CONTENT_DATA/susshake.png")
	self.cl.hookTarget = nil

	self.cl.baseGun = BaseGun()
	self.cl.baseGun.cl_create( self, mods, hookUseCD )
end

function PotatoShotgun:server_onCreate()
	self.sv = {}
	self.sv.hookTarget = nil
end

function PotatoShotgun:sv_toggleFlash( toggle )
	self.network:sendToClients("cl_toggleFlash", toggle )
end

function PotatoShotgun:cl_toggleFlash( toggle )
	self.cl.flashing = toggle
	self.cl.flashCount = 1
	self.cl.flashTimer:reset()
end

function PotatoShotgun:cl_setWpnModGui()
	local player = sm.localPlayer.getPlayer()
	local data = player:getClientPublicData()
	data.weaponMod = {
		name = mods[self.cl.mod].name,
		colour = mods[self.cl.mod].fpCol
	}

	player:setClientPublicData( data )
end

function PotatoShotgun:sv_changeColour( data )
	self.network:sendToClients("cl_changeColour", data)
end

function PotatoShotgun:cl_changeColour( data )
	if data == "secUse_start" then
		local fpCol, tpCol = self:cl_convertToUseCol()
		self.tool:setFpColor(fpCol)
		self.tool:setTpColor(tpCol)
		return
	end

	if data[1] == "flash" then
		self.tool:setFpColor(flashColours[data[2]])
		self.tool:setTpColor(flashColours[data[2]])
		return
	else
		self.cl.flashing = false
	end

	local index = data[1]
	if mods[index].name ~= "Pump" then
		self.tool:setFpColor(mods[index].fpCol)
		self.tool:setTpColor(mods[index].tpCol)
	else
		local pumps = data[2]
		self.tool:setFpColor(pumpColours[pumps])
		self.tool:setTpColor(pumpColours[pumps])
		if pumps == #pumpColours then
			self.cl.flashing = true
		end
	end
end

function PotatoShotgun:client_onReload()
	self.cl.mod = self.cl.mod == #mods and 1 or self.cl.mod + 1
	sm.event.sendToPlayer(sm.localPlayer.getPlayer(), "cl_queueMsg", "#ffffffCurrent weapon mod: #df7f00"..mods[self.cl.mod].name )
	sm.audio.play("PaintTool - ColorPick")

	self.network:sendToServer("sv_changeColour", { self.cl.mod, self.cl.pumpCount })
	self:cl_setWpnModGui()

	return true
end

function PotatoShotgun:client_onToggle()
	local hit, result = sm.localPlayer.getRaycast( 25 )
	if hit then
		self.network:sendToServer("sv_onToggle", result.pointWorld)
	end

	return true
end

function PotatoShotgun:sv_onToggle( pos )
	sm.unit.createUnit(unit_totebot_green, pos)
end

function PotatoShotgun:sv_explode()
	sm.physics.explode( self.tool:getOwner().character.worldPosition, 7, 2.0, 6.0, 25.0, "PropaneTank - ExplosionSmall" )
end

function PotatoShotgun:client_onFixedUpdate( dt )
	if not sm.exists(self.tool) or not self.tool:isEquipped() then return end
	local localTool = self.tool:isLocal()

	if self.cl.flashing then
		self.cl.flashTimer:tick()
		if self.cl.flashTimer:done() then
			self.cl.flashTimer:start(flashFrequency)
			self:cl_changeColour( { "flash", self.cl.flashCount } )
			if localTool and self.cl.flashCount == 1 then
				sm.audio.play("Button off")
			end

			self.cl.flashCount = self.cl.flashCount == 2 and 1 or 2
		end
	end

	if not localTool then return end
	self.cl.baseGun.cl_fixedUpdate( self )

	local player = sm.localPlayer.getPlayer()

	if mods[self.cl.mod].auto and (self.cl.primState == 1 or self.cl.primState == 2) and (self.cl.secState == 1 or self.cl.secState == 2) then
		self.cl.autoFire:tick()
		if self.cl.autoFire:done() then
			self.cl.autoFire:start(autoFireRate)
			self:cl_shoot()
		end
	else
		self.cl.autoFire:reset()
	end


	if mods[self.cl.mod].sec_projectile ~= "hook" or self.cl.useCD.active then
		if self.cl.hookGui:isActive() then
			self.cl.hookGui:close()
		end

		return
	end

	local clientData = player:getClientPublicData()
	if clientData.meathookState and clientData.input[sm.interactable.actions.jump] then
		self.network:sendToServer("sv_applyImpulse", { char = player.character, dir = g_up * meathookDetachImpulse } )
		self.cl.hookTarget = nil
		self.network:sendToServer("sv_setHookTarget", { target = nil, player = player })
	end

	if self.cl.hookTarget ~= nil and sm.exists(self.cl.hookTarget) then
		if self.cl.secState == 1 then
			self.cl.hookTarget = nil
			self.network:sendToServer("sv_setHookTarget", { target = nil, player = player })
		end

		return
	else
		self.cl.hookTarget = nil
	end

	local hit, result = sm.localPlayer.getRaycast( hookRange )
	if hit then
		local char = result:getCharacter()
		if char ~= nil and isAnyOf(char:getCharacterType(), g_robots) then
			self.cl.hookGui:open()
			self.cl.hookGui:setWorldPosition( char:getWorldPosition() )

			if self.cl.secState == sm.tool.interactState.start then
				self.cl.hookTarget = char
				player:getClientPublicData().meathookState = true
				self.network:sendToServer("sv_setHookTarget", { target = char, player = player })
				self.cl.hookGui:close()
			end
		else
			self.cl.hookGui:close()
		end
	else
		self.cl.hookGui:close()
	end
end

function PotatoShotgun:sv_setHookTarget( args )
	self.sv.hookTarget = args.target

	self.network:sendToClients("cl_createHook", { player = args.player, target = args.target, pos = args.player:getCharacter():getWorldPosition(), dir = args.player:getCharacter():getDirection(), delete = args.target == nil } )
end

function PotatoShotgun:cl_createHook( args )
	local id = args.player:getId()
	if args.delete then
		self.cl.hooks[id].effect:stopImmediate()
		self.cl.hooks[id] = nil

		local player = sm.localPlayer.getPlayer()
		if args.player == player then
			player:getClientPublicData().meathookState = false
			self.cl.useCD.active = true
		end

		return
	end

	local hook = sm.effect.createEffect("ShapeRenderable")
	hook:setParameter("uuid", sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a"))
	hook:setParameter("color", sm.color.new(0,0,0))
	hook:setPosition( args.pos )
	hook:setRotation( sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), args.dir ) )
	hook:setScale(sm.vec3.new(0.1,0.1,0.1))
	hook:start()
	self.cl.hooks[id] = { effect = hook, player = args.player, target = args.target, pos = args.pos }
end

function PotatoShotgun:server_onFixedUpdate( dt )
	if self.sv.hookTarget ~= nil and sm.exists(self.sv.hookTarget) then
		local playerChar = self.tool:getOwner():getCharacter()
		local dir = self.sv.hookTarget:getWorldPosition() - playerChar:getWorldPosition()

		if dir:length() <= hookDetachDistance then
			self:sv_setHookTarget( { target = nil, player = self.tool:getOwner() })
			self.network:sendToClients("cl_reset")
			return
		end

		sm.physics.applyImpulse(playerChar, dir:normalize() * hookForceMult, true)
	elseif self.sv.hookTarget ~= nil then
		self:sv_setHookTarget( { target = nil, player = self.tool:getOwner() })
		self.network:sendToClients("cl_reset")
	end
end

function PotatoShotgun:sv_applyImpulse( args )
	sm.physics.applyImpulse(args.char, args.dir, true)
end

function PotatoShotgun:cl_reset()
	if self.tool:isLocal() then
		self.cl.hookTarget = nil
	end
end


function PotatoShotgun:cl_shoot()
	local aiming = (self.cl.secState == 1 or self.cl.secState == 2)
	local mod = mods[self.cl.mod]
	if aiming and mod.sec_projectile == "hook" then return end

	if not sm.game.getEnableAmmoConsumption() or sm.container.canSpend( sm.localPlayer.getInventory(), obj_plantables_potato, 2 ) then

		local firstPerson = self.tool:isInFirstPersonView()

		local dir = sm.localPlayer.getDirection()

		local firePos = self:calculateFirePosition()
		local fakePosition = self:calculateTpMuzzlePos()
		local fakePositionSelf = fakePosition
		if firstPerson then
			fakePositionSelf = self:calculateFpMuzzlePos()
		end

		-- Aim assist
		if not firstPerson then
			local raycastPos = sm.camera.getPosition() + sm.camera.getDirection() * sm.camera.getDirection():dot( GetOwnerPosition( self.tool ) - sm.camera.getPosition() )
			local hit, result = sm.localPlayer.getRaycast( 250, raycastPos, sm.camera.getDirection() )
			if hit then
				local norDir = sm.vec3.normalize( result.pointWorld - firePos )
				local dirDot = norDir:dot( dir )

				if dirDot > 0.96592583 then -- max 15 degrees off
					dir = norDir
				else
					local radsOff = math.asin( dirDot )
					dir = sm.vec3.lerp( dir, norDir, math.tan( radsOff ) / 3.7320508 ) -- if more than 15, make it 15
				end
			end
		end

		dir = dir:rotate( math.rad( 0.955 ), sm.camera.getRight() ) -- 50 m sight calibration

		-- Spread
		local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
		local recoilDispersion = 1.0 - ( math.max(fireMode.minDispersionCrouching, fireMode.minDispersionStanding ) + fireMode.maxMovementDispersion )

		local spreadFactor = fireMode.spreadCooldown > 0.0 and clamp( self.spreadCooldownTimer / fireMode.spreadCooldown, 0.0, 1.0 ) or 0.0
		spreadFactor = clamp( self.movementDispersion + spreadFactor * recoilDispersion, 0.0, 1.0 )
		local spreadDeg =  fireMode.spreadMinAngle + ( fireMode.spreadMaxAngle - fireMode.spreadMinAngle ) * spreadFactor

		dir = sm.noise.gunSpread( dir, spreadDeg )

		local owner = self.tool:getOwner()
		if owner then
			local projectile = aiming and mod.sec_projectile or mod.prim_projectile
			local isPump = mod.name == "Pump"
			if self.cl.pumpCount == #pumpColours then
				self.network:sendToServer("sv_explode")
			else
				for i = 1, isPump and self.cl.pumpCount or 1 do
					dir = sm.noise.gunSpread( dir, spreadDeg * ( isPump and math.random( 10 ) or 1 ) )
					sm.projectile.projectileAttack( projectile, Damage, firePos, dir * mod.fireVels[aiming and 2 or 1], owner, fakePosition, fakePositionSelf )
				end
			end

			if isPump then
				self.cl.pumpCount = 1
				self.network:sendToServer("sv_changeColour", { self.cl.mod, self.cl.pumpCount } )
				self.network:sendToServer("sv_toggleFlash", false)
			end
		end

		-- Timers
		self.fireCooldownTimer = fireMode.fireCooldown
		self.spreadCooldownTimer = math.min( self.spreadCooldownTimer + fireMode.spreadIncrement, fireMode.spreadCooldown )
		self.sprintCooldownTimer = self.sprintCooldown

		-- Send TP shoot over network and dircly to self
		self:onShoot( dir )
		self.network:sendToServer( "sv_n_onShoot", dir )

		-- Play FP shoot animation
		setFpAnimation( self.fpAnimations, self.aiming and "aimShoot" or "shoot", 0.05 )
	else
		local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
		self.fireCooldownTimer = fireMode.fireCooldown
		sm.audio.play( "PotatoRifle - NoAmmo" )
	end
end

function PotatoShotgun.client_onRefresh( self )
	self:loadAnimations()
end

function PotatoShotgun.loadAnimations( self )

	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			shoot = { "spudgun_shoot", { crouch = "spudgun_crouch_shoot" } },
			aim = { "spudgun_aim", { crouch = "spudgun_crouch_aim" } },
			aimShoot = { "spudgun_aim_shoot", { crouch = "spudgun_crouch_aim_shoot" } },
			idle = { "spudgun_idle" },
			pickup = { "spudgun_pickup", { nextAnimation = "idle" } },
			putdown = { "spudgun_putdown" }
		}
	)
	local movementAnimations = {
		idle = "spudgun_idle",
		idleRelaxed = "spudgun_relax",

		sprint = "spudgun_sprint",
		runFwd = "spudgun_run_fwd",
		runBwd = "spudgun_run_bwd",

		jump = "spudgun_jump",
		jumpUp = "spudgun_jump_up",
		jumpDown = "spudgun_jump_down",

		land = "spudgun_jump_land",
		landFwd = "spudgun_jump_land_fwd",
		landBwd = "spudgun_jump_land_bwd",

		crouchIdle = "spudgun_crouch_idle",
		crouchFwd = "spudgun_crouch_fwd",
		crouchBwd = "spudgun_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.tool:isLocal() then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "spudgun_pickup", { nextAnimation = "idle" } },
				unequip = { "spudgun_putdown" },

				idle = { "spudgun_idle", { looping = true } },
				shoot = { "spudgun_shoot", { nextAnimation = "idle" } },

				aimInto = { "spudgun_aim_into", { nextAnimation = "aimIdle" } },
				aimExit = { "spudgun_aim_exit", { nextAnimation = "idle", blendNext = 0 } },
				aimIdle = { "spudgun_aim_idle", { looping = true} },
				aimShoot = { "spudgun_aim_shoot", { nextAnimation = "aimIdle"} },

				sprintInto = { "spudgun_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "spudgun_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "spudgun_sprint_idle", { looping = true } },
			}
		)
	end

	self.normalFireMode = {
		fireCooldown = 0.6,
		spreadCooldown = 0.18,
		spreadIncrement = 2.6,
		spreadMinAngle = .25,
		spreadMaxAngle = 8,
		fireVelocity = 130.0,

		minDispersionStanding = 0.1,
		minDispersionCrouching = 0.04,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.aimFireMode = {
		fireCooldown = 0.6,
		spreadCooldown = 0.18,
		spreadIncrement = 1.3,
		spreadMinAngle = 0,
		spreadMaxAngle = 8,
		fireVelocity =  130.0,

		minDispersionStanding = 0.01,
		minDispersionCrouching = 0.01,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.fireCooldownTimer = 0.0
	self.spreadCooldownTimer = 0.0

	self.movementDispersion = 0.0

	self.sprintCooldownTimer = 0.0
	self.sprintCooldown = 0.3

	self.aimBlendSpeed = 3.0
	self.blendTime = 0.2

	self.jointWeight = 0.0
	self.spineWeight = 0.0
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )

end

function PotatoShotgun.client_onUpdate( self, dt )
	if not sm.exists(self.tool) then return end

	for v, k in pairs(self.cl.hooks) do
		if sm.exists(k.target) then
			k.pos = k.player:getCharacter():getWorldPosition()
			local targetPos = k.target:getWorldPosition()
			local delta = targetPos - k.pos
			local rot = sm.vec3.getRotation(sm.vec3.new(0, 0, 1), delta)
			local distance = sm.vec3.new(0.01, 0.01, delta:length())

			k.effect:setPosition(k.pos + delta * 0.5)
			k.effect:setScale(distance)
			k.effect:setRotation(rot)
		end
	end


	-- First person animation
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.tool:isLocal() then
		if self.equipped then
			if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
				swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
			elseif not self.tool:isSprinting() and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
				swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
			end

			if self.aiming and not isAnyOf( self.fpAnimations.currentAnimation, { "aimInto", "aimIdle", "aimShoot" } ) then
				swapFpAnimation( self.fpAnimations, "aimExit", "aimInto", 0.0 )
			end
			if not self.aiming and isAnyOf( self.fpAnimations.currentAnimation, { "aimInto", "aimIdle", "aimShoot" } ) then
				swapFpAnimation( self.fpAnimations, "aimInto", "aimExit", 0.0 )
			end
		end
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	local effectPos, rot

	if self.tool:isLocal() then

		local zOffset = 0.6
		if self.tool:isCrouching() then
			zOffset = 0.29
		end

		local dir = sm.localPlayer.getDirection()
		local firePos = self.tool:getFpBonePos( "pejnt_barrel" )

		if not self.aiming then
			effectPos = firePos + dir * 0.2
		else
			effectPos = firePos + dir * 0.45
		end

		rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), dir )


		self.shootEffectFP:setPosition( effectPos )
		self.shootEffectFP:setVelocity( self.tool:getMovementVelocity() )
		self.shootEffectFP:setRotation( rot )
	end
	local pos = self.tool:getTpBonePos( "pejnt_barrel" )
	--local dir = self.tool:getTpBoneDir( "pejnt_barrel" )
	local dir = sm.localPlayer.getDirection()

	effectPos = pos + dir * 0.2

	rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), dir )


	self.shootEffect:setPosition( effectPos )
	self.shootEffect:setVelocity( self.tool:getMovementVelocity() )
	self.shootEffect:setRotation( rot )

	-- Timers
	self.fireCooldownTimer = math.max( self.fireCooldownTimer - dt, 0.0 )
	self.spreadCooldownTimer = math.max( self.spreadCooldownTimer - dt, 0.0 )
	self.sprintCooldownTimer = math.max( self.sprintCooldownTimer - dt, 0.0 )


	if self.tool:isLocal() then
		local dispersion = 0.0
		local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
		local recoilDispersion = 1.0 - ( math.max( fireMode.minDispersionCrouching, fireMode.minDispersionStanding ) + fireMode.maxMovementDispersion )

		if isCrouching then
			dispersion = fireMode.minDispersionCrouching
		else
			dispersion = fireMode.minDispersionStanding
		end

		if self.tool:getRelativeMoveDirection():length() > 0 then
			dispersion = dispersion + fireMode.maxMovementDispersion * self.tool:getMovementSpeedFraction()
		end

		if not self.tool:isOnGround() then
			dispersion = dispersion * fireMode.jumpDispersionMultiplier
		end

		self.movementDispersion = dispersion

		self.spreadCooldownTimer = clamp( self.spreadCooldownTimer, 0.0, fireMode.spreadCooldown )
		local spreadFactor = fireMode.spreadCooldown > 0.0 and clamp( self.spreadCooldownTimer / fireMode.spreadCooldown, 0.0, 1.0 ) or 0.0

		self.tool:setDispersionFraction( clamp( self.movementDispersion + spreadFactor * recoilDispersion, 0.0, 1.0 ) )

		if self.aiming then
			if self.tool:isInFirstPersonView() then
				self.tool:setCrossHairAlpha( 0.0 )
			else
				self.tool:setCrossHairAlpha( 1.0 )
			end
			self.tool:setInteractionTextSuppressed( true )
		else
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
		end
	end

	-- Sprint block
	local blockSprint = self.aiming or self.sprintCooldownTimer > 0.0
	self.tool:setBlockSprint( blockSprint )

	local playerDir = self.tool:getDirection()
	local angle = math.asin( playerDir:dot( sm.vec3.new( 0, 0, 1 ) ) ) / ( math.pi / 2 )
	local linareAngle = playerDir:dot( sm.vec3.new( 0, 0, 1 ) )

	local linareAngleDown = clamp( -linareAngle, 0.0, 1.0 )

	down = clamp( -angle, 0.0, 1.0 )
	fwd = ( 1.0 - math.abs( angle ) )
	up = clamp( angle, 0.0, 1.0 )

	local crouchWeight = self.tool:isCrouching() and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if ( name == "shoot" or name == "aimShoot" ) then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 10.0 )
				elseif name == "pickup" then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation( animation.time, weight )
		elseif animation.crouch then
			self.tool:updateAnimation( animation.info.name, animation.time, weight * normalWeight )
			self.tool:updateAnimation( animation.crouch.name, animation.time, weight * crouchWeight )
		else
			self.tool:updateAnimation( animation.info.name, animation.time, weight )
		end
	end

	-- Third Person joint lock
	local relativeMoveDirection = self.tool:getRelativeMoveDirection()
	if ( ( ( isAnyOf( self.tpAnimations.currentAnimation, { "aimInto", "aim", "shoot" } ) and ( relativeMoveDirection:length() > 0 or isCrouching) ) or ( self.aiming and ( relativeMoveDirection:length() > 0 or isCrouching) ) ) and not isSprinting ) then
		self.jointWeight = math.min( self.jointWeight + ( 10.0 * dt ), 1.0 )
	else
		self.jointWeight = math.max( self.jointWeight - ( 6.0 * dt ), 0.0 )
	end

	if ( not isSprinting ) then
		self.spineWeight = math.min( self.spineWeight + ( 10.0 * dt ), 1.0 )
	else
		self.spineWeight = math.max( self.spineWeight - ( 10.0 * dt ), 0.0 )
	end

	local finalAngle = ( 0.5 + angle * 0.5 )
	self.tool:updateAnimation( "spudgun_spine_bend", finalAngle, self.spineWeight )

	local totalOffsetZ = lerp( -22.0, -26.0, crouchWeight )
	local totalOffsetY = lerp( 6.0, 12.0, crouchWeight )
	local crouchTotalOffsetX = clamp( ( angle * 60.0 ) -15.0, -60.0, 40.0 )
	local normalTotalOffsetX = clamp( ( angle * 50.0 ), -45.0, 50.0 )
	local totalOffsetX = lerp( normalTotalOffsetX, crouchTotalOffsetX , crouchWeight )

	local finalJointWeight = ( self.jointWeight )


	self.tool:updateJoint( "jnt_hips", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.35 * finalJointWeight * ( normalWeight ) )

	local crouchSpineWeight = ( 0.35 / 3 ) * crouchWeight

	self.tool:updateJoint( "jnt_spine1", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight )  * finalJointWeight )
	self.tool:updateJoint( "jnt_spine2", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_spine3", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.45 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_head", sm.vec3.new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.3 * finalJointWeight )


	-- Camera update
	local bobbing = 1
	if self.aiming then
		local blend = 1 - math.pow( 1 - 1 / self.aimBlendSpeed, dt * 60 )
		self.aimWeight = sm.util.lerp( self.aimWeight, 1.0, blend )
		bobbing = 0.12
	else
		local blend = 1 - math.pow( 1 - 1 / self.aimBlendSpeed, dt * 60 )
		self.aimWeight = sm.util.lerp( self.aimWeight, 0.0, blend )
		bobbing = 1
	end

	self.tool:updateCamera( 2.8, 30.0, sm.vec3.new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( 30.0, sm.vec3.new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end

function PotatoShotgun.client_onEquip( self, animate )
	if self.tool:isLocal() then
		self.network:sendToServer("sv_changeColour", { self.cl.mod, self.cl.pumpCount } )
		self:cl_setWpnModGui()
	end

	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.wantEquipped = true
	self.aiming = false
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	currentRenderablesTp = {}
	currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end

	self.tool:setTpRenderables( currentRenderablesTp )

	self:loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )

	if self.tool:isLocal() then
		-- Sets PotatoShotgun renderable, change this to change the mesh
		self.tool:setFpRenderables( currentRenderablesFp )
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function PotatoShotgun.client_onUnequip( self, animate )
	if self.tool:isLocal() then
		self.cl.hookGui:close()
		self.network:sendToServer("sv_toggleFlash", false)
		self.cl.pumpCount = 1
		self.network:sendToServer("sv_changeColour", { self.cl.mod, self.cl.pumpCount } )
	end

	self.wantEquipped = false
	self.equipped = false
	self.aiming = false
	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.tool:isLocal() then
			self.tool:setMovementSlowDown( false )
			self.tool:setBlockSprint( false )
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
			end
		end
	end
end

function PotatoShotgun.sv_n_onAim( self, aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function PotatoShotgun.cl_n_onAim( self, aiming )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function PotatoShotgun.onAim( self, aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

function PotatoShotgun.sv_n_onShoot( self, dir )
	self.network:sendToClients( "cl_n_onShoot", dir )
end

function PotatoShotgun.cl_n_onShoot( self, dir )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onShoot( dir )
	end
end

function PotatoShotgun.onShoot( self, dir )
	self.tpAnimations.animations.idle.time = 0
	self.tpAnimations.animations.shoot.time = 0
	self.tpAnimations.animations.aimShoot.time = 0

	setTpAnimation( self.tpAnimations, self.aiming and "aimShoot" or "shoot", 10.0 )

	if self.tool:isInFirstPersonView() then
		self.shootEffectFP:start()
	else
		self.shootEffect:start()
	end

end

function PotatoShotgun.sv_n_onPump( self )
	self.network:sendToClients( "cl_n_onPump" )
end

function PotatoShotgun.cl_n_onPump( self )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onPump()
	end
end

function PotatoShotgun.onPump( self )
	self.tpAnimations.animations.idle.time = 0
	self.tpAnimations.animations.shoot.time = 0
	self.tpAnimations.animations.aimShoot.time = 0

	sm.audio.play("Button on", self.tool:getOwner():getCharacter():getWorldPosition())
	setTpAnimation( self.tpAnimations, self.aiming and "aimShoot" or "shoot", 10.0 )
end

function PotatoShotgun.calculateFirePosition( self )
	local crouching = self.tool:isCrouching()
	local firstPerson = self.tool:isInFirstPersonView()
	local dir = sm.localPlayer.getDirection()
	local pitch = math.asin( dir.z )
	local right = sm.localPlayer.getRight()

	local fireOffset = sm.vec3.new( 0.0, 0.0, 0.0 )

	if crouching then
		fireOffset.z = 0.15
	else
		fireOffset.z = 0.45
	end

	if firstPerson then
		if not self.aiming then
			fireOffset = fireOffset + right * 0.05
		end
	else
		fireOffset = fireOffset + right * 0.25
		fireOffset = fireOffset:rotate( math.rad( pitch ), right )
	end
	local firePosition = GetOwnerPosition( self.tool ) + fireOffset
	return firePosition
end

function PotatoShotgun.calculateTpMuzzlePos( self )
	local crouching = self.tool:isCrouching()
	local dir = sm.localPlayer.getDirection()
	local pitch = math.asin( dir.z )
	local right = sm.localPlayer.getRight()
	local up = right:cross(dir)

	local fakeOffset = sm.vec3.new( 0.0, 0.0, 0.0 )

	--General offset
	fakeOffset = fakeOffset + right * 0.25
	fakeOffset = fakeOffset + dir * 0.5
	fakeOffset = fakeOffset + up * 0.25

	--Action offset
	local pitchFraction = pitch / ( math.pi * 0.5 )
	if crouching then
		fakeOffset = fakeOffset + dir * 0.2
		fakeOffset = fakeOffset + up * 0.1
		fakeOffset = fakeOffset - right * 0.05

		if pitchFraction > 0.0 then
			fakeOffset = fakeOffset - up * 0.2 * pitchFraction
		else
			fakeOffset = fakeOffset + up * 0.1 * math.abs( pitchFraction )
		end
	else
		fakeOffset = fakeOffset + up * 0.1 *  math.abs( pitchFraction )
	end

	local fakePosition = fakeOffset + GetOwnerPosition( self.tool )
	return fakePosition
end

function PotatoShotgun.calculateFpMuzzlePos( self )
	local fovScale = ( sm.camera.getFov() - 45 ) / 45

	local up = sm.localPlayer.getUp()
	local dir = sm.localPlayer.getDirection()
	local right = sm.localPlayer.getRight()

	local muzzlePos45 = sm.vec3.new( 0.0, 0.0, 0.0 )
	local muzzlePos90 = sm.vec3.new( 0.0, 0.0, 0.0 )

	if self.aiming then
		muzzlePos45 = muzzlePos45 - up * 0.2
		muzzlePos45 = muzzlePos45 + dir * 0.5

		muzzlePos90 = muzzlePos90 - up * 0.5
		muzzlePos90 = muzzlePos90 - dir * 0.6
	else
		muzzlePos45 = muzzlePos45 - up * 0.15
		muzzlePos45 = muzzlePos45 + right * 0.2
		muzzlePos45 = muzzlePos45 + dir * 1.25

		muzzlePos90 = muzzlePos90 - up * 0.15
		muzzlePos90 = muzzlePos90 + right * 0.2
		muzzlePos90 = muzzlePos90 + dir * 0.25
	end

	return self.tool:getFpBonePos( "pejnt_barrel" ) + sm.vec3.lerp( muzzlePos45, muzzlePos90, fovScale )
end

function PotatoShotgun.cl_onPrimaryUse( self, state )
	if self.tool:getOwner().character == nil then
		return
	end

	if self.fireCooldownTimer <= 0.0 and state == sm.tool.interactState.start then
		self:cl_shoot()
	end
end

function PotatoShotgun.cl_onSecondaryUse( self, state )
	if mods[self.cl.mod].name ~= "Pump" then return end

	if state == sm.tool.interactState.start then
		local maxPumps = #pumpColours
		self.cl.pumpCount = self.cl.pumpCount < maxPumps and self.cl.pumpCount + 1 or maxPumps

		if self.cl.pumpCount == maxPumps and not self.cl.flashing then
			self.network:sendToServer("sv_toggleFlash", true)
		end

		self:onPump()
		self.network:sendToServer( "sv_n_onPump" )
		setFpAnimation( self.fpAnimations, self.aiming and "aimShoot" or "shoot", 0.05 )
		self.network:sendToServer("sv_changeColour", { self.cl.mod, self.cl.pumpCount } )
	end

	--[[if state == sm.tool.interactState.start and not self.aiming then
		self.aiming = true
		self.tpAnimations.animations.idle.time = 0

		self:onAim( self.aiming )
		self.tool:setMovementSlowDown( self.aiming )
		self.network:sendToServer( "sv_n_onAim", self.aiming )
	end

	if self.aiming and (state == sm.tool.interactState.stop or state == sm.tool.interactState.null) then
		self.aiming = false
		self.tpAnimations.animations.idle.time = 0

		self:onAim( self.aiming )
		self.tool:setMovementSlowDown( self.aiming )
		self.network:sendToServer( "sv_n_onAim", self.aiming )
	end]]
end

function PotatoShotgun.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuild )
	self.cl.primState = primaryState
	self.cl.secState = secondaryState

	if primaryState ~= self.prevPrimaryState then
		self:cl_onPrimaryUse( primaryState )
		self.prevPrimaryState = primaryState
	end

	if secondaryState ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( secondaryState )
		self.prevSecondaryState = secondaryState
	end

	self.cl.baseGun.cl_onEquippedUpdate( self, primaryState, secondaryState, forceBuild, true, "Meathook" )

	return true, true
end
