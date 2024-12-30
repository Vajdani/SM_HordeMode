dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile "$CONTENT_DATA/Scripts/tools/BaseGun.lua"

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
	{
        name = "Charged Burst",
        fpCol = sm.color.new(0, 0.4, 0.9),
        tpCol = sm.color.new(0, 0.4, 0.9),
        prim_projectile = projectile_potato,
        sec_projectile = projectile_potato,
        damage = { 24, 24 },
        cost = { 1, 1 },
        auto = true
    },
	--[[
    {
        name = "Coins",
		fpCol = sm.color.new("#11ab0c"),
		tpCol = sm.color.new("#11ab0c"),
        prim_projectile = "hitscan",
        sec_projectile = "hitscan",
        damage = { 20, 20 },
        cost = { 1, 1 },
        auto = true
    },
	]]
	--[[
    {
        name = "Sniper",
		fpCol = sm.color.new("#e1b40f"),
		tpCol = sm.color.new("#e1b40f"),
        prim_projectile = projectile_potato,
        sec_projectile = sm.uuid.new("0ee21fec-16f6-44f4-b104-458c06941c5e"),
        damage = { 20, 164 },
        cost = { 1, 12 },
        auto = true
    },
	]]
    {
        name = "Spread Shot",
        fpCol = sm.color.new(0.78, 0.03, 0.03),
        tpCol = sm.color.new(0.78, 0.03, 0.03),
        prim_projectile = projectile_potato,
        sec_projectile = projectile_potato,
        damage = { 24, 24 },
        cost = { 1, 1 },
        auto = true
    }
}

local function colourLerp(c1, c2, t)
	local r = sm.util.lerp(c1.r, c2.r, t)
	local g = sm.util.lerp(c1.g, c2.g, t)
	local b = sm.util.lerp(c1.b, c2.b, t)
	return sm.color.new(r,g,b)
end

---@class PotatoRifle : BaseGun
PotatoRifle = class(BaseGun)

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",

	--"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_basic/char_spudgun_barrel_basic.rend",
	"$CONTENT_DATA/Characters/char_spudgun_barrel_basic.rend",

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
	self.tool:setFpColor(mods[1].fpCol)
	self.tool:setTpColor(mods[1].tpCol)

	self.cl = {}
	self.cl.uuid = g_spudgun
	self.isLocal = self.tool:isLocal()

	if not self.isLocal then return end
	self.cl.mod = 1
	self.cl.primState = nil
	self.cl.secState = nil
	self.cl.autoFire = Timer()
	self.cl.autoFire:start( autoFireRate )
	self.cl.blastCharge = 0
	self.cl.blasting = false
	self.cl.spreadShotSpread = 0

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

	--[[self.cl.chargeHud = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/charge.layout", false,
		{
			isHud = true,
			isInteractive = false,
			needsCursor = false
		}
	)]]
	--self.cl.chargeHud:createHorizontalSlider("chargeSlider", maxBlastCharge, 0, false, "cl_bruh")

	self:cl_create( mods, chargedBurstUseCD )
end

function PotatoRifle:cl_bruh()

end

function PotatoRifle:client_onDestroy()
	if self.cl ~= nil then
		self.cl.coin.hud:close()
		--self.cl.chargeHud:close()

		self.cl.coin.hud:destroy()
		--self.cl.chargeHud:destroy()
	end
end

function PotatoRifle:cl_setWpnModGui()
	local player = sm.localPlayer.getPlayer()
	local data = player:getClientPublicData()

	data.weaponMod = {
		name = mods[self.cl.mod].name,
		colour = mods[self.cl.mod].fpCol
	}

	player:setClientPublicData( data )
end

function PotatoRifle:sv_changeColour( data )
	self.network:sendToClients("cl_changeColour", data)
end

function PotatoRifle:cl_changeColour( data )
	if data == "secUse_start" then
		local fpCol, tpCol = self:cl_convertToUseCol()
		self.tool:setFpColor(fpCol)
		self.tool:setTpColor(tpCol)
		return
	end

	self.tool:setFpColor(mods[data].fpCol)
	self.tool:setTpColor(mods[data].tpCol)
end

function PotatoRifle:client_onReload()
	self:cl_reload()
	return true
end

function PotatoRifle:client_onToggle()
	return true
end

function PotatoRifle:client_onFixedUpdate( dt )
	if not sm.exists(self.tool) or not self.isLocal then return end

	if self.cl.coin.ammo < 4 then
		self.cl.coin.recharge = self.cl.coin.recharge - 1
		if self.cl.coin.recharge <= 0 then
			self.cl.coin.ammo = self.cl.coin.ammo + 1
			self.cl.coin.recharge = coinRecharge
		end
	end

	if not self.tool:isEquipped() then
		self.cl.coin.hud:close()
		--self.cl.chargeHud:close()

		return
	end

	self:cl_fixedUpdate()

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

	--uncomment the if check to fix the funny spread shot trick
	--if mods[self.cl.mod].name == "Charged Burst" then
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

		--[[self.cl.chargeHud:open()
		self.cl.chargeHud:setSliderPosition("chargeSlider", self.cl.blastCharge)
		self.cl.chargeHud:setSliderData( "chargeSlider", maxBlastCharge * 10 + 1, self.cl.blastCharge * 10 )
	else
		--self.cl.chargeHud:close()
	end]]

	if not self.aimFireMode then return end

	if mods[self.cl.mod].name == "Sniper" then
		self.aimFireMode.fireCooldown = sniperShotFireCooldown
	else
		self.aimFireMode.fireCooldown = defaultFireCooldown
	end
end

---@class ImpulseData
---@field body Body
---@field dir Vec3 

---@param args ImpulseData
function PotatoRifle:sv_applyImpulse( args )
	sm.physics.applyImpulse(args.body, args.dir * 1000, true)
end

---@class CoinData
---@field uuid Uuid
---@field pos Vec3 
---@field rot Quat 
---@field dynamic boolean
---@field forceSpawn boolean 
---@field dir Vec3
---@field player Player

---@param args CoinData
function PotatoRifle:sv_throwCoin( args )
	local grenade = sm.shape.createPart( args.uuid, args.pos, args.rot, args.dynamic, args.forceSpawn )
	sm.physics.applyImpulse(grenade, args.dir + args.player.character.velocity * 5, true)

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
			local mod = mods[self.cl.mod]
			local projectile = aiming and mod.sec_projectile or mod.prim_projectile
			local damage = mod.damage[index]

			if projectile == "hitscan" then
				local hit, result = sm.localPlayer.getRaycast(hitscanRange)
				if hit then
					local char = result:getCharacter()
					local shape = result:getShape()
					if char ~= nil then
						self.network:sendToServer("sv_onUnitHit", { char = char, index = index } )
					elseif shape ~= nil then
						if shape:getShapeUuid() == coinUUID then
							self.network:sendToServer("sv_onCoinHit", { shape = shape, damage = damage } )
						else
							self.network:sendToServer("sv_applyImpulse", { body = shape, dir = sm.localPlayer.getDirection() })
						end
					end
				end

				local scale = hit and (result.pointWorld - firePos):length() * 4 or hitscanRange
				self.network:sendToServer("sv_onHitscanShot", { pos = firePos + dir * (scale / 8), dir = dir, scale = scale })
			else
				if mod.name == "Spread Shot" then
					local up = sm.camera.getUp()
					sm.projectile.projectileAttack( projectile, damage, firePos, dir:rotate(math.rad(-self.cl.spreadShotSpread*2), up) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
					sm.projectile.projectileAttack( projectile, damage, firePos, dir:rotate(math.rad(-self.cl.spreadShotSpread), up) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
					sm.projectile.projectileAttack( projectile, damage, firePos, dir * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
					sm.projectile.projectileAttack( projectile, damage, firePos, dir:rotate(math.rad(self.cl.spreadShotSpread), up) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
					sm.projectile.projectileAttack( projectile, damage, firePos, dir:rotate(math.rad(self.cl.spreadShotSpread*2), up) * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
				else
					sm.projectile.projectileAttack( projectile, damage, firePos, dir * fireMode.fireVelocity, owner, fakePosition, fakePositionSelf )
				end
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

			--,coinThrow = { "spudgun_coin_throw", { nextAnimation = "idle" } },
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
				sprintIdle = { "spudgun_sprint_idle", { looping = true } }

				--,coinThrow = { "spudgun_coin_throw", { nextAnimation = "idle" } },
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
end

function PotatoRifle.client_onEquip( self, animate )
	if self.isLocal then
		self.network:sendToServer("sv_changeColour", self.cl.mod)
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

function PotatoRifle.client_onUnequip( self, animate )
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

function PotatoRifle.sv_n_onAim( self, aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function PotatoRifle.cl_n_onAim( self, aiming )
	if not self.isLocal and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function PotatoRifle.onAim( self, aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

function PotatoRifle.sv_n_onShoot( self )
	self.network:sendToClients( "cl_n_onShoot" )
end

function PotatoRifle.cl_n_onShoot( self )
	if not self.isLocal and self.tool:isEquipped() then
		self:onShoot()
	end
end

function PotatoRifle.onShoot( self )
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

function PotatoRifle.cl_onPrimaryUse( self, state )
	if self.tool:getOwner().character == nil or self.cl.useCD.active then
		return
	end

	if self.fireCooldownTimer <= 0.0 and state == sm.tool.interactState.start and (mods[self.cl.mod].name ~= "Charged Burst" or self.cl.blastCharge == 0) then
		self:cl_shoot()
	end
end

function PotatoRifle.cl_onSecondaryUse( self, state )
	local name = mods[self.cl.mod].name
	if name ~= "Sniper" and name ~= "Spread Shot" then
		if state == 1 then
			if name == "Coins" and self.cl.coin.ammo > 0 then
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

	local aiming = state == 1 or state == 2
	if aiming ~= self.aiming then
		self.aiming = aiming
		self.tpAnimations.animations.idle.time = 0

		self:onAim( self.aiming )
		self.tool:setMovementSlowDown( self.aiming )
		self.network:sendToServer( "sv_n_onAim", self.aiming )
	end
end

function PotatoRifle.client_onEquippedUpdate( self, primaryState, secondaryState, forceBuild )
	self:cl_onEquippedUpdate( primaryState, secondaryState, forceBuild, false, nil )

	if (self.cl.secState == 1 or self.cl.secState == 2) and not self.cl.useCD.active then
		local name = mods[self.cl.mod].name
		if name == "Sniper" then
			sm.gui.setProgressFraction( self.fireCooldownTimer/sniperShotFireCooldown )
		elseif name == "Charged Burst" and not self.cl.blasting then
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
