-- =============================================
-- GANG HIDEOUT RAID | server.lua  v6.1
-- =============================================

-- =============================================
-- VERSION CHECKER
-- =============================================
local GITHUB_REPO     = 'zixja/gang-raid'
local RESOURCE_NAME   = GetCurrentResourceName()
local CURRENT_VERSION = GetResourceMetadata(RESOURCE_NAME, 'version', 0) or '1.0.0'

local function CheckVersion()
    local url = 'https://api.github.com/repos/' .. GITHUB_REPO .. '/releases/latest'
    print('^5[gang-raid] Checking for updates... (current: v' .. CURRENT_VERSION .. ')^7')

    PerformHttpRequest(url, function(statusCode, response, headers)
        if not response or response == '' then
            print('^3[gang-raid] Version check got no response.^7')
            return
        end
        if statusCode == 404 then
            print('^3[gang-raid] Version check: no releases found at github.com/' .. GITHUB_REPO .. '^7')
            return
        end
        if statusCode ~= 200 then
            print('^3[gang-raid] Version check failed — HTTP ' .. tostring(statusCode) .. '^7')
            return
        end
        local latestTag = response:match('"tag_name"%s*:%s*"([^"]+)"')
        if not latestTag then
            print('^3[gang-raid] Version check: could not parse tag from GitHub response.^7')
            return
        end
        local latest  = latestTag:gsub('^[vV]', '')
        local current = CURRENT_VERSION:gsub('^[vV]', '')
        if current == latest then
            print('^2[gang-raid] Up to date (v' .. current .. ')^7')
        else
            print(' ')
            print('^1[ GANG RAID ] ══════════════════════════════════^7')
            print('^1  UPDATE AVAILABLE!^7')
            print('^3  Running  : ^7v' .. current)
            print('^2  Latest   : ^7v' .. latest)
            print('^5  Download : ^7https://github.com/' .. GITHUB_REPO .. '/releases/latest')
            print('^1═════════════════════════════════════════════════^7')
            print(' ')
        end
    end, 'GET', '', {
        ['User-Agent'] = 'FiveM/' .. RESOURCE_NAME .. '-version-check',
        ['Accept']     = 'application/vnd.github+json',
    })
end

CreateThread(function()
    Wait(5000)
    CheckVersion()
end)

-- =============================================
-- STATE
-- =============================================
local QBCore          = nil
local raidActive      = false
local raidCooldownEnd = 0
local activeLocation  = nil
local raidStarterSrc  = nil
local guardNetIds     = {}
local crateNetId      = nil   -- net ID of the single networked crate

-- =============================================
-- FRAMEWORK INIT
-- =============================================
CreateThread(function()
    Wait(500)
    local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and obj then
        QBCore = obj
        if Config.Debug then print('[gang-raid] QBCore/QBox loaded.') end
    else
        if Config.Debug then print('[gang-raid] QBCore not found — ox_inventory only mode.') end
    end
end)

-- =============================================
-- HELPERS
-- =============================================
local function GetPlayer(src)
    if QBCore then return QBCore.Functions.GetPlayer(src) end
    return nil
end

local function NotifyClient(src, msg, ntype)
    ntype = ntype or 'primary'
    if QBCore then
        TriggerClientEvent('QBCore:Notify', src, msg, ntype)
    else
        TriggerClientEvent('ox_lib:notify', src, { title = msg, type = ntype })
    end
end

local function NotifyAll(msg, ntype)
    ntype = ntype or 'primary'
    if QBCore then
        TriggerClientEvent('QBCore:Notify', -1, msg, ntype)
    else
        TriggerClientEvent('ox_lib:notify', -1, { title = msg, type = ntype })
    end
end

local function AddItem(src, itemName, amount)
    if Config.InventoryExport == 'ox_inventory'
    or (Config.InventoryExport == 'auto' and GetResourceState('ox_inventory') == 'started') then
        local ok = pcall(function() exports['ox_inventory']:AddItem(src, itemName, amount) end)
        if ok then return true end
    end
    local Player = GetPlayer(src)
    if Player then
        Player.Functions.AddItem(itemName, amount)
        return true
    end
    return false
end

local function SendItemNotify(src, itemName, amount, action)
    if QBCore then
        local item = QBCore.Shared.Items and QBCore.Shared.Items[itemName]
        if item then
            TriggerClientEvent('inventory:client:ItemBox', src, item, action or 'add', amount)
        end
    end
end

local function SendDispatch(src, coords)
    if not Config.DispatchEnabled then return end
    if GetResourceState('ps-dispatch') ~= 'started' then return end
    local ok = pcall(function()
        exports['ps-dispatch']:CustomAlert({
            coords       = coords,
            message      = Config.Dispatch.message,
            dispatchCode = Config.Dispatch.code,
            description  = Config.Dispatch.title,
            radius       = 0,
            sprite       = Config.Dispatch.blip.sprite,
            color        = Config.Dispatch.blip.color,
            scale        = 1.0,
            length       = 3,
            jobs         = Config.Dispatch.jobs,
        })
    end)
    if not ok then
        pcall(function()
            TriggerEvent('dispatch:server:notify', {
                dispatchCode = Config.Dispatch.code,
                description  = Config.Dispatch.title,
                message      = Config.Dispatch.message,
                jobs         = Config.Dispatch.jobs,
                coords       = coords,
                sprite       = Config.Dispatch.blip.sprite,
                colour       = Config.Dispatch.blip.color,
            })
        end)
    end
end

-- =============================================
-- LOOT ROLL
-- =============================================
local function RollLoot(src)
    local shuffled = {}
    for _, v in ipairs(Config.LootTable) do shuffled[#shuffled + 1] = v end
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    for _, item in ipairs(shuffled) do
        if math.random(100) <= item.chance then
            local amount = math.random(item.amount.min, item.amount.max)
            if AddItem(src, item.name, amount) then
                SendItemNotify(src, item.name, amount, 'add')
                NotifyClient(src, 'Found ' .. amount .. 'x ' .. item.name, 'success')
                return true
            end
        end
    end
    return false
end

-- =============================================
-- END RAID
-- FIX: Previously called CleanupRaid with a 2s
-- delay, deleting guards/crates before players
-- could loot them. Now we split into two phases:
--   Phase 1 (raidWon)     — instant, claims bonus
--   Phase 2 (raidFinished)— after LootWindowDuration,
--                           actually deletes entities
-- =============================================
local function EndRaid()
    raidActive     = false
    activeLocation = nil
    raidStarterSrc = nil

    TriggerClientEvent('gang_hideout:raidWon', -1)

    if Config.Debug then
        print('[gang-raid] Raid won — loot window open for ' .. Config.LootWindowDuration .. 's')
    end

    SetTimeout(Config.LootWindowDuration * 1000, function()
        TriggerClientEvent('gang_hideout:raidFinished', -1, guardNetIds)
        guardNetIds = {}
        crateNetId  = nil
    end)
end

-- =============================================
-- NET EVENTS
-- =============================================
RegisterNetEvent('gang_hideout:startRaid', function()
    local src = source

    if raidActive then
        NotifyClient(src, 'A raid is already in progress!', 'error')
        return
    end

    local now = os.time()
    if now < raidCooldownEnd then
        NotifyClient(src, 'Raid on cooldown for ' .. (raidCooldownEnd - now) .. 's.', 'error')
        return
    end

    raidActive      = true
    raidCooldownEnd = now + Config.RaidCooldown
    guardNetIds     = {}
    crateNetId      = nil
    raidStarterSrc  = src

    local locationIndex = math.random(1, #Config.Locations)
    activeLocation      = Config.Locations[locationIndex]

    if Config.Debug then
        print('[gang-raid] Raid started by ' .. src .. ' at: ' .. activeLocation.name)
    end

    TriggerClientEvent('gang_hideout:raidStarted', -1, locationIndex)

    SetTimeout(800, function()
        -- Pass both the guards list and the single crate coord to the spawner
        TriggerClientEvent('gang_hideout:spawnGuards', src, activeLocation.guards, activeLocation.crateCoord)
    end)

    SetTimeout(3000, function()
        SendDispatch(src, activeLocation.blip.coords)
    end)
end)

-- Spawner reports back all guard net IDs
RegisterNetEvent('gang_hideout:guardsSpawned', function(netIds)
    local src = source
    if src ~= raidStarterSrc then return end
    guardNetIds = netIds
    if Config.Debug then
        print('[gang-raid] ' .. #netIds .. ' guards spawned.')
    end
    TriggerClientEvent('gang_hideout:configurePeds', -1, netIds)
end)

-- Spawner reports the crate net ID — broadcast to all other clients
RegisterNetEvent('gang_hideout:crateSpawned', function(netId)
    local src = source
    if src ~= raidStarterSrc then return end
    crateNetId = netId
    if Config.Debug then
        print('[gang-raid] Crate net ID received: ' .. netId)
    end
    -- Tell every client EXCEPT the spawner (who already has the target attached)
    TriggerClientEvent('gang_hideout:configureCrate', -1, netId)
end)

-- Spawner client reports all guards are dead → begin loot window then cleanup
RegisterNetEvent('gang_hideout:waveClear', function()
    local src = source
    if src ~= raidStarterSrc then return end
    if not raidActive then return end
    EndRaid()
end)

-- Crate loot
RegisterNetEvent('gang_hideout:giveLoot', function()
    local src    = source
    local Player = GetPlayer(src)
    if not Player and Config.InventoryExport ~= 'ox_inventory' then return end
    if not RollLoot(src) then
        NotifyClient(src, 'The crate was empty.', 'error')
    end
end)

-- Guard body loot
RegisterNetEvent('gang_hideout:lootGuard', function()
    local src    = source
    local Player = GetPlayer(src)
    if not Player and Config.InventoryExport ~= 'ox_inventory' then return end

    if math.random(100) > 50 then
        NotifyClient(src, 'Nothing of value on the body.', 'error')
        return
    end

    local shuffled = {}
    for _, v in ipairs(Config.LootTable) do
        shuffled[#shuffled + 1] = {
            name   = v.name,
            amount = { min = v.amount.min, max = math.max(v.amount.min, math.floor(v.amount.max * 0.5)) },
            chance = math.floor(v.chance * 0.5),
        }
    end
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local rewarded = false
    for _, item in ipairs(shuffled) do
        if math.random(100) <= item.chance then
            local amount = math.random(item.amount.min, item.amount.max)
            if AddItem(src, item.name, amount) then
                SendItemNotify(src, item.name, amount, 'add')
                NotifyClient(src, 'Found ' .. amount .. 'x ' .. item.name .. ' on the body.', 'success')
                rewarded = true
                break
            end
        end
    end

    if not rewarded then
        NotifyClient(src, 'Nothing of value on the body.', 'error')
    end
end)

-- Completion bonus — FIX: now triggered by raidWon on the client, not raidFinished,
-- so it fires when guards die rather than when entities are deleted.
RegisterNetEvent('gang_hideout:claimBonus', function()
    local src    = source
    local Player = GetPlayer(src)
    if not Player then return end

    local bonus = math.random(500, 1500)
    if AddItem(src, 'markedmoney', bonus) then
        SendItemNotify(src, 'markedmoney', bonus, 'add')
        NotifyClient(src, 'Raid bonus: $' .. bonus .. ' in marked bills!', 'success')
    end
end)
