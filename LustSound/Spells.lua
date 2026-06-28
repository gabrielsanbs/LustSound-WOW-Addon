local ADDON_NAME, NS = ...

-- ============================================================================
-- Spells.lua
--
-- Central, extensible registry of Bloodlust-equivalent spell IDs.
-- Detection is done by Spell ID (never by localized name) so the addon works
-- on any client language. Names and icons shown in the UI are always obtained
-- dynamically via C_Spell.GetSpellInfo.
--
-- To add new abilities in the future (drums, items, new lust spells), simply
-- add a new entry to NS.LustSpells and, if it should appear in the options
-- list, add its ID to NS.LustSpellOrder.
-- ============================================================================

NS.LustSpells = NS.LustSpells or {}

-- Spell IDs that should trigger the sound.
--   2825   = Bloodlust          (Shaman)
--   32182  = Heroism             (Shaman)
--   80353  = Time Warp           (Mage)
--   264667 = Primal Rage         (Hunter Ferocity pet)
--   390386 = Fury of the Aspects (Evoker)
NS.LustSpells[2825]   = true
NS.LustSpells[32182]  = true
NS.LustSpells[80353]  = true
NS.LustSpells[264667] = true
NS.LustSpells[390386] = true

-- Debuffs applied as side effects of lust-family spells. In Midnight, allied
-- instant casts can be hidden from addon code, while these exhaustion debuffs
-- are visible. CLEU aura detection maps them back to the user-facing cast.
NS.LustExhaustionDebuffs = NS.LustExhaustionDebuffs or {}
NS.LustExhaustionDebuffs[57723]  = 32182  -- Exhaustion (Heroism)
NS.LustExhaustionDebuffs[57724]  = 2825   -- Sated (Bloodlust)
NS.LustExhaustionDebuffs[80354]  = 80353  -- Temporal Displacement (Time Warp)
NS.LustExhaustionDebuffs[95809]  = 264667 -- Hunter Pet Insanity (legacy pet lust)
NS.LustExhaustionDebuffs[160455] = 264667 -- Fatigued (legacy pet lust)
NS.LustExhaustionDebuffs[264689] = 264667 -- Fatigued (Primal Rage)
NS.LustExhaustionDebuffs[390435] = 390386 -- Exhaustion (Fury of the Aspects)

-- Ordered list used to render the detected-abilities area in the options panel.
NS.LustSpellOrder = NS.LustSpellOrder or {
    2825,
    32182,
    80353,
    264667,
    390386,
}

-- Returns the localized display name for a spell ID.
-- Falls back to "Spell <id>" when the API returns nil or an invalid argument
-- is supplied, so the UI never errors on missing data.
function NS.GetSpellDisplayName(spellID)
    if type(spellID) ~= "number" then
        return NS.L.MSG_SPELL_ID_FALLBACK:format(0)
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if info and info.name then
        return info.name
    end
    return NS.L.MSG_SPELL_ID_FALLBACK:format(spellID)
end

-- Returns the icon FileDataID for a spell ID, or nil if unavailable.
function NS.GetSpellDisplayIcon(spellID)
    if type(spellID) ~= "number" then
        return nil
    end
    local info = C_Spell.GetSpellInfo(spellID)
    if info and info.iconID then
        return info.iconID
    end
    return nil
end
