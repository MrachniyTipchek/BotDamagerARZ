local arzev = require("arizona-events")
local vector3d = require('vector3d')

local CustomBotPool = {}
local targetBotId = nil
local isAttackingSingle = false
local isAttackingAll = false
local attackDelay = 100

local font = renderCreateFont('Arial', 10, 5)
local wallhack = false

function main()
    while not isSampAvailable() do wait(0) end
    
    sampAddChatMessage("----- Arizona Bot Damager -----", -1)
    sampAddChatMessage("/botwh - Show bots", -1)
    sampAddChatMessage("/dmall - Damage all bots", -1)
    sampAddChatMessage("/dm [id] - Toggle attack on bot", -1)
    sampAddChatMessage("/alldmg - Toggle attack on all bots", -1)

    sampRegisterChatCommand('botwh', function()
        wallhack = not wallhack
        sampAddChatMessage('Bot wallhack: ' .. (wallhack and 'ON' or 'OFF'), -1)
    end)

    sampRegisterChatCommand('dmall', function()
        for id, _ in pairs(CustomBotPool) do
            sendDamage(id, true)
        end
        sampAddChatMessage('Damaged all bots', -1)
    end)

    sampRegisterChatCommand('dm', function(param)
        local id = tonumber(param)
        if not id then
            sampAddChatMessage("Usage: /dm [bot id]", -1)
            return
        end
        
        if isAttackingSingle and targetBotId == id then
            isAttackingSingle = false
            sampAddChatMessage(("Attack stopped: [%d]"):format(id), -1)
            return
        end
        
        if isAttackingAll then
            isAttackingAll = false
            sampAddChatMessage("Global attack stopped", -1)
        end
        
        targetBotId = id
        isAttackingSingle = true
        sampAddChatMessage(("Attacking bot: [%d]"):format(id), -1)
        
        lua_thread.create(function()
            while isAttackingSingle and CustomBotPool[targetBotId] do
                sendDamage(targetBotId, true)
                wait(attackDelay)
            end
            isAttackingSingle = false
        end)
    end)

    sampRegisterChatCommand('alldmg', function()
        isAttackingAll = not isAttackingAll
        if isAttackingAll then
            isAttackingSingle = false
            sampAddChatMessage("Attacking all bots", -1)
            
            lua_thread.create(function()
                while isAttackingAll do
                    for id, _ in pairs(CustomBotPool) do
                        if not isAttackingAll then break end
                        sendDamage(id, true)
                        wait(attackDelay)
                    end
                    wait(50)
                end
            end)
        else
            sampAddChatMessage("Attack stopped", -1)
        end
    end)

    while true do
        wait(0)
        if wallhack then
            for id, bot in pairs(CustomBotPool) do
                if bot.position and isPointOnScreen(bot.position.x, bot.position.y, bot.position.z, 0) then
                    local x, y = convert3DCoordsToScreen(bot.position.x, bot.position.y, bot.position.z)
                    local tag = ("[%d]"):format(id)
                    local len = renderGetFontDrawTextLength(font, tag)
                    renderFontDrawText(font, tag, x - len/2, y, 0xFFFFFFFF)
                    
                    if id == targetBotId then
                        renderDrawBox(x - 15, y - 5, 30, 2, 0xFF00FF00, 0x5000FF00)
                    end
                end
            end
        end
    end
end

function addCustomBot(id)
    CustomBotPool[id] = {
        modelId = -1,
        position = vector3d(0,0,0),
        heading = 0,
        health = 0,
        armour = 0,
        nametag1 = {color = 0, text = 'Bot'},
        nametag2 = {color = 0, text = ''},
    }
end

function sendDamage(id, silent)
    if not CustomBotPool[id] then return end
    
    local x, y, z = getCharCoordinates(PLAYER_PED)
    local weapon = getCurrentCharWeapon(PLAYER_PED)
    local data = samp_create_sync_data('bullet')
    
    data.targetType = 0
    data.targetId = -1
    data.origin = vector3d(x, y, z)
    data.target = vector3d(x, y - 1, z)
    data.center = vector3d(x, y - 1, z)
    data.weaponId = weapon
    
    data:send()
    
    arzev.send('onArizonaSendBotDamage', {
        give_or_take = true,
        bot_id = id,
        damage = 999999,
        weapon = weapon,
        bodypart = 6,
        _unknown = 0,
        player_id = select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))
    })
    
    if not silent then
        sampAddChatMessage(("Damaged bot: [%d]"):format(id), -1)
    end
end

function arzev.onArizonaSendBotOnfootSync(packet)
    if not CustomBotPool[packet.bot_id] then
        addCustomBot(packet.bot_id)
    end
    CustomBotPool[packet.bot_id].position = packet.position
    CustomBotPool[packet.bot_id].heading = packet.heading
end

function arzev.onArizonaBotStreamIn(packet)
    if not CustomBotPool[packet.bot_id] then
        addCustomBot(packet.bot_id)
    end
    CustomBotPool[packet.bot_id].modelId = packet.model_id
    CustomBotPool[packet.bot_id].position = packet.position
    CustomBotPool[packet.bot_id].heading = packet.rotation
    CustomBotPool[packet.bot_id].health = packet.health
    CustomBotPool[packet.bot_id].armour = packet.armour
    CustomBotPool[packet.bot_id].nametag1 = packet.nametag_1
    CustomBotPool[packet.bot_id].nametag2 = packet.nametag_2
end

function arzev.onArizonaBotStreamOut(packet)
    CustomBotPool[packet.bot_id] = nil
end

function arzev.onArizonaDestroyBot(packet)
    CustomBotPool[packet.bot_id] = nil
end

function arzev.onArizonaSetBotPos(packet)
    if not CustomBotPool[packet.bot_id] then
        addCustomBot(packet.bot_id)
    end
    CustomBotPool[packet.bot_id].position = packet.position
end

function arzev.onArizonaBotHealthSync(packet)
    if not CustomBotPool[packet.bot_id] then
        addCustomBot(packet.bot_id)
    end
    CustomBotPool[packet.bot_id].health = packet.health
    CustomBotPool[packet.bot_id].armour = packet.armour
end

function arzev.onArizonaBotPassengerSync(packet)
    if not CustomBotPool[packet.bot_id] then
        addCustomBot(packet.bot_id)
    end
    local res, car = sampGetCarHandleBySampVehicleId(packet.vehicle_id)
    if res then
        local _, x, y, z = getCarCoordinates(car)
        CustomBotPool[packet.bot_id].position = vector3d(x, y, z)
        CustomBotPool[packet.bot_id].health = packet.health
        CustomBotPool[packet.bot_id].armour = packet.armour
    end
end

function onReceivePacket(id, bs)
    if id == 34 then
        CustomBotPool = {}
    end
end

function samp_create_sync_data(sync_type, copy_from_player)
    local ffi = require 'ffi'
    local sampfuncs = require 'sampfuncs'
    local raknet = require 'samp.raknet'
    require 'samp.synchronization'

    copy_from_player = copy_from_player or true
    local sync_traits = {
        player = {'PlayerSyncData', raknet.PACKET.PLAYER_SYNC, sampStorePlayerOnfootData},
        vehicle = {'VehicleSyncData', raknet.PACKET.VEHICLE_SYNC, sampStorePlayerIncarData},
        passenger = {'PassengerSyncData', raknet.PACKET.PASSENGER_SYNC, sampStorePlayerPassengerData},
        aim = {'AimSyncData', raknet.PACKET.AIM_SYNC, sampStorePlayerAimData},
        trailer = {'TrailerSyncData', raknet.PACKET.TRAILER_SYNC, sampStorePlayerTrailerData},
        unoccupied = {'UnoccupiedSyncData', raknet.PACKET.UNOCCUPIED_SYNC, nil},
        bullet = {'BulletSyncData', raknet.PACKET.BULLET_SYNC, nil},
        spectator = {'SpectatorSyncData', raknet.PACKET.SPECTATOR_SYNC, nil}
    }
    local sync_info = sync_traits[sync_type]
    local data_type = 'struct ' .. sync_info[1]
    local data = ffi.new(data_type, {})
    local raw_data_ptr = tonumber(ffi.cast('uintptr_t', ffi.new(data_type .. '*', data)))
    if copy_from_player then
        local copy_func = sync_info[3]
        if copy_func then
            local _, player_id
            if copy_from_player == true then
                _, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            else
                player_id = tonumber(copy_from_player)
            end
            copy_func(player_id, raw_data_ptr)
        end
    end
    local func_send = function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, sync_info[2])
        raknetBitStreamWriteBuffer(bs, raw_data_ptr, ffi.sizeof(data))
        raknetSendBitStreamEx(bs, sampfuncs.HIGH_PRIORITY, sampfuncs.UNRELIABLE_SEQUENCED, 1)
        raknetDeleteBitStream(bs)
    end
    local mt = {
        __index = function(t, index)
            return data[index]
        end,
        __newindex = function(t, index, value)
            data[index] = value
        end
    }
    return setmetatable({send = func_send}, mt)
end