Detector = class()

local meathookConsumeActions = {
    sm.interactable.actions.forward,
    sm.interactable.actions.backward,
    sm.interactable.actions.left,
    sm.interactable.actions.right,
    sm.interactable.actions.jump
}

function Detector:server_onCreate()
    self.sv = {}
    self.sv.ignoredPlayers = {}
end

function Detector:server_onFixedUpdate()
    local int = self.shape:getInteractable()
    for v, player in pairs(sm.player.getAllPlayers()) do
        local char = player.character
        if char ~= nil then
            local ignored = isAnyOf(player, self.sv.ignoredPlayers)
            local locked = char:getLockingInteractable() == int
            if not locked and not ignored then
                char:setLockingInteractable(int)
            elseif locked and ignored then
                char:setLockingInteractable(nil)
            end
        end
    end
end

function Detector:sv_manageIgnoredPlayer( player )
    local present = isAnyOf(player, self.sv.ignoredPlayers)
    if not present then
        table.insert(self.sv.ignoredPlayers, player)
        print("G_INPUTMANAGER: Ignored player added:", player)
    elseif present then
        for v, k in pairs(self.sv.ignoredPlayers) do
            if k == player then
                table.remove(self.sv.ignoredPlayers, v)
            end
        end
        print("G_INPUTMANAGER: Ignored player removed:", player)
    end

    sm.event.sendToPlayer(player, "sv_queueMsg", "Advanced movement: #df7f00"..(present and "ON" or "OFF"))
end

function Detector:client_onAction( action, state )
    local player = sm.localPlayer.getPlayer()
    local publicData = player:getClientPublicData()
    publicData.input[action] = state

    local consume = false
    if isAnyOf(action, meathookConsumeActions) and publicData.meathookState then consume = true end

    return consume
end