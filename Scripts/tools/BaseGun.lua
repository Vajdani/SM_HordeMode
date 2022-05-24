BaseGun = class()

function BaseGun.cl_create( self, mods )
    function self:cl_blockModWheel()
        self.cl.blockModWheel = true
    end

    function self:cl_modWheelClick( button )
        self.cl.mod = tonumber(button:sub(4,4))
	    sm.audio.play("PaintTool - ColorPick")
        self.network:sendToServer("sv_changeColour", self.cl.mod)
        self:cl_setWpnModGui()

        self.cl.modWheel:close()
        self.cl.blockModWheel = true
    end

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
    for i = 1, 4 do
        local btn = "btn"..i
        if i <= #mods then
            self.cl.modWheel:setButtonCallback(btn, "cl_modWheelClick")
            self.cl.modWheel:setColor("img"..i, mods[i].fpCol)
        else
            self.cl.modWheel:setVisible(btn, false)
        end
    end
    self.cl.blockModWheel = false

    self.cl.modWheel:setOnCloseCallback("cl_blockModWheel")
end

function BaseGun.cl_fixedUpdate( self )
    local clientData = sm.localPlayer.getPlayer():getClientPublicData()
	if clientData == nil then return true end

    local wheelBindActive = clientData.input[sm.interactable.actions.zoomOut]
	local wheelActive = self.cl.modWheel:isActive()
	if wheelBindActive and not wheelActive and not self.cl.blockModWheel then
		self.cl.modWheel:open()
	elseif not wheelBindActive then
		if wheelActive then
			self.cl.modWheel:close()
		end

		self.cl.blockModWheel = false
	end
end