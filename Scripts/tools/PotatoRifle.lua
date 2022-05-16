dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

local autoFireRate = 8 --ticks
local chargedBurstUseCD = 120
local sniperShotFireCooldown = 0.8
local defaultFireCooldown = 0.2
local maxBlastCharge = 35
local hitscanRange = 100
local coinCost = 5
local coinUUID = sm.uuid.new("35113888-1526-42fc-8165-3f68282d5a6d")
local coinRecharge = 200
local minSpreadShotSpread = 5
local maxSpreadShotSpread = 50
local spreadShotDecrease = 5 / 30
local coinColours = {
	low = sm.color.new("#ff0000"),
	med = sm.color.new("#e3e30b"),
	full = sm.color.new("#16e30b")
}
local mods = {
	{ name = "Charged Burst", prim_projectile = projectile_potato, sec_projectile = projectile_potato, damage = { 20, 20 }, cost = { 1, 1 }, auto = true },
	--{ name = "Coins", prim_projectile = "hitscan", sec_projectile = "hitscan", damage = { 20, 20 }, cost = { 1, 1 }, auto = true },
	--{ name = "Sniper", prim_projectile = projectile_potato, sec_projectile = sm.uuid.new("d48f73b3-521a-4f60-b4d3-0ff08b145cff"), damage = { 20, 164 }, cost = { 1, 12 }, auto = true },
	{ name = "Spread Shot", prim_projectile = projectile_potato, sec_projectile = projectile_potato, damage = { 20, 20 }, cost = { 1, 1 }, auto = true }
}

local function colourLerp(c1, c2, t)
	local r = sm.util.lerp(c1.r, c2.r, t)
	local g = sm.util.lerp(c1.g, c2.g, t)
	local b = sm.util.lerp(c1.b, c2.b, t)
	return sm.color.new(r,g,b)
end

PotatoRifle = class()

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_basic/char_spudgun_barrel_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_basic/char_spudgun_sight_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}

local renderablesTp = {"$CONTENT_988bc7a1-0885-436b-beb9-2b9fc659d005/Characters/char_male_tp_spudgun.rend", "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"}
local renderablesFp = {"$CONTENT_988bc7a1-0885-436b-beb9-2b9fc659d005/Characters/char_male_fp_spudgun.rend", "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend"}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function PotatoRifle.client_onCreate( self )
	self.shootEffect = sm.effect.createEffect( "SpudgunBasic - BasicMuzzel" )
	self.shootEffectFP = sm.effect.createEffect( "SpudgunBasic - FPBasicMuzzel" )

	self.cl = {}
	self.cl.mod = 1
	self.cl.primState = nil
	self.cl.secState = nil
	self.cl.autoFire = Timer()
	self.cl.autoFire:start( autoFireRate )
	self.cl.blastCharge = 0
	self.cl.blasting = false
	self.cl.spreadShotSpread = maxSpreadShotSpread

	self.cl.useCD = {}
	self.cl.useCD.active = false
	self.cl.useCD.cd = chargedBurstUseCD

	self.cl.coin = {}
	self.cl.coin.ammo = 4
	self.cl.coin.recharge = coinRecharge
	self.cl.coin.hud = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/coins.layout", false,
		{
			isHud = true,
			isInteractive = false,
			needsCursor = false
		}
	)
end

function PotatoRifle:client_onReload()
	self.cl.mod = self.cl.mod == #mods and 1 or self.cl.mod + 1
	sm.gui.displayAlertText("Current weapon mod: #df7f00"..mods[self.cl.mod].name, 2.5)
	sm.audio.play("PaintTool - ColorPick")

	return true
end

function PotatoRifle:client_onFixedUpdate( dt )
	if not sm.exists(self.tool) or not self.tool:isEquipped() or not self.tool:isLocal() then return end

	if self.cl.coin.ammo < 4 then
		self.cl.coin.recharge = self.cl.coin.recharge - 1
		if self.cl.coin.recharge <= 0 then
			self.cl.coin.ammo = self.cl.coin.ammo + 1
			self.cl.coin.recharge = coinRecharge
		end
	end

	if self.cl.useCD.active then
		self.cl.useCD.cd = self.cl.useCD.cd - 1
		if self.cl.useCD.cd <= 0 then
			self.cl.useCD.active = false
			self.cl.useCD.cd = chargedBurstUseCD
		end
	end

	if not self.tool:isEquipped() then
		self.cl.coin.hud:close()
		return
	end

	if mods[self.cl.mod].name == "Coins" then
		self.cl.coin.hud:open()
		for i = 1, self.cl.coin.ammo do
			self.cl.coin.hud:setColor( "coin"..tostring(i), coinColours.full )
		end

		local fillAt = self.cl.coin.ammo + 1
		if fillAt <= 4 then
			--[[local colour
			if self.cl.coin.recharge > coinRecharge/2 then
				colour = coinColours.low
			else
				colour = coinColours.med
			end
			self.cl.coin.hud:setColor( "coin"..tostring(fillAt), colour )]]
			self.cl.coin.hud:setColor( "coin"..tostring(fillAt), colourLerp( coinColours.full, coinColours.low, self.cl.coin.recharge/coinRecharge ) )

			for i = fillAt + 1, 4 do
				self.cl.coin.hud:setColor( "coin"..tostring(i), coinColours.low )
			end
		end
	else
		self.cl.coin.hud:close()
	end

	if mods[self.cl.mod].auto and (self.cl.primState == 1 or self.cl.primState == 2) and (mods[self.cl.mod].name == "Spread Shot" or mods[self.cl.mod].name ~= "Sniper" and self.cl.secState == 0 or self.cl.secState == 0) and not self.cl.useCD.active then
		self.cl.autoFire:tick()
		if self.cl.autoFire:done() then
			self.cl.autoFire:start(autoFireRate)

			if mods[self.cl.mod].name == "Spread Shot" then
				self.cl.spreadShotSpread = sm.util.clamp(self.cl.spreadShotSpread + spreadShotDecrease * 2, minSpreadShotSpread, maxSpreadShotSpread)
			end

			self:cl_shoot()
		end
	else
		self.cl.spreadShotSpread = sm.util.clamp(self.cl.spreadShotSpread - spreadShotDecrease, minSpreadShotSpread, maxSpreadShotSpread)
		self.cl.autoFire:reset()
	end

	if mods[self.cl.mod].name == "Charged Burst" and (self.cl.secState == 1 or self.cl.secState == 2) and not self.cl.blasting and not self.cl.useCD.active  then
		self.cl.blastCharge = sm.util.clamp(self.cl.blastCharge + dt * 10, 0, maxBlastCharge)
	elseif self.cl.blastCharge > 0 then
		self.cl.blasting = true
		self:cl_shoot()
		self.cl.blastCharge = math.ceil(self.cl.blastCharge) - 1
	elseif self.cl.blastCharge == 0 and self.cl.blasting then
		self.cl.blasting = false
		self.cl.useCD.active = true
	end

	if not self.aimFireMode then return end

	if mods[self.cl.mod].name == "Sniper" then
		self.aimFireMode.fireCooldown = sniperShotFireCooldown
	else
		self.aimFireMode.fireCooldown = defaultFireCooldown
	end
end

function PotatoRifle:sv_applyImpulse ( args )
	sm.physics.applyImpulse(args.body, args.dir * 1000, true)
end

function PotatoRifle:sv_throwCoin( args )
	local grenade = sm.shape.createPart( args.uuid, args.pos, args.rot, args.dynamic, args.forceSpawn )
	sm.physics.applyImpulse(grenade, args.dir + args.player:getCharacter():getVelocity() * 5, true)

	sm.container.beginTransaction()
	sm.container.spend( args.player:getInventory(), obj_plantables_potato, coinCost )
	sm.container.endTransaction()
end

function PotatoRifle:sv_onCoinHit( args )
	local interactable = args.shape:getInteractable()
	interactable:setPublicData( { level = 1, damage = args.damage } )
	sm.event.sendToInteractable(interactable, "sv_onHit")
end

function PotatoRifle:sv_onHitscanShot( args )
	sm.event.sendToWorld( sm.player.getAllPlayers()[1].character:getWorld(), "sv_onHitscanShot", args)
end

function PotatoRifle:sv_onUnitHit( args )
	sm.event.sendToUnit(args.char:getUnit(), "sv_horde_takeDamage", { damage = mods[self.cl.mod].damage[args.index], impact = sm.vec3.one(), hitpos = args.char:getWorldPosition() } )
end

function PotatoRifle:cl_shoot()
	local aiming = (self.cl.secState == 1 or self.cl.secState == 2)
	local index = aiming and 2 or 1

	if not sm.game.getEnableAmmoConsumption() or sm.container.canSpend( sm.localPlayer.getInventory(), obj_plantables_potato, mods[self.cl.mod].cost[index] ) then

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
			local projectile = aiming and mods[self.cl.mod].sec_projectile or mods[self.cl.mod].prim_projectile
			if projectile == "hitscan" then
				local hit, result = sm.localPlayer.getRaycast(hitscanRange)
				if hit then
					local char = result:getCharacter()
					local shape = result:getShape()
					if char ~= nil then
						self.network:sendToServer("sv_onUnitHit", { char = char, index = index } )
					elseif shape ~= nil then
						if shape:getShapeUuid() == coinUUID then
							self.network:sendToServer("sv_onCoinHit", { shape = shape, damage = mods[self.cl.mod].damage[index] } )
						else
							self.network:sendToServer("sv_applyImpulse", { body = shape, dir = sm.localPlayer.getDirection() })
						end
					end
				end

				local scale = hit and (result.pointWorld - firePos):length() * 4 or hitscanRange
				self.network:sendToServer("sv_onHitscanShot", { pos = firePos + dir * (scale / 8), dir = dir, scale = scale })
			else
				if mods[self.cl.mod].name == "Spread Shot" then
					sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir:rotate(math.rad(-self.cl.spreadShotSpread*2), sm.camera.getUp()) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )	
					sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir:rotate(math.rad(-self.cl.spreadShotSpread), sm.camera.getUp()) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )	
					sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )	
					sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir:rotate(math.rad(self.cl.spreadShotSpread), sm.camera.getUp()) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )	
					sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir:rotate(math.rad(self.cl.spreadShotSpread*2), sm.camera.getUp()) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )	
					
				else
					sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )	
				end
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

function PotatoRifle.client_onRefresh( self )
	self:loadAnimations()
end

function PotatoRifle.loadAnimations( self )

	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			shoot = { "spudgun_shoot", { crouch = "spudgun_crouch_shoot" } },
			aim = { "spudgun_aim", { crouch = "spudgun_crouch_aim" } },
			aimShoot = { "spudgun_aim_shoot", { crouch = "spudgun_crouch_aim_shoot" } },
			idle = { "spudgun_idle" },
			pickup = { "spudgun_pickup", { nextAnimation = "idle" } },
			putdown = { "spudgun_putdown" }

			,coinThrow = { "spudgun_coin_throw", { nextAnimation = "idle" } },
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

				coinThrow = { "spudgun_coin_throw", { nextAnimation = "idle" } },
			}
		)
	end

	self.normalFireMode = {
		fireCooldown = 0.20,
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
		fireCooldown = 0.20,
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

function PotatoRifle.client_onUpdate( self, dt )
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
	local dir = self.tool:getTpBoneDir( "pejnt_barrel" )

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

function PotatoRifle.client_onEquip( self, animate )

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
		-- Sets PotatoRifle renderable, change this to change the mesh
		self.tool:setFpRenderables( currentRenderablesFp )
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function PotatoRifle.client_onUnequip( self, animate )

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

function PotatoRifle.sv_n_onAim( self, aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function PotatoRifle.cl_n_onAim( self, aiming )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function PotatoRifle.onAim( self, aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

function PotatoRifle.sv_n_onShoot( self, dir )
	self.network:sendToClients( "cl_n_onShoot", dir )
end

function PotatoRifle.cl_n_onShoot( self, dir )
	if not self.tool:isLocal() and self.tool:isEquipped() then
		self:onShoot( dir )
	end
end

function PotatoRifle.onShoot( self, dir )

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

function PotatoRifle.calculateFirePosition( self )
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

function PotatoRifle.calculateTpMuzzlePos( self )
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

function PotatoRifle.calculateFpMuzzlePos( self )
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

function PotatoRifle.cl_onPrimaryUse( self, state )
	if self.tool:getOwner().character == nil or self.cl.useCD.active then
		return
	end

	if self.fireCooldownTimer <= 0.0 and state == sm.tool.interactState.start and (mods[self.cl.mod].name ~= "Charged Burst" or self.cl.blastCharge == 0) then
		self:cl_shoot()
	end
end

function PotatoRifle.cl_onSecondaryUse( self, state )
	if mods[self.cl.mod].name ~= "Sniper" then
		if state == 1 then
			if mods[self.cl.mod].name == "Coins" and self.cl.coin.ammo > 0 then
				local dir = sm.localPlayer.getDirection()
				self.network:sendToServer("sv_throwCoin",
					{
						player = sm.localPlayer.getPlayer(),
						uuid = sm.uuid.new("35113888-1526-42fc-8165-3f68282d5a6d"),
						pos = sm.camera.getPosition() - sm.vec3.one() / 7 + dir * 2,
						rot = sm.quat.identity(),
						dynamic = true,
						forceSpawn = false,
						dir = dir:rotate(math.rad(10), sm.localPlayer.getRight()) * 100
					}
				)

				self.cl.coin.ammo = self.cl.coin.ammo - 1
				sm.audio.play("Button on")
			elseif self.cl.coin.ammo == 0 then
				sm.audio.play("Button off")
			end
		end

		return
	end

	if state == sm.tool.interactState.start and not self.aiming then
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
	end
end

function PotatoRifle.client_onEquippedUpdate( self, primaryState, secondaryState )
	self.cl.primState = primaryState
	self.cl.secState = secondaryState

	if self.cl.useCD.active then
		sm.gui.setProgressFraction( self.cl.useCD.cd/chargedBurstUseCD )
	elseif (self.cl.secState == 1 or self.cl.secState == 2) then
		if mods[self.cl.mod].name == "Sniper" then
			sm.gui.setProgressFraction( self.fireCooldownTimer/sniperShotFireCooldown )
		elseif mods[self.cl.mod].name == "Charged Burst" and not self.cl.blasting then
			sm.gui.setProgressFraction( self.cl.blastCharge/maxBlastCharge )
		end
	end

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
