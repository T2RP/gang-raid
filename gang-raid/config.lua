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
        -- Single networked crate that guards protect — all players see the same object
        crateCoord = vector3(-610.27, -1605.41, 26.75),
        guards = {
            { coords = vector4(-611.49, -1614.83, 27.01, 347.29), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 100, accuracy = 70 },
            { coords = vector4(-599.62, -1587.85, 26.75, 119.01), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 100, accuracy = 70 },
            { coords = vector4(-605.2,  -1602.69, 34.49,  78.1),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 75 },
            { coords = vector4(-610.55, -1608.18, 30.2,    4.95), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 80 },
            { coords = vector4(-607.0,  -1635.0,  33.02,   0.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 200, accuracy = 90 },
        },
    },

    {
        name = "Vagos Warehouse",
        blip = {
            coords = vector3(367.96, -2016.8, 22.06),
            sprite = 161,
            color  = 1,
            scale  = 0.9,
            label  = "Vagos Gang Hideout",
        },
        -- Single networked crate that guards protect — all players see the same object
        crateCoord = vector3(367.96, -2016.8, 22.06),
        guards = {
            { coords = vector4(367.96, -2016.8, 22.06, 347.29), model = 'g_m_y_mexgoon_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 100, accuracy = 70 },
            { coords = vector4(355.89, -2000.5, 22.06, 119.01), model = 'g_m_y_mexgoon_02', weapon = 'WEAPON_CARBINERIFLE',  armor = 100, accuracy = 70 },
            { coords = vector4(362.45, -2012.3, 29.56,  78.1),  model = 'g_m_y_mexgoon_03', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 75 },
            { coords = vector4(367.96, -2016.8, 22.06,    4.95), model = 'g_m_y_mexgoon_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 80 },
            { coords = vector4(379.12, -2024.94, 22.39, 290.45), model = 'g_m_y_mexgoon_02', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 200, accuracy = 90 },
        },
    },

}

-- =============================================
-- CRATE CONTENTS
-- Every item listed here is guaranteed to be
-- inside the crate. Amount is rolled once when
-- the raid starts and stays fixed for that raid.
-- Players take one item at a time — first come
-- first served until the crate is empty.
-- =============================================
Config.CrateContents = {
    { name = "black_money", amount = { min = 500, max = 1500 } },
    { name = "armour",      amount = { min = 1,   max = 2   } },
}

-- =============================================
-- GUARD BODY LOOT TABLE
-- Chance-based — guards may or may not carry
-- items. Separate from crate contents.
-- =============================================
Config.GuardLootTable = {
    { name = "meth",     amount = { min = 1,  max = 3  }, chance = 25 },
    { name = "joint",    amount = { min = 1,  max = 5  }, chance = 30 },
    { name = "lockpick", amount = { min = 1,  max = 2  }, chance = 20 },
    { name = "ammo-9",   amount = { min = 10, max = 40 }, chance = 40 },
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
