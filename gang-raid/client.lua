-- =============================================
-- GANG HIDEOUT RAID | client.lua  v6.0
-- Supports: qb-target / ox_target (auto-detect)
--           QBCore / QBox / ox_lib notify
-- =============================================

local QBCore             = nil
local lootedCrates       = {}
local spawnedCrates      = {}   -- object handles so we can delete on cleanup
local spawnedGuards      = {}   -- { ped = handle, looted = bool }
local lootedGuards       = {}   -- [ped handle] = true
local activeLocation     = nil
-- no blip — waypoint used instead
local lootMonitorRunning = false
local aiLoopRunning      = false
local isRaidStarter      = false  -- true only on the client who triggered the raid

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
    local playerPed = PlayerPedId()
    if scenario then
        TaskStartScenarioInPlace(playerPed, scenario, 0, true)
    else
        -- ClearPedTasksImmediately forcefully exits any active scenario
        -- ClearPedTasks alone queues the stop but the scenario can persist
        ClearPedTasksImmediately(PlayerPedId())
    end
end

-- =============================================
-- OX_LIB SKILLCHECK + PROGRESSBAR LOOT SEQUENCE
--
-- Flow:
--   1. Skillcheck pops (must pass to continue)
--   2. Emote starts
--   3. Progress bar runs — player can press E/Backspace to cancel
--   4. Emote always cleared on exit regardless of outcome
--
-- NOTE: We do NOT pass anim.scenario to the progressBar.
-- Letting ox_lib manage the animation internally conflicts
-- with our manual scenario task and prevents clean cancellation.
-- The scenario is started before the bar and cleared after.
-- =============================================
local function DoLootSequence(params)
    local hasOxLib = GetResourceState('ox_lib') == 'started'

    if not hasOxLib then
        params.onSuccess()
        return
    end

    -- 1. Skillcheck first (no emote yet — looks weird to animate before passing)
    local passed = exports['ox_lib']:skillCheck({ 'easy', 'medium' }, { 'e' })

    if not passed then
        Notify('You failed the check.', 'error')
        if params.onFail then params.onFail() end
        return
    end

    -- 2. Start emote AFTER passing skillcheck
    PlayEmote(params.emote)

    -- 3. Progress bar — NO anim block so ox_lib doesn't fight our scenario
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

    -- 4. Always clear emote immediately when bar finishes or is cancelled
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
-- GUARD MONITOR
-- Runs on the spawner client only.
-- Every second checks all guards in the current wave:
--   - If newly dead → add Search Body loot target
--   - If ALL dead   → report gang_hideout:waveClear
--     to server so it can advance to the next wave
--
-- The server cannot reliably detect entity death for
-- client-spawned peds, so the client is authoritative.
-- =============================================
local waveClearReported  = false
local seenAlive          = false

local function StartLootMonitor()
    if lootMonitorRunning then return end
    lootMonitorRunning = true
    waveClearReported  = false
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
                    -- Ped was deleted externally, count as dead
                    deadCount = deadCount + 1
                elseif IsEntityDead(ped) then
                    deadCount = deadCount + 1

                    -- Add loot target once per guard
                    if not entry.looted and not lootedGuards[ped] then
                        lootedGuards[ped] = true
                        entry.looted      = true

                        local p     = ped
                        local e     = entry
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
                end
            end

            -- All guards dead — only the spawner client reports this.
            -- seenAlive gate: we must observe at least one living guard
            -- before we can declare the wave clear. This prevents a false
            -- clear on the very first tick before peds have fully spawned.
            if deadCount < totalGuards then
                seenAlive = true
            end

            if isRaidStarter and seenAlive and deadCount >= totalGuards and totalGuards > 0 and not waveClearReported then
                waveClearReported = true
                if Config.Debug then
                    print('[gang-raid] Wave cleared — ' .. totalGuards .. ' guards down')
                end
                TriggerServerEvent('gang_hideout:waveClear')
            end

            ::continue::
        end
    end)
end

-- =============================================
-- WAYPOINT HELPERS
-- Sets a GPS waypoint to the raid location.
-- Cleared when the raid ends.
-- =============================================
local function SetRaidWaypoint(coords)
    SetNewWaypoint(coords.x, coords.y)
end

local function ClearRaidBlip()
    ClearGpsPlayerWaypoint()
end

-- =============================================
-- RAID STARTED — fires on ALL clients
-- =============================================
RegisterNetEvent('gang_hideout:raidStarted', function(locationIndex)
    lootedCrates       = {}
    spawnedCrates      = {}
    lootedGuards       = {}
    spawnedGuards      = {}
    lootMonitorRunning = false
    aiLoopRunning      = false
    isRaidStarter      = false
    activeLocation     = Config.Locations[locationIndex]

    SetRaidWaypoint(activeLocation.blip.coords)

    for i, coords in pairs(activeLocation.lootCrates) do
        local crateId = "crate_" .. i
        -- Spawn slightly above ground so PlaceObjectOnGroundProperly
        -- has room to raycast downward and find the surface.
        -- We unfreeze briefly, place, wait for physics to settle,
        -- then refreeze so the crate sits flush on the ground.
        local obj = CreateObject(GetHashKey('ch_prop_ch_crate_01a'), coords.x, coords.y, coords.z + 2.0, true, true, true)
        SetEntityAsMissionEntity(obj, true, true)

        -- Let physics run for a tick so the engine registers the object
        FreezeEntityPosition(obj, false)
        Wait(50)
        PlaceObjectOnGroundProperly(obj)
        Wait(200)  -- wait for the prop to settle onto the surface
        FreezeEntityPosition(obj, true)

        table.insert(spawnedCrates, obj)  -- track for cleanup on raid end

        AddEntityTarget(obj, "Search Crate", "fas fa-box-open", 2.0, function(entity)
            if lootedCrates[crateId] then
                Notify("This crate is already empty.", "error")
                return
            end

            DoLootSequence({
                emote         = 'PROP_HUMAN_BUM_BIN',   -- rummaging through a container
                progressLabel = 'Searching crate...',
                duration      = 6000,
                onSuccess     = function()
                    lootedCrates[crateId] = true
                    TriggerServerEvent("gang_hideout:giveLoot")
                    RemoveEntityTarget(entity)
                    DeleteEntity(entity)
                end,
                -- onFail: do nothing, player can try again
            })
        end)
    end

    if Config.Debug then print('[gang-raid] Raid started at: ' .. activeLocation.name) end
end)

-- =============================================
-- SPAWN WAVE — raid-starter client only
-- =============================================
RegisterNetEvent('gang_hideout:spawnWave', function(guards, waveNum)
    isRaidStarter      = true
    local groupHash    = SetupGuardRelationships()
    spawnedGuards      = {}
    waveClearReported  = false
    lootMonitorRunning = false  -- kill any running monitor so this wave gets a fresh one
    aiLoopRunning      = false  -- same for AI loop
    local netIds       = {}

    -- ── Step 1: Pre-load all unique models before spawning any peds.
    -- Requesting them all upfront fills the streaming budget once
    -- rather than hammering it one-by-one inside the spawn loop.
    local uniqueModels = {}
    for _, guard in pairs(guards) do
        local hash = GetHashKey(guard.model)
        if not uniqueModels[hash] then
            uniqueModels[hash] = true
            RequestModel(hash)
        end
    end
    -- Wait until every model is loaded before proceeding
    local allLoaded = false
    local loadTimeout = 0
    while not allLoaded and loadTimeout < 10000 do
        allLoaded = true
        for hash, _ in pairs(uniqueModels) do
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

    -- ── Step 2: Spawn peds one at a time.
    -- For each ped we:
    --   a) Force it visible immediately with SetEntityVisible
    --   b) Set a very high LOD distance so it never culls out
    --   c) Wait up to 1s for the model to actually render
    --      before spawning the next one
    -- This is the only reliable way to prevent invisible peds
    -- when spawning many NPCs in a small area simultaneously.
    for _, guard in pairs(guards) do
        local model = GetHashKey(guard.model)

        local ped = CreatePed(4, model,
            guard.coords.x, guard.coords.y, guard.coords.z, guard.coords.w,
            true, true)

        SetEntityAsMissionEntity(ped, true, true)
        NetworkRegisterEntityAsNetworked(ped)

        -- Force visibility — prevents streaming culling from hiding the ped
        SetEntityVisible(ped, true, false)
        SetEntityLodDist(ped, 500)          -- never cull beyond 500 units
        SetPedConfigFlag(ped, 320, true)    -- disable ambient occlusion culling

        GiveWeaponToPed(ped, GetHashKey(guard.weapon), 200, true, true)
        SetPedArmour(ped, guard.armor    or 100)
        SetPedAccuracy(ped, guard.accuracy or 70)

        ApplyCombatSettings(ped, groupHash)
        TaskGuardCombat(ped)

        table.insert(spawnedGuards, { ped = ped, looted = false })

        -- Wait for valid network ID
        local timeout = 0
        while (not NetworkGetNetworkIdFromEntity(ped) or NetworkGetNetworkIdFromEntity(ped) == 0) do
            Wait(50)
            timeout = timeout + 50
            if timeout > 3000 then break end
        end

        local netId = NetworkGetNetworkIdFromEntity(ped)
        if netId and netId ~= 0 then
            table.insert(netIds, netId)
        end

        -- Wait for the ped to be fully rendered before spawning the next.
        -- IsEntityVisible returns true once the model is actually drawn.
        -- Cap at 1000ms so a bad ped doesn't stall the whole wave.
        local renderWait = 0
        while not IsEntityVisible(ped) and renderWait < 1000 do
            Wait(50)
            renderWait = renderWait + 50
        end

        -- Extra gap so the streaming budget isn't overwhelmed
        Wait(200)
    end

    -- Release model refs now that all peds are created
    for hash, _ in pairs(uniqueModels) do
        SetModelAsNoLongerNeeded(hash)
    end

    TriggerServerEvent('gang_hideout:waveSpawned', netIds)
    StartLootMonitor()
    StartGuardAILoop()
    Notify('Wave ' .. waveNum .. ' — enemies inbound!', 'error')

    if Config.Debug then print('[gang-raid] Wave ' .. waveNum .. ' spawned ' .. #netIds .. ' peds.') end
end)

-- =============================================
-- CONFIGURE PEDS — ALL clients
-- =============================================
RegisterNetEvent('gang_hideout:configurePeds', function(netIds)
    Wait(800)
    local groupHash = SetupGuardRelationships()

    for _, netId in ipairs(netIds) do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local ped = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                -- Force visibility on all clients, not just spawner
                SetEntityVisible(ped, true, false)
                SetEntityLodDist(ped, 500)
                SetPedConfigFlag(ped, 320, true)

                ApplyCombatSettings(ped, groupHash)

                local alreadyTracked = false
                for _, entry in ipairs(spawnedGuards) do
                    if entry.ped == ped then alreadyTracked = true break end
                end
                if not alreadyTracked then
                    table.insert(spawnedGuards, { ped = ped, looted = false })
                end
            end
        end
    end

    -- Note: StartLootMonitor is intentionally NOT called here.
    -- Only the spawner client runs the monitor (via spawnWave).
    -- Non-spawner clients just apply combat settings and track peds for AI.
end)

-- =============================================
-- SPAWN ESCAPE VEHICLE — raid-starter client only
-- =============================================
RegisterNetEvent('gang_hideout:spawnEscapeVehicle', function(vehicleData)
    if not Config.EscapeVehicleEnabled then return end

    local model = GetHashKey(vehicleData.model)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local veh = CreateVehicle(model,
        vehicleData.coords.x, vehicleData.coords.y,
        vehicleData.coords.z, vehicleData.coords.w,
        true, true)
    SetEntityAsMissionEntity(veh, true, true)
    NetworkRegisterEntityAsNetworked(veh)
    SetModelAsNoLongerNeeded(model)

    local driverModelName = (activeLocation
        and activeLocation.waves
        and activeLocation.waves[1]
        and activeLocation.waves[1][1]
        and activeLocation.waves[1][1].model)
        or 'g_m_y_ballasout_01'

    local driverModel = GetHashKey(driverModelName)
    RequestModel(driverModel)
    while not HasModelLoaded(driverModel) do Wait(0) end

    local driver = CreatePedInsideVehicle(veh, 4, driverModel, -1, true, true)
    SetEntityAsMissionEntity(driver, true, true)
    NetworkRegisterEntityAsNetworked(driver)
    GiveWeaponToPed(driver, GetHashKey('WEAPON_ASSAULTRIFLE'), 200, true, true)
    SetPedArmour(driver, 200)

    local timeout = 0
    while (not NetworkGetNetworkIdFromEntity(driver) or NetworkGetNetworkIdFromEntity(driver) == 0) do
        Wait(50)
        timeout = timeout + 50
        if timeout > 3000 then break end
    end

    local driverNetId = NetworkGetNetworkIdFromEntity(driver)
    SetModelAsNoLongerNeeded(driverModel)
    TriggerServerEvent('gang_hideout:escapeVehicleSpawned', driverNetId)
end)

-- =============================================
-- DRIVE ESCAPE VEHICLE — all clients
-- =============================================
RegisterNetEvent('gang_hideout:driveEscapeVehicle', function(driverNetId, x, y, z)
    Wait(500)
    if not NetworkDoesEntityExistWithNetworkId(driverNetId) then return end
    local driver = NetworkGetEntityFromNetworkId(driverNetId)
    if not DoesEntityExist(driver) then return end
    local veh = GetVehiclePedIsIn(driver, false)
    if DoesEntityExist(veh) then
        TaskVehicleDriveToCoordLongrange(driver, veh, x, y, z, 30.0, 786603, 20.0)
    end
end)

-- =============================================
-- RAID FINISHED — all clients
-- =============================================
-- =============================================
-- FULL RAID CLEANUP
-- Deletes all client-side entities (crates, guards)
-- and removes the blip. Called on raidFinished and
-- also exported so server can trigger it directly.
-- =============================================
local function CleanupRaid()
    lootMonitorRunning = false
    aiLoopRunning      = false

    -- Delete remaining crate props
    for _, obj in ipairs(spawnedCrates) do
        if DoesEntityExist(obj) then
            RemoveEntityTarget(obj)
            SetEntityAsMissionEntity(obj, false, true)
            DeleteObject(obj)
        end
    end
    spawnedCrates = {}
    lootedCrates  = {}

    -- Delete remaining guard peds
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

    -- Clear GPS waypoint
    ClearRaidBlip()

    activeLocation = nil
end

RegisterNetEvent('gang_hideout:raidFinished', function()
    CleanupRaid()
    Notify('Gang hideout cleared! Check your inventory for your bonus.', 'success')
    TriggerServerEvent('gang_hideout:claimBonus')
end)

-- =============================================
-- CLEANUP DEAD PEDS — all clients
-- Called 30s after each wave is cleared so
-- corpses don't litter the area forever.
-- =============================================
RegisterNetEvent('gang_hideout:cleanupPeds', function(netIds)
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
