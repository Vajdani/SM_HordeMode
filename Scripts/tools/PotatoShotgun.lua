dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/tools/BaseGun.lua"

local Damage = 16
local autoFireRate = 12 --ticks
local hookRange = 30 --meters?
local hookForceMult = 250
local hookDetachDistance = 1.5^2
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
	}--[[,
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
	}]]
}

local pumpColours = {
	sm.color.new("#11ab0c"),
	sm.color.new("#decc0d"),
	sm.color.new("#de800d"),
	sm.color.new("#de0d0d")
}
local flashFrequency = 40 / 4
local flashColours = {
	pumpColours[#pumpColours],
	sm.color.new(0,0,0)
}

---@class Shotgun_sv
---@field hookTarget Character

---@class PotatoShotgun : BaseGun
---@field sv Shotgun_sv
PotatoShotgun = class(BaseGun)

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
	self.isLocal = self.tool:isLocal()
	self.cl.hooks = {}
	self.cl.flashing = false
	self.cl.flashTimer = Timer()
	self.cl.flashTimer:start( flashFrequency )
	self.cl.flashCount = 1

	if not self.isLocal then return end
	self.cl.mod = 1
	self.cl.primState = nil
	self.cl.secState = nil
	self.cl.autoFire = Timer()
	self.cl.autoFire:start( autoFireRate )
	self.cl.pumpCount = 1

	self.cl.hookGui = sm.gui.createWorldIconGui( 50, 50 )
	self.cl.hookGui:setImage("Icon", "$CONTENT_DATA/susshake.png")
	self.cl.hookTarget = nil

	self:cl_create( mods, hookUseCD )
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
	self:cl_reload()
	return true
end

function PotatoShotgun:client_onToggle()
	return true
end

function PotatoShotgun:sv_explode()
	sm.physics.explode( self.tool:getOwner().character.worldPosition, 7, 2.0, 6.0, 25.0, "PropaneTank - ExplosionSmall" )
end

function PotatoShotgun:client_onFixedUpdate( dt )
	if not sm.exists(self.tool) or not self.tool:isEquipped() then return end

	if self.cl.flashing then
		self.cl.flashTimer:tick()
		if self.cl.flashTimer:done() then
			self.cl.flashTimer:start(flashFrequency)
			self:cl_changeColour( { "flash", self.cl.flashCount } )
			if self.isLocal and self.cl.flashCount == 1 then
				sm.audio.play( "Retrobass" )
			end

			self.cl.flashCount = self.cl.flashCount == 2 and 1 or 2
		end
	end

	if not self.isLocal then return end
	self:cl_fixedUpdate()

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
		local playerChar = self.tool:getOwner().character
		---@type Vec3
		local dir = self.sv.hookTarget.worldPosition - playerChar.worldPosition

		if dir:length2() <= hookDetachDistance then
			self:sv_setHookTarget( { target = nil, player = self.tool:getOwner() })
			self.network:sendToClients("cl_reset")
			return
		end

		sm.physics.applyImpulse(playerChar, dir:normalize() * hookForceMult)
	elseif self.sv.hookTarget ~= nil then
		self:sv_setHookTarget( { target = nil, player = self.tool:getOwner() })
		self.network:sendToClients("cl_reset")
	end
end

function PotatoShotgun:sv_applyImpulse( args )
	sm.physics.applyImpulse(args.char, args.dir, true)
end

function PotatoShotgun:cl_reset()
	if self.isLocal then
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

		self.fireCooldownTimer = fireMode.fireCooldown
		self.spreadCooldownTimer = math.min( self.spreadCooldownTimer + fireMode.spreadIncrement, fireMode.spreadCooldown )
		self.sprintCooldownTimer = self.sprintCooldown

		self:onShoot()
		self.network:sendToServer( "sv_n_onShoot" )
		setFpAnimation( self.fpAnimations, self.aiming and "aimShoot" or "shoot", 0.05 )
	else
		local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
		self.fireCooldownTimer = fireMode.fireCooldown
		sm.audio.play( "PotatoRifle - NoAmmo" )
	end
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

	if self.isLocal then
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
			k.pos = k.player.character.worldPosition
			---@type Vec3
			local targetPos = k.target.worldPosition
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

	if self.isLocal then
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

	if self.isLocal then
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

	self:cl_updateTimers( dt )
	self:cl_updateShootFX()
	self:cl_updateTP( dt, isSprinting, isCrouching )
end

function PotatoShotgun.client_onEquip( self, animate )
	if self.isLocal then
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

	self:cl_equip( renderablesTp, renderablesFp, renderables )
end

function PotatoShotgun.client_onUnequip( self, animate )
	if self.isLocal then
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
		if self.isLocal then
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

function PotatoShotgun.sv_n_onShoot( self )
	self.network:sendToClients( "cl_n_onShoot" )
end

function PotatoShotgun.cl_n_onShoot( self )
	if not self.isLocal and self.tool:isEquipped() then
		self:onShoot()
	end
end

function PotatoShotgun.onShoot( self )
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
	if not self.isLocal and self.tool:isEquipped() then
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
end

function PotatoShotgun.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuild )
	self:cl_onEquippedUpdate( primaryState, secondaryState, forceBuild, true, "Meathook" )

	if primaryState ~= self.prevPrimaryState then
		self:cl_onPrimaryUse( primaryState )
		self.prevPrimaryState = primaryState
	end

	if secondaryState ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( secondaryState )
		self.prevSecondaryState = secondaryState
	end

	return true, true
end
