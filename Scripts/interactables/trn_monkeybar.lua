MonkeyBar = class()

function MonkeyBar:server_onCreate()
    self.swingBoost = sm.vec3.new(1000, 1000, 1100)
    self.swingArea = sm.areaTrigger.createAttachedBox(
            self.interactable,
            sm.vec3.new(0.5,0.5,1),
            sm.vec3.new(0,0,1),
            sm.quat.identity(),
            sm.areaTrigger.filter.character
        )
    self.swingArea:bindOnEnter("sv_applyBoost")
end

function MonkeyBar:sv_applyBoost(trigger, result)
    for _, char in ipairs(result) do
        if char:isPlayer() then
            local boostDir = char:getDirection()


            sm.physics.applyImpulse(char, sm.vec3.new( 1000 * boostDir.x, 1000 * boostDir.y, redirectVel( "z", 1100, char ).z ) )
            self.network:sendToClient(char:getPlayer(), "cl_playAudio")
        end
    end
end

function MonkeyBar:cl_playAudio()
    sm.audio.play("Handbook - Open")
end

function redirectVel( axis, value, char )
    if axis == "x" then
        return sm.vec3.new( char:getVelocity().x * -1 * char:getMass() + value, 0, 0 )
    elseif axis == "y" then
        return sm.vec3.new( 0, char:getVelocity().y * -1 * char:getMass() + value, 0 )
    elseif axis == "z" then
        return sm.vec3.new( 0, 0, char:getVelocity().z * -1 * char:getMass() + value )
    end
end