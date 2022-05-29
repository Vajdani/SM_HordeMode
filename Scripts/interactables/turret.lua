Turret = class()

local fireRate = 10
local Damage = 20
local fireForce = 130
local ammoTransferAmount = 50
local turretUUID = sm.uuid.new("bb314cd5-38bc-4b46-9fb7-0e7347bed62c")

function Turret:server_onCreate()
    self.sv = self.storage:load() or {}
    self.sv.data = self.interactable:getPublicData()

    self.sv.stats = {
        hp = 250, maxhp = 250,
        ammo = 500, maxAmmo = 500
    }

    --self.shape:getBody():setDestructable( false )

    self.sv.fireTimer = Timer()
    self.sv.fireTimer:start( fireRate )

    --self.storage:save( self.sv )
    self.network:setClientData( self.sv )
end

function Turret:server_onRefresh()
    self.network:setClientData( self.sv )
end

function Turret:server_onDestroy()
    sm.container.beginTransaction()
    local player = self.sv.data.owner
	local inv = sm.game.getLimitedInventory() and player:getInventory() or player:getHotbar()
    sm.container.spend(inv, turretUUID, 1)
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
    print("a")
	self:sv_takeDamage(destructionLevel * 2, nil)
end

function Turret.sv_takeDamage( self, damage, source )
	if self.sv.data.owner == source or not g_pvp and type(source) == "Player" then return end

	self.sv.stats.hp = math.max( self.sv.stats.hp - damage, 0 )

	print( "Turret took damage:", damage)

	self.network:setClientData( self.sv )
    --self.storage:save( self.sv )
end

function Turret:server_onFixedUpdate( dt )
    local shapePos = self.shape:getWorldPosition()
    local target = self:sv_findTarget( shapePos )

    if target == nil or self.sv.stats.ammo == 0 then
        self.sv.fireTimer:reset()
        return
    end

    self.sv.fireTimer:tick()
    if self.sv.fireTimer:done() then
        self.sv.fireTimer:start( fireRate )
        self.sv.stats.ammo = self.sv.stats.ammo - 1

        local firePos = shapePos + g_up
        local dir = sm.projectile.solveBallisticArc( firePos, target:getWorldPosition(), fireForce, 10 ):normalize()
        sm.projectile.shapeProjectileAttack( projectile_potato, Damage, g_up, dir * fireForce, self.shape )

        self.network:setClientData( self.sv )
    end
end

function Turret:sv_findTarget( shapePos )
    local enemies = sm.unit.getAllUnits()
    if #enemies == 0 then return nil end

    local body = self.shape:getBody()
    local closest = enemies[1]
    local target = nil
    local minDistance = (closest:getCharacter():getWorldPosition() - shapePos):length2()
    for v, k in pairs(enemies) do
        local new = k
        local newsChar = new:getCharacter()
        local newsPos = newsChar:getWorldPosition()
        if (newsPos - shapePos):length2() <= minDistance then
            local hit, result = sm.physics.raycast(shapePos, newsPos, body, sm.physics.filter.character)
            if hit and result:getCharacter() == newsChar then
                target = newsChar
            end
        end
    end

    return target
end

function Turret:sv_transferAmmo( args )
    sm.container.beginTransaction()
    sm.container.spend( args.inv, obj_plantables_potato, args.amount )
    sm.container.endTransaction()

    self.sv.stats.ammo = self.sv.stats.ammo + args.amount
    self.network:setClientData( self.sv )
    --self.storage:save( self.sv )
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

function Turret:client_canInteract()
    local o1 = "<p textShadow='false' bg='gui_keybinds_bg_orange' color='#4f4f4f' spacing='9'>"
    local o2 = "</p>"

    sm.gui.setInteractionText("", o1.."Delete Turret"..o2, "reclaim Gatling Gun")

    local inv = sm.game.getLimitedInventory() and sm.localPlayer.getInventory() or sm.localPlayer.getHotbar()
    local ammo = self:cl_getTransferrableAmmo( inv )
    local transferText = (self.cl.stats.ammo == self.cl.stats.maxAmmo or ammo == 0) and "#ff0000Can't transfer any potatoes!" or string.format("Transfer #df7f00%d #ffffffpotatoes", ammo)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding( "Use", true), transferText)

    return self.cl.stats.ammo ~= self.cl.stats.maxAmmo
end

function Turret:client_onInteract( char, state )
    if not state then return end

    local inv = sm.game.getLimitedInventory() and sm.localPlayer.getInventory() or sm.localPlayer.getHotbar()
    local ammo = self:cl_getTransferrableAmmo( inv )
    if ammo > 0 then
        self.network:sendToServer("sv_transferAmmo",
            {
                inv = inv,
                amount = ammo
            }
        )
    end
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

    local ammoText = self.cl.stats.ammo == 0 and "OUT OF POTATOES" or tostring(self.cl.stats.ammo)
    self.cl.gui:setText("Text", string.format("Health:#df7f00 %d\n#ffffffAmmo:#df7f00 %s", self.cl.stats.hp, ammoText ))

    self.cl.gui:setWorldPosition(self.shape:getWorldPosition() + sm.vec3.new(0,0,1), self.shape:getBody():getWorld() )
end

function Turret:client_onDestroy()
    if self.cl.data.owner ~= sm.localPlayer.getPlayer() then return end

    self.cl.gui:close()
    self.cl.gui:destroy()
end

function Turret:cl_getTransferrableAmmo( inv )
    local totalQuantity = sm.container.totalQuantity( inv, obj_plantables_potato )
    local amount = ammoTransferAmount
    if not inv:canSpend( obj_plantables_potato, ammoTransferAmount ) then
        amount = totalQuantity
    end

    return self.cl.stats.ammo + amount > self.cl.stats.maxAmmo and amount - math.abs(self.cl.stats.ammo + amount - self.cl.stats.maxAmmo) or amount
end