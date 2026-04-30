-- =============================================
-- GANG HIDEOUT RAID | client.lua  v6.2
-- Supports: qb-target / ox_target (auto-detect)
--           QBCore / QBox / ox_lib notify
-- =============================================

local QBCore             = nil
local lootedCrate        = false         -- single crate, single flag
local spawnedCrateHandle = nil           -- local entity handle of the networked crate
local spawnedCrateNetId  = nil           -- net ID so all clients can resolve it
local spawnedGuards      = {}            -- { ped = handle, looted = bool }
local lootedGuards       = {}            -- [ped handle] = true
local activeLocation     = nil
local lootMonitorRunning = false
local aiLoopRunning      = false
local isRaidStarter      = false
local raidClearReported  = false
local seenAlive          = false
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
-- Guards defend the crate when idle; attack
-- players when one comes close enough.
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
        -- No player in range — guard defends the crate if it exists, otherwise patrols
        if spawnedCrateHandle and DoesEntityExist(spawnedCrateHandle) then
            TaskGuardCurrentPosition(ped)
        else
            TaskCombatHatedTargetsAroundPed(ped, 80.0, 0)
        end
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
-- LOOT MONITOR — raid-starter client only
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
                    seenAlive = true
                end
            end

            if isRaidStarter
            and seenAlive
            and deadCount >= totalGuards
            and totalGuards > 0
            and not raidClearReported then
                raidClearReported = true
                lootWindowOpen    = true
                aiLoopRunning     = false
                if Config.Debug then
                    print('[gang-raid] All guards cleared — ' .. totalGuards .. ' down')
                end
                TriggerServerEvent('gang_hideout:waveClear')
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
-- ATTACH CRATE TARGET — used by both spawner
-- (after spawning) and all other clients (after
-- configureCrate resolves the net ID to a handle)
-- =============================================
local function AttachCrateTarget(obj)
    AddEntityTarget(obj, "Search Crate", "fas fa-box-open", 2.0, function(entity)
        if lootedCrate then
            Notify("This crate is already empty.", "error")
            return
        end

        DoLootSequence({
            emote         = 'PROP_HUMAN_BUM_BIN',
            progressLabel = 'Searching crate...',
            duration      = 6000,
            onSuccess     = function()
                lootedCrate = true
                TriggerServerEvent("gang_hideout:giveLoot")
                RemoveEntityTarget(entity)
                Notify("Crate looted!", "success")
            end,
            onFail = function()
                -- Player can retry
            end,
        })
    end)
end

-- =============================================
-- FULL RAID CLEANUP
-- =============================================
local function CleanupRaid()
    lootMonitorRunning = false
    aiLoopRunning      = false
    lootWindowOpen     = false

    -- Delete networked crate
    if spawnedCrateHandle and DoesEntityExist(spawnedCrateHandle) then
        RemoveEntityTarget(spawnedCrateHandle)
        SetEntityAsMissionEntity(spawnedCrateHandle, false, true)
        DeleteObject(spawnedCrateHandle)
    end
    spawnedCrateHandle = nil
    spawnedCrateNetId  = nil
    lootedCrate        = false

    -- Delete guard peds
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
    lootedCrate        = false
    spawnedCrateHandle = nil
    spawnedCrateNetId  = nil
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

    if Config.Debug then print('[gang-raid] Raid started at: ' .. activeLocation.name) end
end)

-- =============================================
-- SPAWN GUARDS + CRATE — raid-starter client only
-- The crate is spawned here as a networked object
-- so every player sees the exact same prop.
-- Its net ID is sent back to the server which
-- broadcasts it via configureCrate so all other
-- clients can resolve it and attach a loot target.
-- =============================================
RegisterNetEvent('gang_hideout:spawnGuards', function(guards, crateCoord)
    isRaidStarter      = true
    local groupHash    = SetupGuardRelationships()
    spawnedGuards      = {}
    raidClearReported  = false
    lootMonitorRunning = false
    aiLoopRunning      = false
    local netIds       = {}

    -- ---- SPAWN CRATE FIRST (networked) ----
    CreateThread(function()
        local crateModel = GetHashKey('prop_mb_crate_01a_set')
        RequestModel(crateModel)
        local mt = 0
        while not HasModelLoaded(crateModel) and mt < 5000 do
            Wait(100)
            mt = mt + 100
        end

        if not HasModelLoaded(crateModel) then
            print('^1[gang-raid] ERROR: Crate model failed to load.^7')
            SetModelAsNoLongerNeeded(crateModel)
            return
        end

        -- isNetwork=true, isMissionEntity=true, isScriptHostObj=false
        local obj = CreateObject(crateModel, crateCoord.x, crateCoord.y, crateCoord.z + 0.5, true, true, false)

        if not DoesEntityExist(obj) then
            print('^1[gang-raid] ERROR: Crate CreateObject returned invalid handle.^7')
            SetModelAsNoLongerNeeded(crateModel)
            return
        end

        SetModelAsNoLongerNeeded(crateModel)
        SetEntityAsMissionEntity(obj, true, true)
        NetworkRegisterEntityAsNetworked(obj)

        -- Wait for a valid net ID
        local timeout = 0
        while (not NetworkGetNetworkIdFromEntity(obj) or NetworkGetNetworkIdFromEntity(obj) == 0) and timeout < 3000 do
            Wait(50)
            timeout = timeout + 50
        end

        local crateNetId = NetworkGetNetworkIdFromEntity(obj)
        if not crateNetId or crateNetId == 0 then
            print('^1[gang-raid] ERROR: Crate failed to get a network ID.^7')
            return
        end

        SetNetworkIdExistsOnAllMachines(crateNetId, true)
        NetworkSetNetworkIdDynamic(crateNetId, true)

        -- Settle the prop onto the ground
        FreezeEntityPosition(obj, false)
        Wait(100)
        PlaceObjectOnGroundProperly(obj)
        Wait(300)
        FreezeEntityPosition(obj, true)

        spawnedCrateHandle = obj
        spawnedCrateNetId  = crateNetId

        -- Attach loot target on the spawner client
        AttachCrateTarget(obj)

        -- Tell server the crate net ID so it can broadcast to everyone else
        TriggerServerEvent('gang_hideout:crateSpawned', crateNetId)

        if Config.Debug then print('[gang-raid] Crate spawned — netId: ' .. crateNetId) end
    end)

    -- ---- SPAWN GUARDS ----
    -- Pre-load all unique ped models
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

        local timeout = 0
        while (not NetworkGetNetworkIdFromEntity(ped) or NetworkGetNetworkIdFromEntity(ped) == 0) and timeout < 3000 do
            Wait(50)
            timeout = timeout + 50
        end

        local netId = NetworkGetNetworkIdFromEntity(ped)
        if netId and netId ~= 0 then
            table.insert(netIds, netId)
        end

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

-- =============================================
-- CONFIGURE PEDS — all clients (non-spawner)
-- =============================================
RegisterNetEvent('gang_hideout:configurePeds', function(netIds)
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

    -- Non-spawner clients also need to monitor guard deaths to attach loot targets
    StartLootMonitor()
end)

-- =============================================
-- CONFIGURE CRATE — all clients (non-spawner)
-- Resolves the networked crate net ID to a local
-- entity handle and attaches the loot target.
-- =============================================
RegisterNetEvent('gang_hideout:configureCrate', function(crateNetId)
    -- Give the spawner time to fully register the object on the network
    local waitTime = 0
    while not NetworkDoesEntityExistWithNetworkId(crateNetId) and waitTime < 5000 do
        Wait(100)
        waitTime = waitTime + 100
    end

    if not NetworkDoesEntityExistWithNetworkId(crateNetId) then
        print('^1[gang-raid] ERROR: Crate net ID ' .. crateNetId .. ' never appeared on this client.^7')
        return
    end

    local obj = NetworkGetEntityFromNetworkId(crateNetId)
    if not DoesEntityExist(obj) then
        print('^1[gang-raid] ERROR: Crate entity invalid after resolving net ID.^7')
        return
    end

    spawnedCrateHandle = obj
    spawnedCrateNetId  = crateNetId

    SetEntityVisible(obj, true, false)
    SetEntityLodDist(obj, 500)

    AttachCrateTarget(obj)

    if Config.Debug then print('[gang-raid] Crate configured on non-spawner client — netId: ' .. crateNetId) end
end)

-- =============================================
-- RAID WON — fires immediately when all guards die
-- =============================================
RegisterNetEvent('gang_hideout:raidWon', function()
    lootWindowOpen = true
    Notify('All guards down! Loot the crate — you have ' .. Config.LootWindowDuration .. ' seconds!', 'success')
    TriggerServerEvent('gang_hideout:claimBonus')
end)

-- =============================================
-- RAID FINISHED — fires after LootWindowDuration
-- =============================================
RegisterNetEvent('gang_hideout:raidFinished', function(netIds)
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
