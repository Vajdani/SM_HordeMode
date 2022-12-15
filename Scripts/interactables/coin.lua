---@class Coin : ShapeClass
Coin = class()

function Coin:server_onCreate()
    self.id = #g_coins + 1
    g_coins[self.id] = self.shape
end

function Coin:server_onCollision( other, position, selfPointVelocity, otherPointVelocity, normal )
    self.shape:destroyShape()
end

function Coin:sv_onHit( ignoreCoin )
    local objectToShoot
    local shape = self.shape
    local shapePos = shape.worldPosition
    local units = sm.unit.getAllUnits()

    if #g_coins > 1 then
        local minDistance = nil
        for v, coin in pairs(g_coins) do
            if coin ~= shape and coin ~= ignoreCoin and sm.exists(coin) then
                local otherCoinPos = coin.worldPosition
                local distance = otherCoinPos - shapePos
                local hit, result = sm.physics.raycast(shapePos, otherCoinPos)

                if hit and result:getShape() == coin and (minDistance == nil or distance:length2() < minDistance:length2()) then
                    minDistance = distance
                    objectToShoot = coin
                end
            end
        end

        if objectToShoot ~= nil then
            local interactable = objectToShoot.interactable
            local selfData = shape.interactable.publicData
            selfData.level = selfData.level + 1
            interactable:setPublicData( selfData )
            sm.event.sendToInteractable( interactable, "sv_onHit", shape )
        end
    elseif #units > 0 then
        local minDistance = nil
        for v, unit in pairs(units) do
            local char = unit.character
            local otherCharPos = char.worldPosition
            local distance = otherCharPos - shapePos
            local hit, result = sm.physics.raycast(shapePos, otherCharPos)

            if hit and result:getCharacter() == char and (minDistance == nil or distance:length2() < minDistance:length2()) then
                minDistance = distance
                objectToShoot = char
            end
        end

        if objectToShoot ~= nil then
            local selfData = shape.interactable.publicData
            sm.event.sendToUnit(objectToShoot:getUnit(), "sv_horde_takeDamage", { damage = selfData.damage * selfData.level, impact = sm.vec3.one(), hitpos = objectToShoot.worldPosition } )
        end
    end

    --local printObj = objectToShoot == nil and shape.interactable.publicData or objectToShoot
    --print("I have been hit! The coin I hit is:", printObj)

    if objectToShoot ~= nil then
        local pos = type(objectToShoot) == "Unit" and objectToShoot.character.worldPosition or objectToShoot.worldPosition
        local dir = pos - shapePos
        local scale = dir:length() * 4
        sm.event.sendToWorld(
            shape.body:getWorld(),
            "sv_onHitscanShot",
            {
                pos = shapePos + dir * (scale / 16),
                dir = dir,
                scale = scale
            }
        )
    end

    shape:destroyShape()
end

function Coin:server_onFixedUpdate( dt )
    if self.shape.worldPosition.z < 0 then
        self.shape:destroyShape()
    end
end

function Coin:server_onDestroy()
    g_coins[self.id] = nil
end