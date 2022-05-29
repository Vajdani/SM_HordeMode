Turret = class()

function Turret:server_onCreate()
    self.sv = self.storage:load() or {}
    self.sv.data = self.interactable:getPublicData()

    self.sv.stats = {
        hp = 250, maxhp = 250,
        ammo = 500, maxAmmo = 500
    }

    --self.shape:getBody():setDestructable( false )

    self.storage:save( self.sv )
    self.network:setClientData( self.sv )
end

function Turret:server_onRefresh()
    self.network:setClientData( self.sv )
end

function Turret:server_onDestroy()
    sm.container.beginTransaction()
    local player = self.sv.data.owner
	local inv = sm.game.getLimitedInventory() and player:getInventory() or player:getHotbar()
	sm.container.collect(inv, g_gatling, 1)
	sm.container.endTransaction()
end

function Turret.server_onProjectile( self, position, airTime, velocity, projectileName, attacker, damage, customData, normal, uuid )
	self:sv_takeDamage(damage, attacker)
end

function Turret.server_onMelee( self, position, attacker, damage, power, direction, normal )
	self:sv_takeDamage(damage, attacker)
end

function Turret.server_onExplosion( self, center, destructionLevel )
	self:sv_takeDamage(destructionLevel * 2, nil)
end

function Turret.sv_takeDamage( self, damage, source )
	if self.sv.data.owner == source or not g_pvp and type(source) == "Player" then return end

	self.sv.stats.hp = math.max( self.sv.stats.hp - damage, 0 )

	print( "Turret took damage:", damage)

	self.network:setClientData( self.sv )
    self.storage:save( self.sv )
end



function Turret:client_onCreate()
    self.cl = {}
    self.cl.data = {}
    self.cl.stats = {}
end

function Turret:client_canErase()
    if self.cl.data.owner ~= sm.localPlayer.getPlayer() then
        sm.gui.displayAlertText("You're not the owner of this turret!")
        sm.audio.play("RaftShark")
        return false
    end

    return true
end

function Turret:client_onClientDataUpdate( data, channel )
    self.cl.data = data.data
    self.cl.stats = data.stats
end

function Turret:client_onFixedUpdate( dt )
    if self.cl.data.owner ~= sm.localPlayer.getPlayer() then return end

    if not self.cl.gui then
        self.cl.gui = sm.gui.createNameTagGui()
        self.cl.gui:setRequireLineOfSight( false )
        self.cl.gui:setMaxRenderDistance( 10000 )
        self.cl.gui:open()
    end

    self.cl.gui:setText("Text", string.format("Health:#df7f00 %d\n#ffffffAmmo:#df7f00 %d", self.cl.stats.hp, self.cl.stats.ammo ))

    self.cl.gui:setWorldPosition(self.shape:getWorldPosition() + sm.vec3.new(0,0,1), self.shape:getBody():getWorld() )
end

function Turret:client_onDestroy()
    if self.cl.data.owner ~= sm.localPlayer.getPlayer() then return end

    self.cl.gui:close()
    self.cl.gui:destroy()
end