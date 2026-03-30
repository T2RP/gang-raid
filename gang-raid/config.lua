Config = {}

-- =============================================
-- FRAMEWORK DETECTION
-- =============================================
Config.Framework       = 'auto'   -- 'qb' | 'ox' | 'auto'
Config.TargetExport    = 'auto'   -- 'qb-target' | 'ox_target' | 'auto'
Config.InventoryExport = 'auto'   -- 'qb' | 'ox_inventory' | 'auto'

-- =============================================
-- GENERAL SETTINGS
-- =============================================
Config.Debug              = false
Config.RaidCooldown       = 600    -- seconds before another raid can start
Config.DispatchEnabled    = true
Config.LootWindowDuration = 120    -- seconds players have to loot after all guards are dead

-- =============================================
-- START RAID NPC
-- =============================================
Config.StartRaidNPC = {
    coords      = vector4(-197.43, -1711.59, 32.66, 134.99),
    model       = 'g_m_m_chigoon_02',
    targetLabel = 'Start Gang Hideout Raid',
}

-- =============================================
-- RAID LOCATIONS
-- Each location has its own guards and crates.
-- A random one is picked each time a raid starts.
-- =============================================
Config.Locations = {

    -- ==========================================
    -- LOCATION 1: Ballas Warehouse
    -- ==========================================
    {
        name = "Ballas Warehouse",
        blip = {
            coords = vector3(-608.95, -1608.51, 26.89),
            sprite = 161,
            color  = 1,
            scale  = 0.9,
            label  = "Gang Hideout",
        },
        lootCrates = {
            vector3(-613.25, -1624.78, 33.01),
            vector3(-605.89, -1633.7,  33.05),
            vector3(-596.6,  -1619.59, 33.01),
            vector3(-589.16, -1618.51, 33.01),
        },
        guards = {
            { coords = vector4(-611.49, -1614.83, 27.01, 347.29), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 100, accuracy = 70 },
            { coords = vector4(-599.62, -1587.85, 26.75, 119.01), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 100, accuracy = 70 },
            { coords = vector4(-605.2,  -1602.69, 34.49,  78.1),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 75 },
            { coords = vector4(-610.55, -1608.18, 30.2,    4.95), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 80 },
            { coords = vector4(-607.0,  -1635.0,  33.02,   0.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 200, accuracy = 90 },
        },
    },

}

-- =============================================
-- LOOT TABLE
-- =============================================
Config.LootTable = {
    { name = "black_money", amount = { min = 200, max = 800 }, chance = 60 },
    { name = "meth",        amount = { min = 1,   max = 3   }, chance = 25 },
    { name = "joint",       amount = { min = 1,   max = 5   }, chance = 30 },
    { name = "lockpick",    amount = { min = 1,   max = 2   }, chance = 20 },
    { name = "armour",      amount = { min = 1,   max = 1   }, chance = 15 },
    { name = "ammo-9",      amount = { min = 20,  max = 50  }, chance = 35 },
}

-- =============================================
-- POLICE DISPATCH (ps-dispatch)
-- =============================================
Config.Dispatch = {
    code     = '10-71',
    title    = 'Gang Hideout Raid in Progress',
    message  = 'Shots fired at a known gang location. Multiple armed suspects.',
    blip     = { sprite = 161, color = 1 },
    jobs     = { 'police', 'bcso', 'sasp' },
    cooldown = 60,
}
