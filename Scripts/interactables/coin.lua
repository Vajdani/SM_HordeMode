Coin = class()

function Coin:server_onCreate()
    table.insert(g_coins, self.shape)
end

function Coin:server_onCollision( other, position, selfPointVelocity, otherPointVelocity, normal )
    self.shape:destroyShape( 0 )
end

function Coin:sv_onHit()
    local objectToShoot
    local shapePos = self.shape:getWorldPosition()
    local units = sm.unit.getAllUnits()

    if #g_coins > 1 then
        local minDistance = sm.vec3.new(1000,1000,1000)
        for v, coin in pairs(g_coins) do
            if coin ~= self.shape and sm.exists(coin) then
                local otherCoinPos = coin:getWorldPosition()
                local distance = otherCoinPos - shapePos
                local hit, result = sm.physics.raycast(shapePos, otherCoinPos)

                if hit and result:getShape() == coin and distance:length() < minDistance:length() then
                    minDistance = distance
                    objectToShoot = coin
                end
            end
        end

        if objectToShoot ~= nil then
            local interactable = objectToShoot:getInteractable()
            local selfData = self.shape:getInteractable():getPublicData()
            selfData.level = selfData.level + 1
            interactable:setPublicData( selfData )
            sm.event.sendToInteractable( interactable, "sv_onHit" )
        end
    elseif #units > 0 then
        local minDistance = sm.vec3.new(1000,1000,1000)
        for v, unit in pairs(units) do
            local char = unit:getCharacter()
            local otherCharPos = char:getWorldPosition()
            local distance = otherCharPos - shapePos
            local hit, result = sm.physics.raycast(shapePos, otherCharPos)

            if hit and result:getCharacter() == char and distance:length() < minDistance:length() then
                minDistance = distance
                objectToShoot = char
            end
        end

        if objectToShoot ~= nil then
            local selfData = self.shape:getInteractable():getPublicData()
            sm.event.sendToUnit(objectToShoot:getUnit(), "sv_horde_takeDamage", { damage = selfData.damage * selfData.level, impact = sm.vec3.one(), hitpos = objectToShoot:getWorldPosition() } )
        end
    end

    local printObj = objectToShoot == nil and self.shape:getInteractable():getPublicData() or objectToShoot
    print("I have been hit! The coin I hit is:", printObj)

    if objectToShoot ~= nil then
        local pos = type(objectToShoot) == "Unit" and objectToShoot:getCharacter():getWorldPosition() or objectToShoot:getWorldPosition()
        local dir = (pos - shapePos)
        local scale = dir:length() * 4
        sm.event.sendToWorld(self.shape:getBody():getWorld(), "sv_onHitscanShot", { pos = shapePos + dir * (scale / 16), dir = dir, scale = scale } )
    end

    self.shape:destroyShape( 0 )
end

function Coin:server_onFixedUpdate( dt )
    if self.shape:getWorldPosition().z < 0 then
        self.shape:destroyShape( 0 )
    end
end