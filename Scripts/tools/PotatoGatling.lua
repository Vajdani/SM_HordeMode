dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/tools/BaseGun.lua"

local spinUpMult = 2.5
local spinUpProjs = {
	projectile_smallpotato,
	projectile_fries,
	projectile_tape,
	projectile_explosivetape,
}

local turretUUID = sm.uuid.new("bb314cd5-38bc-4b46-9fb7-0e7347bed62c")

local mods = {
	--[[
	{
		name = "Spin Up",
		fpCol = sm.color.new(0.78,0.03,0.03),
		tpCol = sm.color.new(0.78,0.03,0.03),
		prim_projectile = projectile_smallpotato,
		sec_projectile = projectile_smallpotato,
		damage = { 20, 20 },
		cost = { 1, 1 }
	},
	]]
	{
		name = "Turret",
		fpCol = sm.color.new(0,0.4,0.9),
		tpCol = sm.color.new(0,0.4,0.9),
		prim_projectile = projectile_smallpotato,
		sec_projectile = projectile_smallpotato,
		damage = { 22, 22 },
		cost = { 1, 1 },
		auto = true
	}
}

local dirY = sm.vec3.new( 0, 1, 0 )
local dirX = sm.vec3.new( 1, 0, 0 )
local deg90 = math.pi*0.5

---@class PotatoGatling : BaseGun
---@field windupEffect Effect
---@field gatlingActive boolean
---@field gatlingBlendSpeedIn number
---@field gatlingTurnSpeed number
---@field gatlingBlendSpeedOut number
PotatoGatling = class(BaseGun)

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_spinner/char_spudgun_barrel_spinner.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_spinner/char_spudgun_sight_spinner.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}

local renderablesTp = {
	"$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"
}
local renderablesFp = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function PotatoGatling.client_onCreate( self )
	self.shootEffect = sm.effect.createEffect( "SpudgunSpinner - SpinnerMuzzel" )
	self.shootEffectFP = sm.effect.createEffect( "SpudgunSpinner - FPSpinnerMuzzel" )
	self.windupEffect = sm.effect.createEffect( "SpudgunSpinner - Windup" )

	self.tool:setFpColor(mods[1].fpCol)
	self.tool:setTpColor(mods[1].tpCol)

	self.cl = {}
	self.cl.uuid = g_gatling
	self.isLocal = self.tool:isLocal()

	if not self.isLocal then return end
	self.cl.mod = 1
	self.cl.primState = nil
	self.cl.secState = nil
	self.cl.spinUpTime = 0
	self.cl.spinUpCanLevelUp = true

	self.cl.visEffect = sm.effect.createEffect( "ShapeRenderable" )
	self.cl.visEffect:setParameter("uuid", turretUUID)
	self.cl.visEffect:setParameter("visualization", true)
	self.cl.visEffect:setScale(sm.vec3.one() / 4)

	self.cl.rot = 1

	self:cl_create( mods, 0 )
end

function PotatoGatling:client_onDestroy()
	if self.cl.visEffect then
		self.cl.visEffect:stop()
	end
end

function PotatoGatling:cl_setWpnModGui()
	local player = sm.localPlayer.getPlayer()
	local data = player:getClientPublicData()

	data.weaponMod = {
		name = mods[self.cl.mod].name,
		colour = mods[self.cl.mod].fpCol
	}

	player:setClientPublicData( data )
end

function PotatoGatling:sv_changeColour( data )
	self.network:sendToClients("cl_changeColour", data)
end

function PotatoGatling:cl_changeColour( data )
	if data == "secUse_start" then
		local fpCol, tpCol = self:cl_convertToUseCol()
		self.tool:setFpColor(fpCol)
		self.tool:setTpColor(tpCol)
		return
	end

	self.tool:setFpColor(mods[data].fpCol)
	self.tool:setTpColor(mods[data].tpCol)
end

function PotatoGatling:client_onReload()
	self:cl_reload()
	return true
end

function PotatoGatling:client_onToggle()
	if mods[self.cl.mod].name == "Turret" then
		sm.audio.play("ConnectTool - Rotate")
		self.cl.rot = self.cl.rot == 4 and 1 or self.cl.rot + 1
	end

	return true
end

function PotatoGatling:client_onFixedUpdate( dt )
	if not sm.exists(self.tool) or not self.tool:isEquipped() then return end

	self:cl_fixedUpdate()
end

function PotatoGatling.loadAnimations( self )

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
		fireCooldown = 0.1,
		spreadCooldown = 0.18,
		spreadIncrement = 3.9,
		spreadMinAngle = 0.25,
		spreadMaxAngle = 32,
		fireVelocity = 130.0,
		
		minDispersionStanding = 0.1,
		minDispersionCrouching = 0.04,
		
		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.aimFireMode = {
		fireCooldown = 0.1,
		spreadCooldown = 0.18,
		spreadIncrement = 1.95,
		spreadMinAngle = 0.25,
		spreadMaxAngle = 24,
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
	
	self.gatlingActive = false
	self.gatlingBlendSpeedIn = 100 --1.5
	self.gatlingBlendSpeedOut = 0.375
	self.gatlingWeight = 0.0
	self.gatlingTurnSpeed = ( 1 / self.normalFireMode.fireCooldown ) / 3
	self.gatlingTurnFraction = 0.0
end

function PotatoGatling.client_onUpdate( self, dt )
	if not sm.exists(self.tool) then return end

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
	self:cl_updateGatling( dt )
end

function PotatoGatling.client_onEquip( self, animate )
	if self.isLocal then
		self.network:sendToServer("sv_changeColour", self.cl.mod)
		self:cl_setWpnModGui()
	end

	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.windupEffect:start()
	self.wantEquipped = true
	self.aiming = false
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	self:cl_equip( renderablesTp, renderablesFp, renderables )
end

function PotatoGatling.client_onUnequip( self, animate )
	self.windupEffect:stop()
	self.wantEquipped = false
	self.equipped = false
	self.aiming = false
	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.isLocal then
			self.cl.visEffect:stop()

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

function PotatoGatling.sv_n_onAim( self, aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function PotatoGatling.cl_n_onAim( self, aiming )
	if not self.isLocal and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function PotatoGatling.onAim( self, aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

function PotatoGatling.sv_n_onShoot( self )
	self.network:sendToClients( "cl_n_onShoot" )
end

function PotatoGatling.cl_n_onShoot( self )
	if not self.isLocal and self.tool:isEquipped() then
		self:onShoot()
	end
end

function PotatoGatling.onShoot( self )
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

function PotatoGatling.cl_updateGatling( self, dt )
	local spinUp = mods[self.cl.mod].name == "Spin Up" and (self.cl.secState == 1 or self.cl.secState == 2 )
	local mult = spinUp and spinUpMult or 1
	if spinUp and not self.gatlingActive and self.cl.spinUpCanLevelUp then
		self.cl.spinUpTime = sm.util.clamp(self.cl.spinUpTime + dt / 2, 0, #spinUpProjs)
	elseif not spinUp then
		self.cl.spinUpTime = 0
		self.cl.spinUpCanLevelUp = true
	else
		self.cl.spinUpCanLevelUp = false
	end

	self.gatlingWeight = (self.gatlingActive or spinUp) and ( self.gatlingWeight + self.gatlingBlendSpeedIn * dt * mult ) or ( self.gatlingWeight - self.gatlingBlendSpeedOut * dt )
	self.gatlingWeight = math.min( math.max( self.gatlingWeight, 0.0 ), 1.0 )
	local frac
	frac, self.gatlingTurnFraction = math.modf( self.gatlingTurnFraction + self.gatlingTurnSpeed * self.gatlingWeight * dt )

	self.windupEffect:setParameter( "velocity", self.gatlingWeight )
	if self.equipped and not self.windupEffect:isPlaying() then
		self.windupEffect:start()
	elseif not self.equipped and self.windupEffect:isPlaying() then
		self.windupEffect:stop()
	end

	-- Update gatling animation
	if self.isLocal then
		self.tool:updateFpAnimation( "spudgun_spinner_shoot_fp", self.gatlingTurnFraction, 1.0, true )
	end
	self.tool:updateAnimation( "spudgun_spinner_shoot_tp", self.gatlingTurnFraction, 1.0 )

	if self.fireCooldownTimer <= 0.0 and self.gatlingWeight >= 1.0 and self.gatlingActive then
		self:cl_fire()
	end
end

function PotatoGatling.cl_fire( self )
	if self.tool:getOwner().character == nil then
		return
	end

	local aiming = (self.cl.secState == 1 or self.cl.secState == 2)
	local index = aiming and 2 or 1

	if not sm.game.getEnableAmmoConsumption() or sm.container.canSpend( sm.localPlayer.getInventory(), obj_plantables_potato, 1 ) then

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
			local projectile

			if mods[self.cl.mod].name ~= "Spin Up" then
				projectile = aiming and mods[self.cl.mod].sec_projectile or mods[self.cl.mod].prim_projectile
			else
				projectile = spinUpProjs[math.floor(self.cl.spinUpTime)]

				if projectile == nil then projectile = projectile_smallpotato end
			end

			sm.projectile.projectileAttack( projectile, mods[self.cl.mod].damage[index], firePos, dir * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
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

function PotatoGatling.cl_onSecondaryUse( self, state )
	if mods[self.cl.mod].name == "Spin Up" then return end

	local aiming = state == 1 or state == 2
	if aiming ~= self.aiming then
		self.aiming = aiming
		self.tpAnimations.animations.idle.time = 0

		self:onAim( self.aiming )
		self.tool:setMovementSlowDown( self.aiming )
		self.network:sendToServer( "sv_n_onAim", self.aiming )
	end
end


function PotatoGatling.constructionRayCast( self )
	local valid, result = sm.localPlayer.getRaycast( 7.5 )
	if valid then
		if result.type == "terrainSurface" then
			local constants = sm.construction.constants
			local groundPointOffset = -( constants.subdivideRatio_2 - 0.04 + constants.shapeSpacing + 0.005 )
			local pointLocal = result.pointLocal + result.normalLocal * groundPointOffset
			local size = sm.vec3.new( 3, 3, 1 )
			local size_2 = sm.vec3.new( 1, 1, 0 )
			local a = pointLocal * constants.subdivisions
			local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), a.z ) - size_2

			local ratio = constants.subdivideRatio
			local worldPos = gridPos * ratio + ( size * ratio ) * 0.5
			return valid, worldPos, result.normalWorld
		end
	end

	return false
end


function PotatoGatling.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuild )
	if not sm.exists(self.tool) then return end

	self:cl_onEquippedUpdate( primaryState, secondaryState, forceBuild, false, nil )

	local name = mods[self.cl.mod].name
	if name == "Turret" then
		local hit, worldPos, worldNormal = ConstructionRayCast( { "terrainSurface" } )

		if hit then
			local keyBindingText =  sm.gui.getKeyBinding( "ForceBuild", true )
			sm.gui.setInteractionText( "", keyBindingText, "Place Turret" )

			local rot = sm.quat.angleAxis( deg90, dirX ) * sm.quat.angleAxis( deg90 * self.cl.rot, dirY )

			self.cl.visEffect:setPosition( worldPos + sm.vec3.new(0,0,1) / 8 )
			self.cl.visEffect:setRotation( rot )

			if not self.cl.visEffect:isPlaying() then
				self.cl.visEffect:start()
			end

			if forceBuild then
				self.network:sendToServer("sv_placeTurret",
					{
						pos = worldPos,
						rot = rot,
						player = sm.localPlayer.getPlayer()
					}
				)
				self.cl.visEffect:stop()
			end
		else
			self.cl.visEffect:stop()
		end
	else
		self.cl.visEffect:stop()
	end

	if self.cl.secState == 1 or self.cl.secState == 2 then
		if name == "Spin Up" then
			sm.gui.setProgressFraction( self.cl.spinUpTime/#spinUpProjs )
		end
	end

	self.gatlingActive = (primaryState == 1 or primaryState == 2) and not forceBuild

	if secondaryState ~= self.prevSecondaryState then
		self:cl_onSecondaryUse( secondaryState )
		self.prevSecondaryState = secondaryState
	end

	return true, true
end

---@class turretData
---@field pos Vec3
---@field rot Quat
---@field player Player

---@param args turretData
function PotatoGatling:sv_placeTurret( args )
	local turret = sm.shape.createPart(
		turretUUID,
		args.pos - sm.vec3.new(0.125,0.125,0),
		sm.quat.identity() --[[args.rot]],
		false,
		true
	)

	local player = args.player
	turret.interactable:setPublicData( { owner = player } )

	sm.container.beginTransaction()
	local inv = sm.game.getLimitedInventory() and player:getInventory() or player:getHotbar()
	sm.container.spend(inv, g_gatling, 1)
	sm.container.endTransaction()
end