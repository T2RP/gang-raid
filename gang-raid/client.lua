-- =============================================
-- GANG HIDEOUT RAID | client.lua  v6.1
-- Supports: qb-target / ox_target (auto-detect)
--           QBCore / QBox / ox_lib notify
-- =============================================

local QBCore             = nil
local lootedCrates       = {}
local spawnedCrates      = {}   -- object handles so we can delete on cleanup
local spawnedGuards      = {}   -- { ped = handle, looted = bool }
local lootedGuards       = {}   -- [ped handle] = true
local activeLocation     = nil
local lootMonitorRunning = false
local aiLoopRunning      = false
local isRaidStarter      = false
local raidClearReported  = false
local seenAlive          = false
-- FIX: track whether the loot window is open so raidFinished
-- doesn't delete bodies players are actively looting mid-animation
local lootWindowOpen     = false

-- Init QBCore if available
local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
if ok and obj then QBCore = obj end

-- =============================================
-- NOTIFY HELPER
-- =============================================
local function Notify(msg, ntype)
    ntype = ntype or 'primary'
    if QBCore then
        QBCore.Functions.Notify(msg, ntype)
    elseif GetResourceState('ox_lib') == 'started' then
        exports['ox_lib']:notify({ description = msg, type = ntype })
    end
end

-- =============================================
-- TARGET COMPATIBILITY LAYER
-- =============================================
local TargetLib = nil

local function GetTargetLib()
    if TargetLib and TargetLib ~= 'none' then return TargetLib end
    local cfg = Config.TargetExport
    if cfg == 'ox_target' or (cfg == 'auto' and GetResourceState('ox_target') == 'started') then
        TargetLib = 'ox_target'
    elseif cfg == 'qb-target' or (cfg == 'auto' and GetResourceState('qb-target') == 'started') then
        TargetLib = 'qb-target'
    else
        TargetLib = 'none'
    end
    if Config.Debug then print('[gang-raid] Target lib: ' .. TargetLib) end
    return TargetLib
end

local function WaitForTargetLib()
    local attempts = 0
    while GetTargetLib() == 'none' and attempts < 40 do
        Wait(500)
        attempts = attempts + 1
    end
    if TargetLib == 'none' then
        print('^1[gang-raid] ERROR: No target resource found. Ensure qb-target or ox_target starts before gang-raid.^7')
    end
end

local function AddEntityTarget(entity, label, icon, distance, action)
    local lib = GetTargetLib()
    if lib == 'ox_target' then
        exports['ox_target']:addLocalEntity(entity, {
            {
                name     = 'gr_' .. tostring(entity),
                label    = label,
                icon     = icon,
                distance = distance,
                onSelect = action,
            }
        })
    elseif lib == 'qb-target' then
        exports['qb-target']:AddTargetEntity(entity, {
            options  = { { label = label, icon = icon, action = action } },
            distance = distance,
        })
    end
end

local function RemoveEntityTarget(entity)
    local lib = GetTargetLib()
    if lib == 'ox_target' then
        exports['ox_target']:removeLocalEntity(entity)
    elseif lib == 'qb-target' then
        exports['qb-target']:RemoveTargetEntity(entity)
    end
end

-- =============================================
-- EMOTE HELPER
-- =============================================
local function PlayEmote(scenario)
    if scenario then
        TaskStartScenarioInPlace(PlayerPedId(), scenario, 0, true)
    else
        ClearPedTasksImmediately(PlayerPedId())
    end
end

-- =============================================
-- OX_LIB SKILLCHECK + PROGRESSBAR LOOT SEQUENCE
-- =============================================
local function DoLootSequence(params)
    local hasOxLib = GetResourceState('ox_lib') == 'started'

    if not hasOxLib then
        params.onSuccess()
        return
    end

    local passed = exports['ox_lib']:skillCheck({ 'easy', 'medium' }, { 'e' })

    if not passed then
        Notify('You failed the check.', 'error')
        if params.onFail then params.onFail() end
        return
    end

    PlayEmote(params.emote)

    local completed = exports['ox_lib']:progressBar({
        duration     = params.duration or 4000,
        label        = params.progressLabel or 'Searching...',
        useWhileDead = false,
        canCancel    = true,
        disable = {
            move   = true,
            car    = true,
            combat = true,
            sprint = true,
        },
    })

    ClearPedTasksImmediately(PlayerPedId())

    if completed then
        params.onSuccess()
    else
        Notify('Interrupted.', 'error')
        if params.onFail then params.onFail() end
    end
end

-- =============================================
-- GUARD RELATIONSHIPS
-- =============================================
local function SetupGuardRelationships()
    local groupName   = "HIDEOUT_GUARDS"
    local groupHash   = GetHashKey(groupName)
    local playerGroup = GetHashKey("PLAYER")

    AddRelationshipGroup(groupName)
    SetRelationshipBetweenGroups(5, groupHash, playerGroup)
    SetRelationshipBetweenGroups(5, playerGroup, groupHash)
    SetRelationshipBetweenGroups(5, groupHash, GetHashKey("CIVMALE"))
    SetRelationshipBetweenGroups(5, groupHash, GetHashKey("CIVFEMALE"))

    return groupHash
end

-- =============================================
-- APPLY COMBAT SETTINGS
-- =============================================
local function ApplyCombatSettings(ped, groupHash)
    SetPedRelationshipGroupHash(ped, groupHash)
    SetPedAsEnemy(ped, true)
    SetPedAlertness(ped, 3)

    SetPedCombatAttributes(ped, 0,  true)
    SetPedCombatAttributes(ped, 2,  true)
    SetPedCombatAttributes(ped, 5,  true)
    SetPedCombatAttributes(ped, 14, true)
    SetPedCombatAttributes(ped, 17, true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCombatAttributes(ped, 52, true)

    SetPedCombatRange(ped, 2)
    SetPedCombatAbility(ped, 2)
    SetPedCombatMovement(ped, 2)

    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedTargetLossResponse(ped, 2)
end

-- =============================================
-- GUARD AI LOOP
-- =============================================
local function RequestPedControl(ped)
    if NetworkHasControlOfEntity(ped) then return true end
    NetworkRequestControlOfEntity(ped)
    local t = 0
    while not NetworkHasControlOfEntity(ped) and t < 1000 do
        Wait(50)
        t = t + 50
        NetworkRequestControlOfEntity(ped)
    end
    return NetworkHasControlOfEntity(ped)
end

local function TaskGuardCombat(ped)
    local pedCoords     = GetEntityCoords(ped)
    local closestPlayer = nil
    local closestDist   = 80.0

    for _, playerId in ipairs(GetActivePlayers()) do
        local playerPed = GetPlayerPed(playerId)
        if DoesEntityExist(playerPed) and not IsEntityDead(playerPed) then
            local dist = #(pedCoords - GetEntityCoords(playerPed))
            if dist < closestDist then
                closestDist   = dist
                closestPlayer = playerPed
            end
        end
    end

    if closestPlayer then
        TaskCombatPed(ped, closestPlayer, 0, 16)
    else
        TaskCombatHatedTargetsAroundPed(ped, 80.0, 0)
    end
end

local function StartGuardAILoop()
    if aiLoopRunning then return end
    aiLoopRunning = true

    CreateThread(function()
        while aiLoopRunning do
            Wait(1500)
            for _, entry in ipairs(spawnedGuards) do
                local ped = entry.ped
                if not DoesEntityExist(ped) or IsEntityDead(ped) then goto continue end
                if RequestPedControl(ped) then
                    TaskGuardCombat(ped)
                end
                ::continue::
            end
        end
    end)
end

-- =============================================
-- LOOT MONITOR
-- Runs only on the raid-starter client.
-- Watches for dead guards, adds loot targets to
-- bodies, and signals the server when all are down.
--
-- FIX: Previously reported waveClear the moment
-- deadCount >= totalGuards which could fire before
-- seenAlive was set (i.e. on the very first tick
-- if guards hadn't registered yet). Now we gate on
-- seenAlive being true, meaning at least one guard
-- was confirmed alive before we start counting deaths.
-- =============================================
local function StartLootMonitor()
    if lootMonitorRunning then return end
    lootMonitorRunning = true
    raidClearReported  = false
    seenAlive          = false

    CreateThread(function()
        while lootMonitorRunning do
            Wait(1000)

            if #spawnedGuards == 0 then goto continue end

            local totalGuards = #spawnedGuards
            local deadCount   = 0

            for _, entry in ipairs(spawnedGuards) do
                local ped = entry.ped

                if not DoesEntityExist(ped) then
                    deadCount = deadCount + 1
                elseif IsEntityDead(ped) then
                    deadCount = deadCount + 1

                    -- FIX: Only add target if the ped still exists at the time the
                    -- timeout fires. Previously we checked DoesEntityExist inside
                    -- the timeout but the entity could be deleted by CleanupRaid
                    -- (which ran after 2s) before the 1.5s timeout even elapsed,
                    -- meaning the target was added to a deleted ped and vanished.
                    -- Now CleanupRaid is deferred by LootWindowDuration so bodies
                    -- persist long enough for players to actually interact.
                    if not entry.looted and not lootedGuards[ped] then
                        lootedGuards[ped] = true
                        entry.looted      = true

                        local p = ped
                        local e = entry
                        SetTimeout(1500, function()
                            if not DoesEntityExist(p) then return end
                            AddEntityTarget(p, "Search Body", "fas fa-search", 1.5, function(entity)
                                RemoveEntityTarget(entity)
                                DoLootSequence({
                                    emote         = 'CODE_HUMAN_MEDIC_KNEEL',
                                    progressLabel = 'Searching body...',
                                    duration      = 5000,
                                    onSuccess     = function()
                                        TriggerServerEvent("gang_hideout:lootGuard")
                                    end,
                                    onFail = function()
                                        -- Let the player retry on failure
                                        if DoesEntityExist(p) then
                                            lootedGuards[p] = nil
                                            e.looted        = false
                                        end
                                    end,
                                })
                            end)
                        end)
                    end
                else
                    -- Guard is alive — mark that we've seen at least one alive guard
                    -- so we don't trigger waveClear prematurely on the first tick
                    seenAlive = true
                end
            end

            -- All guards confirmed dead and we previously saw them alive
            if isRaidStarter
            and seenAlive
            and deadCount >= totalGuards
            and totalGuards > 0
            and not raidClearReported then
                raidClearReported = true
                lootWindowOpen    = true
                if Config.Debug then
                    print('[gang-raid] All guards cleared — ' .. totalGuards .. ' down')
                end
                TriggerServerEvent('gang_hideout:waveClear')

                -- Stop AI loop — no live guards left to command
                aiLoopRunning = false
            end

            ::continue::
        end
    end)
end

-- =============================================
-- WAYPOINT HELPERS
-- =============================================
local function SetRaidWaypoint(coords)
    SetNewWaypoint(coords.x, coords.y)
end

local function ClearRaidBlip()
    ClearGpsPlayerWaypoint()
end

-- =============================================
-- FULL RAID CLEANUP
-- FIX: Now only called after LootWindowDuration
-- has elapsed (triggered by gang_hideout:raidFinished).
-- Previously CleanupRaid fired 2s after waveClear,
-- deleting all bodies and crates almost immediately.
-- =============================================
local function CleanupRaid()
    lootMonitorRunning = false
    aiLoopRunning      = false
    lootWindowOpen     = false

    -- Remove crate props
    for _, obj in ipairs(spawnedCrates) do
        if DoesEntityExist(obj) then
            RemoveEntityTarget(obj)
            SetEntityAsMissionEntity(obj, false, true)
            DeleteObject(obj)
        end
    end
    spawnedCrates = {}
    lootedCrates  = {}

    -- Remove guard peds
    for _, entry in ipairs(spawnedGuards) do
        local ped = entry.ped
        if DoesEntityExist(ped) then
            RemoveEntityTarget(ped)
            SetEntityAsMissionEntity(ped, false, true)
            DeleteEntity(ped)
        end
    end
    spawnedGuards = {}
    lootedGuards  = {}

    ClearRaidBlip()
    activeLocation = nil
end

-- =============================================
-- NET EVENTS
-- =============================================

-- Fires on ALL clients when the raid location is chosen
RegisterNetEvent('gang_hideout:raidStarted', function(locationIndex)
    -- Reset all state
    lootedCrates       = {}
    spawnedCrates      = {}
    lootedGuards       = {}
    spawnedGuards      = {}
    lootMonitorRunning = false
    aiLoopRunning      = false
    isRaidStarter      = false
    raidClearReported  = false
    seenAlive          = false
    lootWindowOpen     = false
    activeLocation     = Config.Locations[locationIndex]

    SetRaidWaypoint(activeLocation.blip.coords)

    -- Spawn loot crates in a thread — Wait() calls are not safe in a bare net event
    -- callback and CreateObject requires the model to be streamed first.
    CreateThread(function()
        -- Request and wait for the crate model to fully stream before spawning
        local crateModel = GetHashKey('ch_prop_ch_crate_01a')
        RequestModel(crateModel)
        local modelTimeout = 0
        while not HasModelLoaded(crateModel) and modelTimeout < 5000 do
            Wait(100)
            modelTimeout = modelTimeout + 100
        end

        if not HasModelLoaded(crateModel) then
            print('^1[gang-raid] ERROR: Crate model failed to load — crates will not spawn.^7')
            SetModelAsNoLongerNeeded(crateModel)
            return
        end

        for i, coords in pairs(activeLocation.lootCrates) do
            local crateId = "crate_" .. i

            local obj = CreateObject(crateModel, coords.x, coords.y, coords.z + 2.0, true, true, true)

            if not DoesEntityExist(obj) then
                if Config.Debug then print('[gang-raid] Crate ' .. crateId .. ' failed to create.') end
                goto nextcrate
            end

            SetEntityAsMissionEntity(obj, true, true)

            -- Let physics settle so PlaceObjectOnGroundProperly has a surface to raycast
            FreezeEntityPosition(obj, false)
            Wait(100)
            PlaceObjectOnGroundProperly(obj)
            Wait(300)
            FreezeEntityPosition(obj, true)

            table.insert(spawnedCrates, obj)

            AddEntityTarget(obj, "Search Crate", "fas fa-box-open", 2.0, function(entity)
                if lootedCrates[crateId] then
                    Notify("This crate is already empty.", "error")
                    return
                end

                DoLootSequence({
                    emote         = 'PROP_HUMAN_BUM_BIN',
                    progressLabel = 'Searching crate...',
                    duration      = 6000,
                    onSuccess     = function()
                        lootedCrates[crateId] = true
                        TriggerServerEvent("gang_hideout:giveLoot")
                        RemoveEntityTarget(entity)
                    end,
                    onFail = function()
                        -- Player can retry on fail
                    end,
                })
            end)

            if Config.Debug then print('[gang-raid] Crate ' .. crateId .. ' spawned.') end
            ::nextcrate::
        end

        SetModelAsNoLongerNeeded(crateModel)

        if Config.Debug then
            print('[gang-raid] ' .. #spawnedCrates .. ' crates spawned at: ' .. activeLocation.name)
        end
    end)
end)

-- Fires on the raid-starter client only — spawn guards
RegisterNetEvent('gang_hideout:spawnGuards', function(guards)
    isRaidStarter      = true
    local groupHash    = SetupGuardRelationships()
    spawnedGuards      = {}
    raidClearReported  = false
    lootMonitorRunning = false
    aiLoopRunning      = false
    local netIds       = {}

    -- Pre-load all unique models
    local uniqueModels = {}
    for _, guard in pairs(guards) do
        local hash = GetHashKey(guard.model)
        if not uniqueModels[hash] then
            uniqueModels[hash] = true
            RequestModel(hash)
        end
    end

    local loadTimeout = 0
    local allLoaded   = false
    while not allLoaded and loadTimeout < 10000 do
        allLoaded = true
        for hash in pairs(uniqueModels) do
            if not HasModelLoaded(hash) then
                allLoaded = false
                break
            end
        end
        if not allLoaded then
            Wait(100)
            loadTimeout = loadTimeout + 100
        end
    end

    -- Spawn each guard
    for _, guard in pairs(guards) do
        local model = GetHashKey(guard.model)

        local ped = CreatePed(4, model,
            guard.coords.x, guard.coords.y, guard.coords.z, guard.coords.w,
            true, true)

        SetEntityAsMissionEntity(ped, true, true)
        NetworkRegisterEntityAsNetworked(ped)
        SetEntityVisible(ped, true, false)
        SetEntityLodDist(ped, 500)
        SetPedConfigFlag(ped, 320, true)

        local pedNetId = NetworkGetNetworkIdFromEntity(ped)
        if pedNetId and pedNetId ~= 0 then
            SetNetworkIdExistsOnAllMachines(pedNetId, true)
            NetworkSetNetworkIdDynamic(pedNetId, true)
        end

        GiveWeaponToPed(ped, GetHashKey(guard.weapon), 200, true, true)
        SetPedArmour(ped, guard.armor    or 100)
        SetPedAccuracy(ped, guard.accuracy or 70)

        ApplyCombatSettings(ped, groupHash)
        TaskGuardCombat(ped)

        table.insert(spawnedGuards, { ped = ped, looted = false })

        -- Wait for network ID to be valid
        local timeout = 0
        while (not NetworkGetNetworkIdFromEntity(ped) or NetworkGetNetworkIdFromEntity(ped) == 0) and timeout < 3000 do
            Wait(50)
            timeout = timeout + 50
        end

        local netId = NetworkGetNetworkIdFromEntity(ped)
        if netId and netId ~= 0 then
            table.insert(netIds, netId)
        end

        -- Wait for entity to be visible before spawning the next
        local renderWait = 0
        while not IsEntityVisible(ped) and renderWait < 1000 do
            Wait(50)
            renderWait = renderWait + 50
        end

        Wait(200)
    end

    for hash in pairs(uniqueModels) do
        SetModelAsNoLongerNeeded(hash)
    end

    TriggerServerEvent('gang_hideout:guardsSpawned', netIds)
    StartLootMonitor()
    StartGuardAILoop()
    Notify('Gang hideout spotted — enemies on site!', 'error')

    if Config.Debug then print('[gang-raid] Spawned ' .. #netIds .. ' guards.') end
end)

-- Fires on ALL clients — configure peds that the spawner created
RegisterNetEvent('gang_hideout:configurePeds', function(netIds)
    -- Give the spawner client time to fully register each entity on the network
    Wait(1500)
    local groupHash = SetupGuardRelationships()

    for _, netId in ipairs(netIds) do
        local waitTime = 0
        while not NetworkDoesEntityExistWithNetworkId(netId) and waitTime < 3000 do
            Wait(100)
            waitTime = waitTime + 100
        end

        if NetworkDoesEntityExistWithNetworkId(netId) then
            local ped = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                SetEntityVisible(ped, true, false)
                SetEntityLodDist(ped, 500)
                SetPedConfigFlag(ped, 320, true)
                ApplyCombatSettings(ped, groupHash)

                -- Track on non-spawner clients so the AI loop works for everyone
                local alreadyTracked = false
                for _, entry in ipairs(spawnedGuards) do
                    if entry.ped == ped then alreadyTracked = true; break end
                end
                if not alreadyTracked then
                    table.insert(spawnedGuards, { ped = ped, looted = false })
                end
            end
        end
    end
end)

-- =============================================
-- RAID WON — fires immediately when all guards die
-- FIX: Previously claimBonus was called inside
-- raidFinished which only fired after CleanupRaid,
-- meaning the bonus triggered at the same moment
-- everything was deleted. Now it fires here so the
-- bonus is given while bodies are still lootable.
-- =============================================
RegisterNetEvent('gang_hideout:raidWon', function()
    lootWindowOpen = true
    Notify('All guards down! Loot the site — you have ' .. Config.LootWindowDuration .. ' seconds!', 'success')
    TriggerServerEvent('gang_hideout:claimBonus')
end)

-- =============================================
-- RAID FINISHED — fires after LootWindowDuration
-- FIX: This is now the ONLY place CleanupRaid is
-- called. It receives the guard netIds from the
-- server for any remaining corpse cleanup.
-- =============================================
RegisterNetEvent('gang_hideout:raidFinished', function(netIds)
    -- Clean up any leftover corpses passed by the server
    if netIds then
        for _, netId in ipairs(netIds) do
            if NetworkDoesEntityExistWithNetworkId(netId) then
                local ped = NetworkGetEntityFromNetworkId(netId)
                if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    RemoveEntityTarget(ped)
                    SetEntityAsMissionEntity(ped, false, true)
                    DeleteEntity(ped)
                end
            end
        end
    end

    CleanupRaid()
    Notify('The raid site has gone cold.', 'primary')
end)

-- =============================================
-- START NPC — always present in world
-- =============================================
CreateThread(function()
    WaitForTargetLib()

    local npc   = Config.StartRaidNPC
    local model = GetHashKey(npc.model)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local ped = CreatePed(0, model,
        npc.coords.x, npc.coords.y, npc.coords.z - 1, npc.coords.w,
        false, true)

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(model)

    AddEntityTarget(ped, npc.targetLabel, "fas fa-skull-crossbones", 2.5, function()
        TriggerServerEvent("gang_hideout:startRaid")
    end)
end)
