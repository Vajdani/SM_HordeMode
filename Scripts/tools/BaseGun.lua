---@class Timer
---@field ticks number
---@field count number
---@field start function
---@field stop function
---@field reset function
---@field tick function


---@class BaseGun : ToolClass
---@field cl_blockModWheel function
---@field cl_modWheelClick function
---@field cl_setWpnModGui function
---@field cl_convertToUseCol function
---@field cl_create function
---@field cl_fixedUpdate function
---@field cl_onEquippedUpdate function
---@field cl_reload function
---@field loadAnimations function
---@field cl table
---@field tpAnimations table
---@field fpAnimations table
---@field aimFireMode table
---@field normalFireMode table
---@field aiming boolean
---@field equipped boolean
---@field wantEquipped boolean
---@field isLocal boolean
---@field movementDispersion number
---@field sprintCooldown number
---@field shootEffect Effect
---@field shootEffectFP Effect
---@field blendTime number
---@field aimBlendSpeed number
---@field fireCooldownTimer number
BaseGun = class()

function BaseGun.cl_create( self, mods, useCD )
    function self:cl_blockModWheel()
        self.cl.blockModWheel = true
    end

    function self:cl_modWheelClick( button )
        self.cl.mod = tonumber(button:sub(4,4))
	    sm.audio.play("PaintTool - ColorPick")

        local sent = self.cl.uuid == g_shotgun and { self.cl.mod, self.cl.pumpCount } or self.cl.mod
        self.network:sendToServer("sv_changeColour", sent )
        self:cl_setWpnModGui()

        self.cl.modWheel:close()
        self.cl.blockModWheel = true
    end

    function self:cl_convertToUseCol()
        local mod = self.cl.weaponMods[self.cl.mod]
        local function brighten( colour )
            return sm.color.new( colour.r * 2, colour.g * 2, colour.b * 2 )
        end

        return brighten(mod.fpCol), brighten(mod.tpCol)
    end

    self.cl.weaponMods = mods
    self.cl.modWheel = sm.gui.createGuiFromLayout( "$CONTENT_DATA/Gui/modWheel.layout", false,
        {
            isHud = false,
            isInteractive = true,
            needsCursor = true,
            hidesHotbar = false,
            isOverlapped = false,
            backgroundAlpha = 0.0,
        }
    )
    self.cl.modWheel:setOnCloseCallback("cl_blockModWheel")

    for i = 1, 6 do
        local btn = "btn"..i
        if i <= #mods then
            self.cl.modWheel:setButtonCallback(btn, "cl_modWheelClick")
            self.cl.modWheel:setColor("img"..i, mods[i].fpCol)
        else
            self.cl.modWheel:setVisible(btn, false)
        end
    end
    self.cl.blockModWheel = false

    self.cl.useCD = {}
	self.cl.useCD.active = false
	self.cl.useCD.cd = useCD
    self.cl.useCD.max = useCD
end

function BaseGun.cl_fixedUpdate( self )
    if self.cl.useCD.active then
		self.cl.useCD.cd = self.cl.useCD.cd - 1
		if self.cl.useCD.cd <= 0 then
			self.cl.useCD.active = false
			self.cl.useCD.cd = self.cl.useCD.max
		end
	end

    local clientData = sm.localPlayer.getPlayer():getClientPublicData()
	if clientData == nil then return true end

    --[[local wheelBindActive = clientData.input[sm.interactable.actions.zoomOut]
	local wheelActive = self.cl.modWheel:isActive()
	if wheelBindActive and not wheelActive and not self.cl.blockModWheel then
		self.cl.modWheel:open()
	elseif not wheelBindActive then
		if wheelActive then
			self.cl.modWheel:close()
		end

		self.cl.blockModWheel = false
	end]]
end

function BaseGun.cl_onEquippedUpdate( self, mouse0, mouse1, f, cdVisCheck, mod )
    self.cl.primState = mouse0
	self.cl.secState = mouse1

    if self.cl.useCD.active and ( not cdVisCheck or self.cl.weaponMods[self.cl.mod].name == mod) then
		sm.gui.setProgressFraction( self.cl.useCD.cd/self.cl.useCD.max )
    end

    if self.cl.weaponMods[self.cl.mod].name ~= "Pump" then
        if mouse1 == 1 then
            self.network:sendToServer("sv_changeColour", "secUse_start")
        elseif mouse1 == 3 then
            self.network:sendToServer("sv_changeColour", self.cl.uuid == g_shotgun and { self.cl.mod, self.cl.pumpCount } or self.cl.mod)
        end
    end
end

function BaseGun.cl_equip( self, renderablesTp, renderablesFp, renderables )
    local currentRenderablesTp = {}
	local currentRenderablesFp = {}
	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do
		currentRenderablesTp[#currentRenderablesTp+1] = v
		currentRenderablesFp[#currentRenderablesFp+1] = v
	end

	self.tool:setTpRenderables( currentRenderablesTp )
	if self.isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
	end

	self:loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function BaseGun:cl_reload()
    local mods = self.cl.weaponMods
    self.cl.mod = self.cl.mod == #mods and 1 or self.cl.mod + 1
	sm.event.sendToPlayer(
        sm.localPlayer.getPlayer(),
        "cl_queueMsg",
        "#ffffffCurrent weapon mod: #df7f00"..mods[self.cl.mod].name
    )
	sm.audio.play("PaintTool - ColorPick")

	self.network:sendToServer(
        "sv_changeColour",
        self.cl.uuid == g_shotgun and { self.cl.mod, self.cl.pumpCount } or self.cl.mod
    )
	self:cl_setWpnModGui()
end

function BaseGun.calculateFirePosition( self )
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

function BaseGun.calculateTpMuzzlePos( self )
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

---@return Vec3
function BaseGun.calculateFpMuzzlePos( self )
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

	---@type Vec3
	local pos = self.tool:getFpBonePos( "pejnt_barrel" )
	return pos + sm.vec3.lerp( muzzlePos45, muzzlePos90, fovScale )
end