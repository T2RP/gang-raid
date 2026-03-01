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
Config.Debug                = false
Config.MaxWaves             = 3
Config.WaveDelay            = 30     -- seconds between waves
Config.RaidCooldown         = 600    -- seconds before raid can start again
Config.DispatchEnabled      = true
Config.EscapeVehicleEnabled = true

-- =============================================
-- START RAID NPC
-- =============================================
Config.StartRaidNPC = {
    coords      = vector4(-197.43, -1711.59, 32.66, 134.99),
    model       = 'g_m_m_chigoon_02',
    targetLabel = 'Start Gang Hideout Raid'
}

-- =============================================
-- RAID LOCATIONS
-- Each location has its own waves, crates and escape vehicle.
-- A random one is picked each time a raid starts.
-- Guards per location across all 3 waves: ~15 total (was ~5)
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
            label  = "Gang Hideout"
        },
        lootCrates = {
            vector3(-613.25, -1624.78, 33.01),
            vector3(-605.89, -1633.7,  33.05),
            vector3(-596.6,  -1619.59, 33.01),
            vector3(-589.16, -1618.51, 33.01),
        },
        escapeVehicle = {
            model  = 'sultan',
            coords = vector4(-625.0, -1600.0, 26.89, 90.0),
        },
        waves = {
            -- Wave 1 — 5 guards (was 5)
            {
                { coords = vector4(-612.24, -1608.82, 26.89, 354.31), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_PISTOL' },
                { coords = vector4(-608.5,  -1607.96, 26.75,  62.64), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(-617.32, -1622.71, 33.01, 353.27), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_MICROSMG' },
                { coords = vector4(-605.39, -1627.38, 33.01, 141.29), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_PUMPSHOTGUN' },
                { coords = vector4(-617.15, -1633.37, 33.02,  42.08), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE' },
                -- 4 extra wave 1 guards
                { coords = vector4(-600.0,  -1610.0,  26.89, 180.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_PISTOL' },
                { coords = vector4(-620.0,  -1612.0,  26.89,  90.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_MICROSMG' },
                { coords = vector4(-595.0,  -1625.0,  33.01, 270.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(-622.0,  -1630.0,  33.01,  45.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_PISTOL' },
            },
            -- Wave 2 — 8 guards (was 5)
            {
                { coords = vector4(-590.38, -1618.95, 33.01,  97.2),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(-605.09, -1622.89, 33.01, 167.82), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_MACHINEPISTOL' },
                { coords = vector4(-615.64, -1628.5,  33.01,  98.47), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_MICROSMG' },
                { coords = vector4(-624.61, -1618.62, 33.01, 258.7),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_SAWNOFFSHOTGUN' },
                { coords = vector4(-609.17, -1612.5,  31.0,  119.8),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_COMBATPDW' },
                -- 3 extra wave 2 guards
                { coords = vector4(-598.0,  -1630.0,  33.01, 135.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE' },
                { coords = vector4(-618.0,  -1605.0,  26.89,  20.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(-604.0,  -1615.0,  26.89, 200.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_MACHINEPISTOL' },
            },
            -- Wave 3 — boss wave, 7 guards (was 4)
            {
                { coords = vector4(-611.49, -1614.83, 27.01, 347.29), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(-599.62, -1587.85, 26.75, 119.01), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(-605.2,  -1602.69, 34.49,  78.1),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(-610.55, -1608.18, 30.2,    4.95), model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 85 },
                -- 3 extra boss guards
                { coords = vector4(-593.0,  -1614.0,  33.01,  90.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(-620.0,  -1622.0,  33.01, 270.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 85 },
                { coords = vector4(-607.0,  -1635.0,  33.02,   0.0),  model = 'g_m_y_ballasout_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 200, accuracy = 90 },
            },
        },
    },

    -- ==========================================
    -- LOCATION 2: Grove Street Hideout
    -- ==========================================
    {
        name = "Grove Street Hideout",
        blip = {
            coords = vector3(112.46, -1940.54, 21.12),
            sprite = 161,
            color  = 2,
            scale  = 0.9,
            label  = "Gang Hideout"
        },
        lootCrates = {
            vector3(108.0, -1942.0, 21.12),
            vector3(115.0, -1936.0, 21.12),
            vector3(120.0, -1944.0, 21.12),
        },
        escapeVehicle = {
            model  = 'schwarzer',
            coords = vector4(105.0, -1930.0, 21.12, 180.0),
        },
        waves = {
            -- Wave 1 — 7 guards (was 3)
            {
                { coords = vector4(112.0, -1940.0, 21.12, 180.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_PISTOL' },
                { coords = vector4(116.0, -1943.0, 21.12, 270.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(109.0, -1937.0, 21.12,  90.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_MICROSMG' },
                -- 4 extra wave 1 guards
                { coords = vector4(120.0, -1940.0, 21.12,   0.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_PISTOL' },
                { coords = vector4(106.0, -1945.0, 21.12, 135.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_PUMPSHOTGUN' },
                { coords = vector4(118.0, -1932.0, 21.12, 225.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_MICROSMG' },
                { coords = vector4(111.0, -1948.0, 21.12,  45.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_SMG' },
            },
            -- Wave 2 — 7 guards (was 3)
            {
                { coords = vector4(114.0, -1945.0, 21.12, 200.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_ASSAULTRIFLE' },
                { coords = vector4(107.0, -1941.0, 21.12, 100.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_PUMPSHOTGUN' },
                { coords = vector4(118.0, -1938.0, 21.12,  45.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_COMBATPISTOL' },
                -- 4 extra wave 2 guards
                { coords = vector4(122.0, -1943.0, 21.12, 315.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(104.0, -1938.0, 21.12,  60.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_ASSAULTRIFLE' },
                { coords = vector4(115.0, -1950.0, 21.12, 180.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_MACHINEPISTOL' },
                { coords = vector4(109.0, -1930.0, 21.12,  90.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_COMBATPISTOL' },
            },
            -- Wave 3 — boss wave, 6 guards (was 2)
            {
                { coords = vector4(113.0, -1942.0, 21.12, 225.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(110.0, -1935.0, 21.12, 315.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 80 },
                -- 4 extra boss guards
                { coords = vector4(120.0, -1945.0, 21.12,  90.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 150, accuracy = 82 },
                { coords = vector4(106.0, -1942.0, 21.12, 270.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(116.0, -1930.0, 21.12, 180.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 85 },
                { coords = vector4(112.0, -1950.0, 21.12,   0.0), model = 'g_m_y_famca_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 200, accuracy = 90 },
            },
        },
    },

    -- ==========================================
    -- LOCATION 3: Vagos East LS
    -- ==========================================
    {
        name = "Vagos East LS",
        blip = {
            coords = vector3(373.42, -1991.68, 24.58),
            sprite = 161,
            color  = 5,
            scale  = 0.9,
            label  = "Gang Hideout"
        },
        lootCrates = {
            vector3(370.0, -1994.0, 24.58),
            vector3(376.0, -1989.0, 24.58),
            vector3(365.0, -1993.0, 24.58),
        },
        escapeVehicle = {
            model  = 'ruiner',
            coords = vector4(380.0, -1983.0, 24.58, 90.0),
        },
        waves = {
            -- Wave 1 — 7 guards (was 3)
            {
                { coords = vector4(373.0, -1991.0, 24.58,   0.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_PISTOL' },
                { coords = vector4(376.0, -1994.0, 24.58,  90.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_MICROSMG' },
                { coords = vector4(370.0, -1988.0, 24.58, 270.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_SMG' },
                -- 4 extra wave 1 guards
                { coords = vector4(380.0, -1992.0, 24.58, 180.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_PISTOL' },
                { coords = vector4(366.0, -1996.0, 24.58,  45.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_PUMPSHOTGUN' },
                { coords = vector4(377.0, -1984.0, 24.58, 135.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_MICROSMG' },
                { coords = vector4(362.0, -1990.0, 24.58,  90.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_SMG' },
            },
            -- Wave 2 — 6 guards (was 2)
            {
                { coords = vector4(378.0, -1991.0, 24.58,  45.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_ASSAULTRIFLE' },
                { coords = vector4(368.0, -1995.0, 24.58, 135.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_SAWNOFFSHOTGUN' },
                -- 4 extra wave 2 guards
                { coords = vector4(382.0, -1986.0, 24.58, 270.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_SMG' },
                { coords = vector4(364.0, -1998.0, 24.58,   0.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_MACHINEPISTOL' },
                { coords = vector4(374.0, -1999.0, 24.58, 180.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_ASSAULTRIFLE' },
                { coords = vector4(369.0, -1984.0, 24.58,  90.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_COMBATPISTOL' },
            },
            -- Wave 3 — boss wave, 6 guards (was 2)
            {
                { coords = vector4(374.0, -1992.0, 24.58, 180.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(371.0, -1989.0, 24.58, 270.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 80 },
                -- 4 extra boss guards
                { coords = vector4(380.0, -1995.0, 24.58,  90.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 150, accuracy = 82 },
                { coords = vector4(366.0, -1992.0, 24.58,   0.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_ASSAULTRIFLE',  armor = 150, accuracy = 80 },
                { coords = vector4(375.0, -1982.0, 24.58, 135.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_ADVANCEDRIFLE', armor = 150, accuracy = 85 },
                { coords = vector4(362.0, -1997.0, 24.58, 225.0), model = 'g_m_y_vagos_01', weapon = 'WEAPON_CARBINERIFLE',  armor = 200, accuracy = 90 },
            },
        },
    },
}

-- =============================================
-- LOOT TABLE
-- =============================================
Config.LootTable = {
    { name = "black_money", amount = { min = 200, max = 800 }, chance = 60 },
    { name = "meth",   amount = { min = 1,   max = 3   }, chance = 25 },
    { name = "joint", amount = { min = 1,   max = 5   }, chance = 30 },
    { name = "lockpick",    amount = { min = 1,   max = 2   }, chance = 20 },
    { name = "armour",       amount = { min = 1,   max = 1   }, chance = 15 },
    { name = "ammo-9", amount = { min = 20,  max = 50  }, chance = 35 },
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
