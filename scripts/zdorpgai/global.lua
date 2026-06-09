-- ZDORPG Global Script
-- Handles IPC polling, command dispatch, world state tracking

local core = require('openmw.core')
local types = require('openmw.types')
local util = require('openmw.util')
local vfs = require('openmw.vfs')
local world = require('openmw.world')
local calendar = require('openmw_aux.calendar')

local ipc = require('scripts.zdorpgai.ipc')

-- State
local POLL_INTERVAL_FRAMES = 5
local frameCounter = 0
local playerInfoSent = false
local lastSeenClientMsgId = 0
local modMsgCounter = 0
local lastCellName = nil
local playerObject = nil
local saveId = nil
local activeNpcs = {}
local lastEquipment = {}
local clientConnected = false
local currentSessionId = nil

-------------------------------------------------------------------------------
-- Outgoing helpers
-------------------------------------------------------------------------------

local function publish(msgType, data)
    modMsgCounter = ipc.sendMessage(msgType, data, nil, modMsgCounter)
end

local function respond(msgType, responseTo, data)
    modMsgCounter = ipc.sendMessage(msgType, data, responseTo, modMsgCounter)
end

-------------------------------------------------------------------------------
-- Character info gathering
-------------------------------------------------------------------------------

local function getCharacterInfo(gameObject)
    local ok, record = pcall(types.NPC.record, gameObject)
    if not ok or not record then return nil end

    print("[ZDORPG-DEBUG] getCharacterInfo for " .. tostring(record.name) .. " | class=" .. tostring(record.class))

    -- Resolve faction and rank via documented OpenMW API
    local factionName = record.faction
    local factionRankName = nil
    if not factionName then
        local okF, factionIds = pcall(function() return types.NPC.getFactions(gameObject) end)
        if okF and factionIds and #factionIds > 0 then
            local fid = factionIds[1]
            local okR, fRec = pcall(function() return core.factions.records[fid] end)
            if okR and fRec then
                factionName = fRec.name
                local okRank, rankIndex = pcall(function() return types.NPC.getFactionRank(gameObject, fid) end)
                if okRank and rankIndex and fRec.ranks then
                    local rankRec = fRec.ranks[rankIndex + 1]
                    if rankRec then
                        factionRankName = rankRec.name
                    end
                end
            else
                factionName = fid
            end
        end
    end
    print("  resolved faction         = " .. tostring(factionName))
    print("  resolved rank            = " .. tostring(factionRankName))

    local health = types.Actor.stats.dynamic.health(gameObject)

    return {
        objectId = gameObject.recordId,
        name = record.name,
        race = record.race,
        sex = record.isMale and 'male' or 'female',
        className = record.class,
        faction = factionName,
        factionRank = factionRankName,
        level = record.level,
        isDead = types.Actor.isDead(gameObject),
        healthCurrent = health.current,
        healthMax = health.base,
    }
end

-------------------------------------------------------------------------------
-- Incoming message handlers
-------------------------------------------------------------------------------

local function handleGetPlayerInfo(msg)
    if not playerObject then
        respond('GetPlayerInfo', msg.id, { error = 'no_player' })
        return
    end
    local info = getCharacterInfo(playerObject)
    if not info then
        respond('GetPlayerInfo', msg.id, { error = 'info_failed' })
        return
    end

    -- Read actual dynamic stats from the player object
    local health = types.Actor.stats.dynamic.health(playerObject)
    local magicka = types.Actor.stats.dynamic.magicka(playerObject)
    local fatigue = types.Actor.stats.dynamic.fatigue(playerObject)
    local levelStat = types.Actor.stats.level(playerObject)

    local hpCur = health and health.current or 0
    local hpMax = health and health.base or 0
    local mgCur = magicka and magicka.current or 0
    local mgMax = magicka and magicka.base or 0
    local ftCur = fatigue and fatigue.current or 0
    local ftMax = fatigue and fatigue.base or 0
    local lvl = levelStat and levelStat.current or 0

    print("[ZDORPG-DEBUG] Player stats: name=" .. tostring(info.name) ..
          " level=" .. tostring(lvl) ..
          " hp=" .. tostring(hpCur) .. "/" .. tostring(hpMax) ..
          " mg=" .. tostring(mgCur) .. "/" .. tostring(mgMax) ..
          " ft=" .. tostring(ftCur) .. "/" .. tostring(ftMax))

    respond('GetPlayerInfo', msg.id, {
        objectId = info.objectId,
        name = info.name,
        race = info.race,
        sex = info.sex,
        class = info.className or "",
        level = lvl,
        healthCurrent = hpCur,
        healthMax = hpMax,
        magickaCurrent = mgCur,
        magickaMax = mgMax,
        fatigueCurrent = ftCur,
        fatigueMax = ftMax,
    })
end

local function handleGetNpcInfo(msg)
    local data = msg.data or {}
    if not data.npcId then
        respond('GetNpcInfo', msg.id, { error = 'missing_npcId' })
        return
    end
    local npc = activeNpcs[data.npcId]
    if not npc then
        respond('GetNpcInfo', msg.id, { error = 'not_found' })
        return
    end
    local info = getCharacterInfo(npc)
    if not info then
        respond('GetNpcInfo', msg.id, { error = 'info_failed' })
        return
    end
    respond('GetNpcInfo', msg.id, {
        objectId = info.objectId,
        name = info.name,
        race = info.race,
        sex = info.sex,
        className = info.className,
        faction = info.faction,
        level = info.level,
    })
end

local function handleSayMp3File(msg)
    local data = msg.data or {}
    local npc = activeNpcs[data.npcId]
    if not npc then
        print('[ZDORPG] SayMp3File: NPC not found in activeNpcs: ' .. tostring(data.npcId))
        return
    end
    print('[ZDORPG] SayMp3File: playing ' .. tostring(data.mp3Name) .. ' for ' .. tostring(data.npcId))
    local okSay, err = pcall(core.sound.say, 'Sound/zdorpgai_mp3/' .. data.mp3Name, npc, '')
    if not okSay then
        print('[ZDORPG] Error playing voice: ' .. tostring(err))
    end
    if playerObject and data.text and data.text ~= '' then
        local npcName = data.npcId or '???'
        local okRec, record = pcall(types.NPC.record, npc)
        if okRec and record then
            npcName = record.name
        end
        playerObject:sendEvent('ZdorpgShowSpeech', {
            npcName = npcName,
            text = data.text,
            animate = true,
            durationSec = data.durationSec,
        })
    end
end

local function handleSpeechRecognitionInProgress(msg)
    if not playerObject then return end
    local data = msg.data or {}
    playerObject:sendEvent('ZdorpgShowListening', {
        text = data.text or '',
    })
end

local function handleSpeechRecognitionComplete(msg)
    if not playerObject then return end
    local data = msg.data or {}
    playerObject:sendEvent('ZdorpgShowListening', {
        text = data.text or '',
    })
end

local function handlePlayerStartSpeak(msg)
    if playerObject then
        playerObject:sendEvent('ZdorpgShowListening', {})
    end
end

local function handlePlayerStopSpeak(msg)
    -- Don't hide listening here; let SpeechRecognitionComplete or the
    -- 4-second auto-hide timer handle it instead.
end

local function showConnectedIndicator()
    if playerObject then
        playerObject:sendEvent('ZdorpgNotify', { text = 'ZdoRPG connected' })
    end
end

local function handleGetCharactersWhoHear(msg)
    local data = msg.data or {}
    local characterId = data.characterId
    if not characterId then
        respond('GetCharactersWhoHear', msg.id, { characters = {} })
        return
    end

    -- Find the speaking character
    local speaker = nil
    if playerObject and playerObject.recordId == characterId then
        speaker = playerObject
    else
        speaker = activeNpcs[characterId]
    end

    if not speaker then
        respond('GetCharactersWhoHear', msg.id, { characters = {} })
        return
    end

    local okPos, speakerPos = pcall(function() return speaker.position end)
    if not okPos or not speakerPos then
        respond('GetCharactersWhoHear', msg.id, { characters = {} })
        return
    end

    local maxDistMeters = data.maxDistanceMeters or (2000 / 70)
    local maxDistUnits = maxDistMeters * 70
    local hearingRangeSq = maxDistUnits * maxDistUnits
    local characters = {}
    for id, npc in pairs(activeNpcs) do
        if id ~= characterId then
            local okDead, isDead = pcall(types.Actor.isDead, npc)
            if okDead and not isDead then
                local okNpc, npcPos = pcall(function() return npc.position end)
                if okNpc and npcPos then
                    local dx = npcPos.x - speakerPos.x
                    local dy = npcPos.y - speakerPos.y
                    local dz = npcPos.z - speakerPos.z
                    local distSq = dx*dx + dy*dy + dz*dz
                    if distSq < hearingRangeSq then
                        characters[#characters + 1] = { characterId = id, distanceMeters = math.sqrt(distSq) / 70 }
                    end
                end
            end
        end
    end

    table.sort(characters, function(a, b) return a.distanceMeters < b.distanceMeters end)
    respond('GetCharactersWhoHear', msg.id, { characters = characters })
end

local function handleSpawnOnGroundInFrontOfCharacter(msg)
    local data = msg.data or {}
    local npcId = data.npcId
    local itemId = data.itemId
    local count = data.count or 1

    if not npcId or not itemId then
        print('[ZDORPG] SpawnOnGround: missing npcId or itemId')
        return
    end

    local npc = activeNpcs[npcId]
    if not npc then
        print('[ZDORPG] SpawnOnGround: NPC not found: ' .. tostring(npcId))
        return
    end

    local okPos, npcPos = pcall(function() return npc.position end)
    if not okPos or not npcPos then
        print('[ZDORPG] SpawnOnGround: cannot get NPC position')
        return
    end

    local okRot, facing = pcall(function() return npc.rotation:getYaw() end)
    if not okRot then
        facing = 0
    end

    local spawnDistance = 70
    local spawnPos = util.vector3(
        npcPos.x + math.sin(facing) * spawnDistance,
        npcPos.y + math.cos(facing) * spawnDistance,
        npcPos.z
    )

    local okCreate, item = pcall(world.createObject, itemId, count)
    if not okCreate or not item then
        print('[ZDORPG] SpawnOnGround: failed to create ' .. tostring(itemId) .. ': ' .. tostring(item))
        return
    end

    local okBB, bb = pcall(function() return item:getBoundingBox() end)
    if okBB and bb then
        spawnPos = util.vector3(spawnPos.x, spawnPos.y, spawnPos.z + bb.halfSize.z)
    end

    local okTeleport, err = pcall(function()
        item:teleport(npc.cell, spawnPos)
    end)
    if not okTeleport then
        print('[ZDORPG] SpawnOnGround: failed to place object: ' .. tostring(err))
        return
    end

    print('[ZDORPG] Spawned ' .. tostring(count) .. 'x ' .. tostring(itemId) .. ' in front of ' .. tostring(npcId))
end

local function handlePlaySound3dOnCharacter(msg)
    local data = msg.data or {}
    local npcId = data.npcId
    local sound = data.sound

    if not npcId or not sound then
        print('[ZDORPG] PlaySound3d: missing npcId or sound')
        return
    end

    local npc = activeNpcs[npcId]
    if not npc then
        print('[ZDORPG] PlaySound3d: NPC not found: ' .. tostring(npcId))
        return
    end

    local ok, err = pcall(core.sound.playSound3d, sound, npc)
    if not ok then
        print('[ZDORPG] PlaySound3d: failed to play ' .. tostring(sound) .. ': ' .. tostring(err))
    end
end

local function handleNpcStartFollowCharacter(msg)
    local data = msg.data or {}
    local npcId = data.npcId
    local targetId = data.targetCharacterId

    if not npcId or not targetId then
        print('[ZDORPG] NpcStartFollow: missing npcId or targetCharacterId')
        return
    end

    local npc = activeNpcs[npcId]
    if not npc then
        print('[ZDORPG] NpcStartFollow: NPC not found: ' .. tostring(npcId))
        return
    end

    local target = activeNpcs[targetId]
    if not target then
        if playerObject and playerObject.recordId == targetId then
            target = playerObject
        else
            print('[ZDORPG] NpcStartFollow: target not found: ' .. tostring(targetId))
            return
        end
    end

    local ok, err = pcall(function()
        npc:sendEvent('RemoveAIPackages', 'Follow')
        npc:sendEvent('StartAIPackage', {type = 'Follow', target = target})
    end)
    if not ok then
        print('[ZDORPG] NpcStartFollow: failed: ' .. tostring(err))
        return
    end

    print('[ZDORPG] NPC ' .. tostring(npcId) .. ' now following ' .. tostring(targetId))
end

local function handleNpcStopFollowCharacter(msg)
    local data = msg.data or {}
    local npcId = data.npcId

    if not npcId then
        print('[ZDORPG] NpcStopFollow: missing npcId')
        return
    end

    local npc = activeNpcs[npcId]
    if not npc then
        print('[ZDORPG] NpcStopFollow: NPC not found: ' .. tostring(npcId))
        return
    end

    local ok, err = pcall(function()
        npc:sendEvent('RemoveAIPackages', 'Follow')
    end)
    if not ok then
        print('[ZDORPG] NpcStopFollow: failed: ' .. tostring(err))
        return
    end

    print('[ZDORPG] NPC ' .. tostring(npcId) .. ' stopped following')
end

local function handleNpcAttack(msg)
    local data = msg.data or {}
    local npcId = data.npcId
    local targetId = data.targetCharacterId

    if not npcId or not targetId then
        print('[ZDORPG] NpcAttack: missing npcId or targetCharacterId')
        return
    end

    local npc = activeNpcs[npcId]
    if not npc then
        print('[ZDORPG] NpcAttack: NPC not found: ' .. tostring(npcId))
        return
    end

    local target = activeNpcs[targetId]
    if not target then
        if playerObject and playerObject.recordId == targetId then
            target = playerObject
        else
            print('[ZDORPG] NpcAttack: target not found: ' .. tostring(targetId))
            return
        end
    end

    local ok, err = pcall(function()
        npc:sendEvent('RemoveAIPackages', 'Combat')
        npc:sendEvent('StartAIPackage', {type = 'Combat', target = target})
    end)
    if not ok then
        print('[ZDORPG] NpcAttack: failed: ' .. tostring(err))
        return
    end

    print('[ZDORPG] NPC ' .. tostring(npcId) .. ' attacking ' .. tostring(targetId))
end

local function handleNpcStopAttack(msg)
    local data = msg.data or {}
    local npcId = data.npcId

    if not npcId then
        print('[ZDORPG] NpcStopAttack: missing npcId')
        return
    end

    local npc = activeNpcs[npcId]
    if not npc then
        print('[ZDORPG] NpcStopAttack: NPC not found: ' .. tostring(npcId))
        return
    end

    local ok, err = pcall(function()
        npc:sendEvent('RemoveAIPackages', 'Combat')
    end)
    if not ok then
        print('[ZDORPG] NpcStopAttack: failed: ' .. tostring(err))
        return
    end

    print('[ZDORPG] NPC ' .. tostring(npcId) .. ' stopped attacking')
end

local function handleShowMessageBox(msg)
    if not playerObject then return end
    local data = msg.data or {}
    playerObject:sendEvent('ZdorpgNotify', { text = data.message or '' })
end

local function handleTeleportCharacterTo(msg)
    local data = msg.data or {}
    local npcId = data.sourceCharacterId
    local targetId = data.targetCharacterId
    if not npcId or not targetId then
        print("[ZDORPG] TeleportCharacterTo: missing source or target")
        return
    end
    local npc = activeNpcs[npcId]
    if not npc then
        print("[ZDORPG] TeleportCharacterTo: NPC not found: " .. tostring(npcId))
        return
    end
    local target = activeNpcs[targetId]
    if not target then
        if playerObject and playerObject.recordId == targetId then
            target = playerObject
        else
            print("[ZDORPG] TeleportCharacterTo: target not found: " .. tostring(targetId))
            return
        end
    end
    local okPos, targetPos = pcall(function() return target.position end)
    local okCell, targetCell = pcall(function() return target.cell end)
    if not okPos or not okCell then
        print("[ZDORPG] TeleportCharacterTo: cannot get target position/cell")
        return
    end
    local ok, err = pcall(function()
        npc:teleport(targetCell, targetPos)
    end)
    if not ok then
        print("[ZDORPG] TeleportCharacterTo: failed: " .. tostring(err))
        return
    end
    print("[ZDORPG] Teleported " .. tostring(npcId) .. " to " .. tostring(targetId))
end

local function handleSetHealth(msg)
    local data = msg.data or {}
    local npcId = data.characterId
    local health = data.health
    if not npcId then
        print("[ZDORPG] SetHealth: missing characterId")
        return
    end
    local npc = activeNpcs[npcId]
    if not npc then
        print("[ZDORPG] SetHealth: NPC not found: " .. tostring(npcId))
        return
    end
    local ok, err = pcall(function()
        local healthStat = types.Actor.stats.dynamic.health(npc)
        healthStat.current = health
        if health > healthStat.base then
            healthStat.base = health
        end
    end)
    if not ok then
        print("[ZDORPG] SetHealth: failed: " .. tostring(err))
        return
    end
    print("[ZDORPG] Set health of " .. tostring(npcId) .. " to " .. tostring(health))
end

local function handleEquipItem(msg)
    local msgId = msg.id or msg.Id
    local data = msg.data or {}
    local npcId = data.characterId
    local itemId = data.itemId
    local slot = data.slot
    if not npcId or not itemId then
        print("[ZDORPG] EquipItem: missing characterId or itemId")
        respond('EquipItem', msgId, { success = false, error = "missing_fields" })
        return
    end
    local npc = activeNpcs[npcId]
    if not npc then
        print("[ZDORPG] EquipItem: NPC not found: " .. tostring(npcId))
        respond('EquipItem', msgId, { success = false, error = "npc_not_found" })
        return
    end
    local okCreate, item = pcall(world.createObject, itemId, 1)
    if not okCreate or not item then
        print("[ZDORPG] EquipItem: failed to create " .. tostring(itemId))
        respond('EquipItem', msgId, { success = false, error = "create_failed" })
        return
    end
    local okMove, errMove = pcall(function() item:moveInto(npc) end)
    if not okMove then
        print("[ZDORPG] EquipItem: moveInto failed, spawning at feet")
        pcall(function() item:teleport(npc.cell, npc.position) end)
        respond('EquipItem', msgId, { success = false, error = "move_failed" })
        return
    end
    if slot then
        pcall(function()
            npc:sendEvent("Equip", { item = item, slot = slot, recordId = itemId })
        end)
    end
    print("[ZDORPG] Equipped " .. tostring(itemId) .. " on " .. tostring(npcId))
    respond('EquipItem', msgId, { success = true })
end

local function handleAddItemToInventory(msg)
    local data = msg.data or {}
    local npcId = data.characterId
    local itemId = data.itemId
    local count = data.count or 1
    if not npcId or not itemId then
        print("[ZDORPG] AddItemToInventory: missing characterId or itemId")
        return
    end
    local npc = activeNpcs[npcId]
    if not npc then
        print("[ZDORPG] AddItemToInventory: NPC not found: " .. tostring(npcId))
        return
    end
    local okCreate, item = pcall(world.createObject, itemId, count)
    if not okCreate or not item then
        print("[ZDORPG] AddItemToInventory: failed to create " .. tostring(itemId))
        return
    end
    local okMove, errMove = pcall(function() item:moveInto(npc) end)
    if not okMove then
        print("[ZDORPG] AddItemToInventory: moveInto failed, spawning at feet")
        item:teleport(npc.cell, npc.position)
        return
    end
    print("[ZDORPG] Added " .. tostring(count) .. "x " .. tostring(itemId) .. " to " .. tostring(npcId))
end

local function handleRemoveItemFromInventory(msg)
    local data = msg.data or {}
    local npcId = data.characterId
    local itemId = data.itemId
    local count = data.count or 1
    if not npcId or not itemId then
        print("[ZDORPG] RemoveItemFromInventory: missing characterId or itemId")
        return
    end
    print("[ZDORPG] RemoveItemFromInventory: NPC " .. tostring(npcId) .. " wants to remove " .. tostring(count) .. "x " .. tostring(itemId) .. ". Player must take it manually.")
end

local function findActor(id)
    if id == "player" then return playerObject end
    if activeNpcs[id] then return activeNpcs[id] end
    local lid = tostring(id):lower()
    for k, v in pairs(activeNpcs) do
        if tostring(k):lower() == lid then return v end
    end
    return nil
end

local function handleTransferItem(msg)
    local data = msg.data or {}
    local fromId   = data.fromCharacterId
    local toId     = data.toCharacterId
    local itemId   = data.itemId
    local count    = tonumber(data.count) or 1
    local isService = data.isServicePayment or false

    print("[ZDORPG] TransferItem called: from=" .. tostring(fromId) .. " to=" .. tostring(toId) .. " item=" .. tostring(itemId) .. " count=" .. tostring(count))

    if not fromId or not toId or not itemId or count <= 0 then
        respond('TransferItem', msg.id, { success = false, error = "missing_or_invalid_args" })
        return
    end

    local fromActor = findActor(fromId)
    local toActor   = findActor(toId)

    print("[ZDORPG] Resolved fromActor=" .. tostring(fromActor and fromActor.recordId or "NIL") .. " toActor=" .. tostring(toActor and toActor.recordId or "NIL"))

    if not fromActor then
        respond('TransferItem', msg.id, { success = false, error = "source_not_found" })
        return
    end
    if not toActor then
        respond('TransferItem', msg.id, { success = false, error = "target_not_found" })
        return
    end

    -- Remove from source: resolve inventory if needed, find the GameObject, then :remove(count)
    local okRemove, errRemove = pcall(function()
        local inv = types.Actor.inventory(fromActor)
        if not inv:isResolved() then
            print("[ZDORPG] resolving source inventory...")
            inv:resolve()
        end
        local beforeCount = inv:countOf(itemId)
        if beforeCount < count then
            error("insufficient items: have " .. beforeCount .. " need " .. count)
        end
        local item = inv:find(itemId)
        if not item then
            error("item not found in inventory")
        end
        print("[ZDORPG] remove found item=" .. tostring(item) .. " calling remove(" .. count .. ")")
        item:remove(count)
        local afterCount = inv:countOf(itemId)
        print("[ZDORPG] remove before=" .. beforeCount .. " after=" .. afterCount)
        if afterCount >= beforeCount then
            error("remove did not decrease item count")
        end
    end)
    print("[ZDORPG] remove ok=" .. tostring(okRemove) .. " err=" .. tostring(errRemove))

    if not okRemove then
        respond('TransferItem', msg.id, { success = false, error = "remove_failed", detail = tostring(errRemove) })
        return
    end

    -- Create new stack for target
    local okCreate, item = pcall(world.createObject, itemId, count)
    print("[ZDORPG] createObject ok=" .. tostring(okCreate) .. " item=" .. tostring(item))

    if not okCreate or not item then
        print("[ZDORPG] TransferItem: createObject failed, inventory may be inconsistent")
        respond('TransferItem', msg.id, { success = false, error = "create_failed" })
        return
    end

    -- Move into target inventory
    local okMove, errMove = pcall(function()
        item:moveInto(types.Actor.inventory(toActor))
    end)
    print("[ZDORPG] moveInto ok=" .. tostring(okMove) .. " err=" .. tostring(errMove))

    if not okMove then
        print("[ZDORPG] TransferItem: moveInto failed, dropping at feet")
        pcall(function() item:teleport(toActor.cell, toActor.position) end)
    end

    local label = isService and "[SERVICE]" or "[TRANSFER]"
    print(label .. " " .. tostring(count) .. "x " .. tostring(itemId) .. " | " .. tostring(fromId) .. " → " .. tostring(toId))
    respond('TransferItem', msg.id, { success = okMove })
end

local function processIncomingMessage(msg)
    print('[ZDORPG:DEBUG] Processing message: ' .. tostring(msg.type))

    if msg.type == 'GetPlayerInfo' then
        handleGetPlayerInfo(msg)
    elseif msg.type == 'GetNpcInfo' then
        handleGetNpcInfo(msg)
    elseif msg.type == 'SayMp3File' then
        handleSayMp3File(msg)
    elseif msg.type == 'SpeechRecognitionInProgress' then
        handleSpeechRecognitionInProgress(msg)
    elseif msg.type == 'SpeechRecognitionComplete' then
        handleSpeechRecognitionComplete(msg)
    elseif msg.type == 'PlayerStartSpeak' then
        handlePlayerStartSpeak(msg)
    elseif msg.type == 'PlayerStopSpeak' then
        handlePlayerStopSpeak(msg)
    elseif msg.type == 'GetCharactersWhoHear' then
        handleGetCharactersWhoHear(msg)
    elseif msg.type == 'SpawnOnGroundInFrontOfCharacter' then
        handleSpawnOnGroundInFrontOfCharacter(msg)
    elseif msg.type == 'PlaySound3dOnCharacter' then
        handlePlaySound3dOnCharacter(msg)
    elseif msg.type == 'NpcStartFollowCharacter' then
        handleNpcStartFollowCharacter(msg)
    elseif msg.type == 'NpcStopFollowCharacter' then
        handleNpcStopFollowCharacter(msg)
    elseif msg.type == 'NpcAttack' then
        handleNpcAttack(msg)
    elseif msg.type == 'NpcStopAttack' then
        handleNpcStopAttack(msg)
    elseif msg.type == 'ShowMessageBox' then
        handleShowMessageBox(msg)
    elseif msg.type == 'TransferItem' then
        handleTransferItem(msg)
    elseif msg.type == 'EquipItem' then
        handleEquipItem(msg)
    elseif msg.type == 'AddItemToInventory' then
        handleAddItemToInventory(msg)
    elseif msg.type == 'RemoveItemFromInventory' then
        handleRemoveItemFromInventory(msg)
    elseif msg.type == 'TeleportCharacterTo' then
        handleTeleportCharacterTo(msg)
    elseif msg.type == 'SetHealth' then
        handleSetHealth(msg)
    else
        print('[ZDORPG:ERROR] Unknown message type: ' .. tostring(msg.type))
    end
end

-------------------------------------------------------------------------------
-- Game time tracking
-------------------------------------------------------------------------------

local lastGameTime = nil

local function checkGameTime()
    if not playerObject then return end
    local ok, gt = pcall(calendar.formatGameTime, "%H:%M, %d %B 3E %Y")
    if not ok then return end
    if gt ~= lastGameTime then
        lastGameTime = gt
        publish('GameTimeUpdate', { gameTime = gt })
    end
end
-------------------------------------------------------------------------------
-- Cell change detection
-------------------------------------------------------------------------------

local function checkCellChange()
    if not playerObject then return end
    local ok, cell = pcall(function() return playerObject.cell end)
    if not ok or not cell then return end
    local cellName = cell.name or cell.id
    if cellName ~= lastCellName then
        lastCellName = cellName
        publish('CellChange', {
            playerId = playerObject.recordId,
            cellName = cellName,
        })
    end
end

-------------------------------------------------------------------------------
-- Engine handlers
-------------------------------------------------------------------------------

local function getEquipmentList(actor)
    local items = {}
    local ok, equipment = pcall(types.Actor.getEquipment, actor)
    if not ok or not equipment then return items end
    for slot, item in pairs(equipment) do
        if item and item:isValid() then
            table.insert(items, { slot = tostring(slot), recordId = item.recordId or "unknown" })
        end
    end
    return items
end

local function hashEquipment(items)
    if not items or #items == 0 then return "empty" end
    local parts = {}
    for _, item in ipairs(items) do table.insert(parts, item.slot .. ":" .. item.recordId) end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function sendEquipmentIfChanged(actor, kind)
    if not actor or not actor:isValid() then return end
    local items = getEquipmentList(actor)
    local hash = hashEquipment(items)
    local key = kind .. ":" .. actor.recordId
    if lastEquipment[key] == hash then return end
    lastEquipment[key] = hash
    publish(kind .. 'Equipment', { id = actor.recordId, items = items })
    print('[ZDORPG] Sent ' .. kind .. ' equipment: ' .. actor.recordId .. ' (' .. #items .. ' items)')
end

local function rebuildActiveNpcs()
    activeNpcs = {}
    for _, actor in ipairs(world.activeActors) do
        if types.NPC.objectIsInstance(actor) then
            activeNpcs[actor.recordId] = actor
            sendEquipmentIfChanged(actor, 'Npc')
        end
    end
    print('[ZDORPG] Rebuilt activeNpcs: ' .. tostring(#world.activeActors) .. ' actors checked')
end

local function onUpdate(dt)
    frameCounter = frameCounter + 1
    if frameCounter % POLL_INTERVAL_FRAMES ~= 0 then return end

    local messages, newLastId, sessionId, sessionChanged =
        ipc.readIncoming(vfs, lastSeenClientMsgId, currentSessionId)

    if sessionChanged then
        print('[ZDORPG] Session changed: ' .. tostring(currentSessionId) .. ' -> ' .. tostring(sessionId))
        currentSessionId = sessionId
        lastSeenClientMsgId = newLastId or 0
        modMsgCounter = 0
        clientConnected = true
        playerInfoSent = false
        publish('StartSessionAck', { sessionId = sessionId })
        showConnectedIndicator()
        -- Send save context and player info now that we're in the new session
        if not saveId then
            math.randomseed(os.time())
            saveId = tostring(os.time()) .. '-' .. tostring(math.random(1, 1000000))
            print('[ZDORPG] Generated new saveId in sessionChanged: ' .. saveId)
        end
        publish('GameSaveLoad', { saveId = saveId })

    end

    if messages and #messages > 0 then
        lastSeenClientMsgId = newLastId
        for _, msg in ipairs(messages) do
            local ok, err = pcall(processIncomingMessage, msg)
            if not ok then
                print('[ZDORPG] Error processing message: ' .. tostring(err))
            end
        end
        ipc.sendAck(lastSeenClientMsgId)
    end

    checkCellChange()
    checkGameTime()
    
    -- Send PlayerAdded once we have connection and player (e.g. after save load)
    if playerObject and clientConnected and not playerInfoSent then
        local rec = types.NPC.record(playerObject)
        local health = types.Actor.stats.dynamic.health(playerObject)
        local magicka = types.Actor.stats.dynamic.magicka(playerObject)
        local fatigue = types.Actor.stats.dynamic.fatigue(playerObject)
        local levelStat = types.Actor.stats.level(playerObject)
        publish('PlayerAdded', {
            playerId = playerObject.recordId,
            name = rec.name or "",
            race = rec.race or "",
            sex = (rec.isMale == true) and "male" or (rec.isMale == false) and "female" or "",
            className = rec.class or "",
            level = levelStat and levelStat.current or 0,
            healthCurrent = health and health.current or 0,
            healthMax = health and health.base or 0,
            magickaCurrent = magicka and magicka.current or 0,
            magickaMax = magicka and magicka.base or 0,
            fatigueCurrent = fatigue and fatigue.current or 0,
            fatigueMax = fatigue and fatigue.base or 0,
        })
        playerInfoSent = true
        print('[ZDORPG] Sent PlayerAdded from onUpdate: ' .. (rec.name or "?"))
    end
    
    -- Periodic NPC discovery + equipment sync (every ~10 seconds)
    npcRebuildTick = (npcRebuildTick or 0) + 1
    if npcRebuildTick >= 120 and playerObject then
        npcRebuildTick = 0
        rebuildActiveNpcs()
    end

    -- Periodic player state sync to server (every ~3 seconds)
    stateSyncTick = (stateSyncTick or 0) + 1
    if stateSyncTick >= 180 and playerObject then
        stateSyncTick = 0
        local health = types.Actor.stats.dynamic.health(playerObject)
        local magicka = types.Actor.stats.dynamic.magicka(playerObject)
        local fatigue = types.Actor.stats.dynamic.fatigue(playerObject)
        local pCell = playerObject.cell
        local cellName = pCell and (pCell.name or pCell.editorName) or nil
        publish('PlayerStateChanged', {
            playerId = playerObject.recordId,
            healthCurrent = health and health.current or 0,
            healthMax = health and health.base or 0,
            magickaCurrent = magicka and magicka.current or 0,
            magickaMax = magicka and magicka.base or 0,
            fatigueCurrent = fatigue and fatigue.current or 0,
            fatigueMax = fatigue and fatigue.base or 0,
            cellName = cellName,
            isDead = health and health.current <= 0 or false,
        })
    end
end

local function onPlayerAdded(player)
    playerObject = player
    print('[ZDORPG] Player added: ' .. tostring(player.recordId))
    local rec = types.NPC.record(player)
    local health = types.Actor.stats.dynamic.health(player)
    local magicka = types.Actor.stats.dynamic.magicka(player)
    local fatigue = types.Actor.stats.dynamic.fatigue(player)
    local levelStat = types.Actor.stats.level(player)
    publish('PlayerAdded', {
        playerId = player.recordId,
        name = rec.name or "",
        race = rec.race or "",
        sex = (rec.isMale == true) and "male" or (rec.isMale == false) and "female" or "",
        className = rec.class or "",
        level = levelStat and levelStat.current or 0,
        healthCurrent = health and health.current or 0,
        healthMax = health and health.base or 0,
        magickaCurrent = magicka and magicka.current or 0,
        magickaMax = magicka and magicka.base or 0,
        fatigueCurrent = fatigue and fatigue.current or 0,
        fatigueMax = fatigue and fatigue.base or 0,
    })
    if clientConnected then
        showConnectedIndicator()
    end
end

local function onActorActive(actor)
    if types.NPC.objectIsInstance(actor) then
        activeNpcs[actor.recordId] = actor
        sendEquipmentIfChanged(actor, 'Npc')
    end
end

local function onObjectActive(object)
end

-------------------------------------------------------------------------------
-- Event handlers (from player script)
-------------------------------------------------------------------------------

local function onTargetChanged(data)
    publish('TargetChanged', {
        playerId = data.playerId,
        npcId = data.npcId,
    })
end

-------------------------------------------------------------------------------
-- Save / Load
-------------------------------------------------------------------------------

local function onSave()
    if not saveId then
        math.randomseed(os.time())
        saveId = tostring(os.time()) .. '-' .. tostring(math.random(1, 1000000))
        print('[ZDORPG] Generated new saveId in onSave: ' .. saveId)
    end
    publish('GameSaveLoad', { saveId = saveId })
    return {
        lastSeenClientMsgId = lastSeenClientMsgId,
        lastCellName = lastCellName,
        modMsgCounter = modMsgCounter,
        currentSessionId = currentSessionId,
        saveId = saveId,
    }
end

local function onLoad(data)
    if data then
        lastSeenClientMsgId = data.lastSeenClientMsgId or 0
        lastCellName = data.lastCellName
        modMsgCounter = data.modMsgCounter or 0
        currentSessionId = data.currentSessionId
        if data.saveId then
            saveId = data.saveId
            print('[ZDORPG] Restored saveId from save: ' .. tostring(saveId))
        end
    end
    lastEquipment = {}
    rebuildActiveNpcs()
    -- Try to restore playerObject (onPlayerAdded may not fire after reloadlua)
    for _, actor in ipairs(world.activeActors) do
        if types.Player.objectIsInstance(actor) then
            playerObject = actor
            print('[ZDORPG] Restored playerObject on load: ' .. tostring(actor.recordId))
            sendEquipmentIfChanged(actor, 'Player')
            break
        end
    end
    if not saveId then
        math.randomseed(os.time())
        saveId = tostring(os.time()) .. '-' .. tostring(math.random(1, 1000000))
        print('[ZDORPG] Generated new saveId in sessionChanged: ' .. saveId)
    end
    publish('GameSaveLoad', { saveId = saveId })
    -- Re-broadcast player object to NPCs so their onInputAction works again
    if playerObject then
        for _, actor in ipairs(world.activeActors) do
            if types.NPC.objectIsInstance(actor) then
                actor:sendEvent('ZdoRpgAi_SetPlayer', playerObject)
            end
        end
        print('[ZDORPG] Re-sent playerObject to NPCs after load')
    end
end

-------------------------------------------------------------------------------
-- Script interface
-------------------------------------------------------------------------------

print('[ZDORPG] Global script loaded')

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
        onPlayerAdded = onPlayerAdded,
        onActorActive = onActorActive,
        onObjectActive = onObjectActive,
    },
    eventHandlers = {
        ZdorpgTargetChanged = onTargetChanged,
        ZdorpgRequestTextInput = function(data)
            publish('RequestTextInput', data)
        end,
    },
}
