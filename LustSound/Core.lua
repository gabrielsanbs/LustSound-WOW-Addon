local ADDON_NAME, NS = ...
local HasAnySecretValues = hasanysecretvalues or function()
    return false
end

-- ============================================================================
-- Core.lua
--
-- SavedVariables handling, defaults, event handling, GUID cache, spell-cast
-- detection (visible UNIT_SPELLCAST_SUCCEEDED + aura polling fallback),
-- anti-spam, sound playback, context filters, chat messages, debug and slash
-- commands.
--
-- ============================================================================
-- ARCHITECTURE NOTE (Patch 12.0 / Midnight)
-- ============================================================================
-- COMBAT_LOG_EVENT_UNFILTERED (CLEU), CombatLogGetCurrentEventInfo(), some
-- spellcast events, and some Blizzard UI values have been restricted for addon
-- code in Patch 12.0+.
--
-- Detection uses visible UNIT_SPELLCAST_SUCCEEDED for direct casts. Allied
-- instant casts can be hidden, so a timer polls non-player group unit tokens
-- for the visible exhaustion debuffs and dedupes them.
-- ============================================================================

NS.DB = nil

-- Default configuration. Nested tables are intentionally separate values so
-- they are never shared by reference across copies.
NS.defaultDB = {
    enabled = true,
    selectedSound = "faaaahhh_screaming.ogg",
    soundChannel = "Master",
    preventOverlap = true,
    groupOnly = true,
    showChatMessage = false,
    debugMode = false,
    debugLogs = {},
    contexts = {
        world = true,
        party = true,
        raid = true,
        arena = true,
        pvp = true,
        scenario = true,
    },
}

-- Minimum time (seconds) between two lust-family triggers (global anti-spam).
local ANTI_SPAM_INTERVAL = 1.5

-- After zoning, resurrecting into a new map, or roster changes, WoW can briefly
-- hide and then re-show existing exhaustion auras. Treat those reappearing auras
-- as baseline state instead of a fresh lust cast.
local AURA_BASELINE_GRACE_SECONDS = 15
local AURA_START_TIME_FUDGE_SECONDS = 0.5

-- Cache of valid caster GUIDs (player, player pet, group members and their pets).
-- Stored as a set: guid -> true. Used by group filtering and debug labels.
NS.GroupGUIDs = NS.GroupGUIDs or {}

-- Runtime state (kept local to avoid polluting the namespace).
local lastSoundHandle = nil
local lastActivationTime = 0
local seenExhaustionAuras = {}
local seededAuraGUIDs = {}
local auraFallbackTicker = nil
local auraSeedPending = false
local auraBaselineStartedAt = 0
local auraBaselineUntil = 0
local unitEventFrames = {}
local debugThrottle = {}

local trackedUnitTokens = {
    "player",
    "pet",
}
local auraFallbackUnitTokens = {
    "player",
    "pet",
}

for i = 1, 4 do
    trackedUnitTokens[#trackedUnitTokens + 1] = "party" .. i
    trackedUnitTokens[#trackedUnitTokens + 1] = "partypet" .. i
    auraFallbackUnitTokens[#auraFallbackUnitTokens + 1] = "party" .. i
    auraFallbackUnitTokens[#auraFallbackUnitTokens + 1] = "partypet" .. i
end

for i = 1, 40 do
    trackedUnitTokens[#trackedUnitTokens + 1] = "raid" .. i
    trackedUnitTokens[#trackedUnitTokens + 1] = "raidpet" .. i
    auraFallbackUnitTokens[#auraFallbackUnitTokens + 1] = "raid" .. i
    auraFallbackUnitTokens[#auraFallbackUnitTokens + 1] = "raidpet" .. i
end

-- ----------------------------------------------------------------------------
-- Table helpers
-- ----------------------------------------------------------------------------

-- Deep copy of a simple table value (no metatable handling, safe for our data).
local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

-- Merge defaults into the user DB without overwriting existing valid values,
-- adding missing keys and correcting invalid types. Nested tables are merged
-- recursively and never shared by reference.
local function MergeDefaults(db, defaults)
    if type(db) ~= "table" then
        db = {}
    end
    for k, defaultVal in pairs(defaults) do
        if type(defaultVal) == "table" then
            if type(db[k]) ~= "table" then
                db[k] = DeepCopy(defaultVal)
            else
                MergeDefaults(db[k], defaultVal)
            end
        else
            if type(db[k]) ~= type(defaultVal) then
                db[k] = defaultVal
            end
        end
    end
    return db
end

-- Returns a fresh deep copy of the default configuration.
function NS.GetDefaults()
    return DeepCopy(NS.defaultDB)
end

-- ----------------------------------------------------------------------------
-- Unit name helper
-- ----------------------------------------------------------------------------

-- Returns the full name of a unit token (name + server when cross-realm).
-- Returns nil when the unit doesn't exist or has no name.
local function GetUnitFullName(unitToken)
    if not unitToken or not UnitExists(unitToken) then
        return nil
    end
    local name, server = UnitName(unitToken)
    if not name or name == "" then
        return nil
    end
    if server and server ~= "" then
        return name .. "-" .. server
    end
    return name
end
NS.GetUnitFullName = GetUnitFullName

-- ----------------------------------------------------------------------------
-- Chat / debug helpers
-- ----------------------------------------------------------------------------

local function SafeToString(value)
    local ok, result = pcall(tostring, value)
    if ok then
        return result
    end
    return "<secret>"
end

local function ChatMessage(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(tostring(msg), 1.0, 0.82, 0.0)
    end
end
NS.ChatMessage = ChatMessage

function NS.Debug(msg)
    if NS.DB and NS.DB.debugMode then
        ChatMessage(msg)
        if NS.DB.debugLogs then
            table.insert(NS.DB.debugLogs, "[" .. date("%Y-%m-%d %H:%M:%S") .. "] " .. msg)
            if #NS.DB.debugLogs > 100 then
                table.remove(NS.DB.debugLogs, 1)
            end
        end
    end
end

local function DebugThrottled(key, msg, interval)
    if not NS.DB or not NS.DB.debugMode then
        return
    end

    local now = GetTime and GetTime() or 0
    local last = debugThrottle[key] or -999
    if (now - last) < (interval or 5) then
        return
    end

    debugThrottle[key] = now
    NS.Debug(msg)
end

-- ----------------------------------------------------------------------------
-- Static popup for "Restore defaults" confirmation
-- ----------------------------------------------------------------------------

local function EnsureResetPopupRegistered()
    if not StaticPopupDialogs or StaticPopupDialogs["LUSTSOUND_RESET_CONFIRM"] then
        return
    end

    StaticPopupDialogs["LUSTSOUND_RESET_CONFIRM"] = {
        text = NS.L.RESET_CONFIRM_TEXT,
        button1 = NS.L.RESET_CONFIRM_ACCEPT,
        button2 = NS.L.RESET_CONFIRM_CANCEL,
        OnAccept = function()
            NS.ResetToDefaults()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
    }
end

-- Opens the reset-confirmation popup (used by the panel button and the slash
-- command). Wrapped in nil checks so it never hard-errors.
function NS.RequestResetDefaults()
    if StaticPopup_Show then
        EnsureResetPopupRegistered()
        StaticPopup_Show("LUSTSOUND_RESET_CONFIRM")
    end
end

-- ----------------------------------------------------------------------------
-- GUID cache
-- ----------------------------------------------------------------------------

-- Rebuilds the set of GUIDs considered "in my group": the player, the
-- player's pet, party members (1..4) and their pets, or raid members (1..N)
-- and their pets. nil GUIDs are skipped. Called on roster / pet / world events.
function NS.RebuildGroupGUIDs()
    wipe(NS.GroupGUIDs)

    -- Player and player's pet.
    local playerGUID = UnitGUID("player")
    if type(playerGUID) == "string" then
        NS.GroupGUIDs[playerGUID] = true
    end
    local petGUID = UnitGUID("pet")
    if type(petGUID) == "string" then
        NS.GroupGUIDs[petGUID] = true
    end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            local guid = UnitGUID("raid" .. i)
            if type(guid) == "string" then
                NS.GroupGUIDs[guid] = true
            end
            local raidPetGUID = UnitGUID("raidpet" .. i)
            if type(raidPetGUID) == "string" then
                NS.GroupGUIDs[raidPetGUID] = true
            end
        end
    else
        local n = GetNumSubgroupMembers()
        for i = 1, n do
            local guid = UnitGUID("party" .. i)
            if type(guid) == "string" then
                NS.GroupGUIDs[guid] = true
            end
            local partyPetGUID = UnitGUID("partypet" .. i)
            if type(partyPetGUID) == "string" then
                NS.GroupGUIDs[partyPetGUID] = true
            end
        end
    end

    for guid in pairs(seededAuraGUIDs) do
        if NS.GroupGUIDs[guid] ~= true then
            seededAuraGUIDs[guid] = nil
        end
    end

    for key in pairs(seenExhaustionAuras) do
        local guid = key:match("^([^:]+):")
        if guid and NS.GroupGUIDs[guid] ~= true then
            seenExhaustionAuras[key] = nil
        end
    end
end

-- ----------------------------------------------------------------------------
-- Context handling
-- ----------------------------------------------------------------------------

-- Returns the current context key based on IsInInstance().
-- Unknown instance types fall back to "world" (allowed by default).
function NS.GetCurrentContext()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return "world"
    elseif instanceType == "party" then
        return "party"
    elseif instanceType == "raid" then
        return "raid"
    elseif instanceType == "arena" then
        return "arena"
    elseif instanceType == "pvp" then
        return "pvp"
    elseif instanceType == "scenario" then
        return "scenario"
    end
    return "world"
end

-- Returns true when the current context is enabled in the config.
-- Unknown contexts default to allowed (no error).
function NS.IsContextAllowed()
    if not NS.DB then
        return true
    end
    local ctx = NS.GetCurrentContext()
    if not NS.DB.contexts then
        return true
    end
    local val = NS.DB.contexts[ctx]
    if val == nil then
        return true
    end
    return val == true
end

-- ----------------------------------------------------------------------------
-- Sound playback
-- ----------------------------------------------------------------------------

-- Plays the currently selected sound. `bypassAntiSpam` is true for the test
-- button and for real detections (the detection handlers manage anti-spam
-- separately, so playback itself is never double-gated).
function NS.PlaySelectedSound(bypassAntiSpam)
    if not NS.DB or not NS.DB.enabled then
        return
    end

    local preset = NS.GetSoundPreset(NS.DB.selectedSound)
    if not preset then
        NS.Debug("LustSound [debug]: playback skipped; no sound preset for key=" .. SafeToString(NS.DB.selectedSound))
        return
    end

    local channel = NS.DB.soundChannel or "Master"

    -- Prevent overlap: stop the previous sound before starting a new one.
    if NS.DB.preventOverlap and lastSoundHandle then
        pcall(StopSound, lastSoundHandle, 100)
        lastSoundHandle = nil
    end

    local willPlay, soundHandle

    if preset.soundType == "file" then
        if not preset.path then
            ChatMessage(NS.L.MSG_PLAY_FAILED)
            return
        end
        local fullPath = NS.ADDON_SOUND_ROOT .. preset.path
        willPlay, soundHandle = PlaySoundFile(fullPath, channel)
    elseif preset.soundType == "soundKit" then
        if not preset.soundKitID then
            ChatMessage(NS.L.MSG_PLAY_FAILED)
            return
        end
        willPlay, soundHandle = PlaySound(preset.soundKitID, channel)
    else
        return
    end

    if soundHandle then
        lastSoundHandle = soundHandle
    end

    NS.Debug("LustSound [debug]: playback requested key=" .. SafeToString(NS.DB.selectedSound) ..
        " type=" .. SafeToString(preset.soundType) ..
        " channel=" .. SafeToString(channel) ..
        " willPlay=" .. tostring(willPlay) ..
        " handle=" .. SafeToString(soundHandle))

    if not willPlay then
        ChatMessage(NS.L.MSG_PLAY_FAILED)
    end
end

-- Stops the most recently played sound (if any). Safe to call with no sound.
function NS.StopCurrentSound()
    if lastSoundHandle then
        pcall(StopSound, lastSoundHandle, 100)
        lastSoundHandle = nil
    end
end

-- Test button entry point. Bypasses anti-spam (handled at call site already).
function NS.TestSound()
    NS.PlaySelectedSound(true)
end

-- ----------------------------------------------------------------------------
-- Chat message about who cast
-- ----------------------------------------------------------------------------

function NS.ShowCastChat(spellID, casterName)
    if not NS.DB or not NS.DB.showChatMessage then
        return
    end
    local spellName = NS.GetSpellDisplayName(spellID)
    local name = casterName
    if name == nil or name == "" then
        name = NS.L.MSG_SPELL_ID_FALLBACK:format(spellID or 0)
    end
    ChatMessage(NS.L.MSG_SPELL_USED:format(spellName, name))
end

local function PlayDetectedLust(spellID, spellName, casterName, inGroup, sourceLabel)
    -- 1. Enabled?
    if not NS.DB or not NS.DB.enabled then
        return
    end

    -- 2. Is the spell a lust-family ability?
    if not NS.LustSpells[spellID] then
        return
    end

    -- 3. Group filter.
    if NS.DB.groupOnly and not inGroup then
        return
    end

    -- 4. Context filter.
    local context = NS.GetCurrentContext()
    if not NS.IsContextAllowed() then
        if NS.DB.debugMode then
            NS.Debug(NS.L.DEBUG_CAST:format(
                tostring(spellID),
                tostring(spellName),
                tostring(casterName),
                tostring(inGroup),
                tostring(context),
                "ignored (context disabled)"
            ))
        end
        return
    end

    -- 5. Global anti-spam across cast and aura fallback paths.
    local now = GetTime()
    if (now - lastActivationTime) < ANTI_SPAM_INTERVAL then
        if NS.DB.debugMode then
            NS.Debug(NS.L.DEBUG_CAST:format(
                tostring(spellID),
                tostring(spellName),
                tostring(casterName),
                tostring(inGroup),
                tostring(context),
                "ignored (anti-spam)"
            ))
        end
        return
    end
    lastActivationTime = now

    -- 6. Chat message + playback.
    NS.ShowCastChat(spellID, casterName)

    if NS.DB.debugMode then
        NS.Debug(NS.L.DEBUG_CAST:format(
            tostring(spellID),
            tostring(spellName),
            tostring(casterName),
            tostring(inGroup),
            tostring(context),
            "played (" .. tostring(sourceLabel) .. ")"
        ))
    end

    NS.PlaySelectedSound(true)
end

-- ============================================================================
-- PRIMARY DETECTION: UNIT_SPELLCAST_SUCCEEDED
-- ============================================================================
--
-- This is the direct cast detection path. It is still useful for player casts
-- and any group/pet casts the client continues to expose to addon code.
--
-- In Midnight, allied instant casts can be hidden. The exhaustion-debuff
-- polling fallback below covers those cases.
--
-- The event passes: unitTarget (string), castGUID (string), spellID (number)
-- ============================================================================

local function OnUnitSpellcastSucceeded(unitTarget, castGUID, spellID)
    -- 1. Enabled?
    if not NS.DB or not NS.DB.enabled then
        return
    end

    -- 2. Is the spell a lust-family ability?
    if type(spellID) ~= "number" or not NS.LustSpells[spellID] then
        return
    end

    DebugThrottled(
        "spellcast:" .. SafeToString(unitTarget) .. ":" .. SafeToString(spellID),
        "LustSound [debug]: UNIT_SPELLCAST_SUCCEEDED unit=" .. SafeToString(unitTarget) ..
            " spellID=" .. SafeToString(spellID) ..
            " castGUID=" .. SafeToString(castGUID),
        1
    )

    -- 3. Context filter.
    local context = NS.GetCurrentContext()
    if not NS.IsContextAllowed() then
        if NS.DB.debugMode then
            local casterName = GetUnitFullName(unitTarget) or tostring(unitTarget)
            NS.Debug(NS.L.DEBUG_CAST:format(
                tostring(spellID),
                tostring(NS.GetSpellDisplayName(spellID)),
                tostring(casterName),
                "true",
                tostring(context),
                "ignored (context disabled)"
            ))
        end
        return
    end

    -- 4. No group filter needed: UNIT_SPELLCAST_SUCCEEDED only fires for
    --    units we can track (player, party, raid, and their pets), so
    --    groupOnly is inherently satisfied.

    -- 5. Global anti-spam across all lust-family spells.
    local now = GetTime()
    if (now - lastActivationTime) < ANTI_SPAM_INTERVAL then
        if NS.DB.debugMode then
            local casterName = GetUnitFullName(unitTarget) or tostring(unitTarget)
            NS.Debug(NS.L.DEBUG_CAST:format(
                tostring(spellID),
                tostring(NS.GetSpellDisplayName(spellID)),
                tostring(casterName),
                "true",
                tostring(context),
                "ignored (anti-spam)"
            ))
        end
        return
    end
    lastActivationTime = now

    -- 6. Chat message + playback.
    local casterName = GetUnitFullName(unitTarget) or NS.L.MSG_SPELL_ID_FALLBACK:format(spellID or 0)

    NS.ShowCastChat(spellID, casterName)

    if NS.DB.debugMode then
        NS.Debug(NS.L.DEBUG_CAST:format(
            tostring(spellID),
            tostring(NS.GetSpellDisplayName(spellID)),
            tostring(casterName),
            "true",
            tostring(context),
            "played"
        ))
    end

    NS.PlaySelectedSound(true)
end
NS.OnUnitSpellcastSucceeded = OnUnitSpellcastSucceeded

-- ============================================================================
-- PRIMARY FALLBACK: EXHAUSTION DEBUFF POLLING
-- ============================================================================
--
-- Midnight can hide allied instant spellcasts from addon code. The resulting
-- exhaustion debuffs are visible, so we scan group unit tokens for newly seen
-- debuffs and map them back to the original lust-family spell.
-- ============================================================================

local function OnExhaustionAuraDetected(unitToken, debuffID, castSpellID, sourceUnit)
    local sourceName = type(sourceUnit) == "string" and GetUnitFullName(sourceUnit) or nil
    local casterName = sourceName or GetUnitFullName(unitToken) or tostring(unitToken)
    local inGroup = false
    local guid = UnitGUID(unitToken)
    if type(guid) == "string" then
        inGroup = NS.GroupGUIDs[guid] == true
    end

    PlayDetectedLust(
        castSpellID,
        NS.GetSpellDisplayName(castSpellID),
        casterName,
        inGroup,
        "unit aura " .. tostring(debuffID)
    )
end

local function GetAuraSourceUnit(aura)
    if type(aura) ~= "table" then
        return nil
    end
    local ok, sourceUnit = pcall(function()
        return aura.sourceUnit
    end)
    if ok and type(sourceUnit) == "string" then
        return sourceUnit
    end
    return nil
end

local function AuraStartedDuringBaseline(aura)
    if type(aura) ~= "table" or auraBaselineStartedAt <= 0 then
        return false
    end

    local ok, duration, expirationTime = pcall(function()
        return aura.duration, aura.expirationTime
    end)
    if not ok or type(duration) ~= "number" or type(expirationTime) ~= "number" then
        return false
    end
    if duration <= 0 or expirationTime <= 0 then
        return false
    end

    local startTime = expirationTime - duration
    return startTime >= (auraBaselineStartedAt - AURA_START_TIME_FUDGE_SECONDS)
end

function NS.FindUnitAuraBySpellID(unitToken, spellID)
    if not unitToken or type(spellID) ~= "number" then
        return nil
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unitToken, info.name, "HARMFUL")
            if ok and aura then
                return aura, GetAuraSourceUnit(aura), "C_UnitAuras.GetAuraDataBySpellName"
            end
        end
    end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and UnitIsUnit and UnitIsUnit(unitToken, "player") then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and aura then
            return aura, GetAuraSourceUnit(aura), "C_UnitAuras.GetPlayerAuraBySpellID"
        end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unitToken, i, "HARMFUL")
            if not ok or not aura then
                break
            end
            local matchOk, isMatch = pcall(function()
                return aura.spellId == spellID
            end)
            if matchOk and isMatch then
                return aura, GetAuraSourceUnit(aura), "C_UnitAuras.GetAuraDataByIndex"
            end
        end
    end

    if AuraUtil and AuraUtil.FindAuraBySpellID then
        local ok, aura, _, _, _, _, sourceUnit = pcall(AuraUtil.FindAuraBySpellID, spellID, unitToken, "HARMFUL")
        if ok and aura then
            if type(aura) == "table" then
                return aura, GetAuraSourceUnit(aura), "AuraUtil.FindAuraBySpellID"
            end
            return aura, sourceUnit, "AuraUtil.FindAuraBySpellID"
        elseif not ok then
            DebugThrottled(
                "aura-api-error:" .. tostring(spellID),
                "LustSound [debug]: AuraUtil.FindAuraBySpellID failed for spellID=" .. tostring(spellID),
                10
            )
        end
    end

    if UnitAura then
        for i = 1, 40 do
            local ok, name, _, _, _, _, _, sourceUnit, _, _, auraSpellID = pcall(UnitAura, unitToken, i, "HARMFUL")
            if not ok or not name then
                break
            end
            if type(auraSpellID) == "number" and auraSpellID == spellID then
                return name, sourceUnit, "UnitAura"
            end
        end
    end

    return nil
end

local function ScanUnitExhaustionAuras(unitToken, silent)
    if not NS.DB or not NS.LustExhaustionDebuffs then
        return
    end
    if not unitToken or not UnitExists(unitToken) then
        return
    end

    local guid = UnitGUID(unitToken)
    if type(guid) ~= "string" then
        return
    end
    if NS.DB.groupOnly and NS.GroupGUIDs[guid] ~= true then
        return
    end

    local now = GetTime and GetTime() or 0
    local baselineActive = silent or now < auraBaselineUntil
    local firstScanForGUID = seededAuraGUIDs[guid] ~= true
    if firstScanForGUID then
        seededAuraGUIDs[guid] = true
    end

    for debuffID, castSpellID in pairs(NS.LustExhaustionDebuffs) do
        local key = guid .. ":" .. tostring(debuffID)
        local aura, sourceUnit, method = NS.FindUnitAuraBySpellID(unitToken, debuffID)

        if aura then
            if not seenExhaustionAuras[key] then
                seenExhaustionAuras[key] = true
                local freshDuringBaseline = baselineActive and not silent and AuraStartedDuringBaseline(aura)
                if (not baselineActive and not firstScanForGUID) or freshDuringBaseline then
                    NS.Debug("LustSound [debug]: exhaustion aura found unit=" ..
                        SafeToString(unitToken) .. " debuffID=" .. tostring(debuffID) ..
                        " castSpellID=" .. tostring(castSpellID) ..
                        " method=" .. SafeToString(method))
                    OnExhaustionAuraDetected(unitToken, debuffID, castSpellID, sourceUnit)
                elseif (firstScanForGUID or baselineActive) and NS.DB.debugMode then
                    local reason = firstScanForGUID and "first-scan" or "transition"
                    NS.Debug("LustSound [debug]: seeded existing exhaustion aura unit=" ..
                        SafeToString(unitToken) .. " debuffID=" .. tostring(debuffID) ..
                        " reason=" .. reason)
                end
            end
        elseif not baselineActive then
            seenExhaustionAuras[key] = nil
        end
    end
end
NS.ScanUnitExhaustionAuras = ScanUnitExhaustionAuras

local function ScanGroupExhaustionAuras(silent)
    for _, unitToken in ipairs(auraFallbackUnitTokens) do
        ScanUnitExhaustionAuras(unitToken, silent)
    end
end
NS.ScanGroupExhaustionAuras = ScanGroupExhaustionAuras

function NS.DebugScanAuras()
    NS.Debug("LustSound [debug]: manual aura scan start")
    for _, unitToken in ipairs(auraFallbackUnitTokens) do
        if UnitExists(unitToken) then
            local guid = UnitGUID(unitToken)
            NS.Debug("LustSound [debug]: scan unit=" .. SafeToString(unitToken) ..
                " guid=" .. SafeToString(guid) ..
                " inGroup=" .. tostring(guid ~= nil and NS.GroupGUIDs[guid] == true))
            ScanUnitExhaustionAuras(unitToken, false)
        end
    end
    NS.Debug("LustSound [debug]: manual aura scan end")
end

local function QueueExhaustionAuraSeed(reason)
    local now = GetTime and GetTime() or 0
    auraBaselineStartedAt = now
    local baselineUntil = now + AURA_BASELINE_GRACE_SECONDS
    if auraBaselineUntil < baselineUntil then
        auraBaselineUntil = baselineUntil
    end
    DebugThrottled(
        "aura-baseline:" .. SafeToString(reason),
        "LustSound [debug]: aura baseline active reason=" .. SafeToString(reason) ..
            " seconds=" .. tostring(AURA_BASELINE_GRACE_SECONDS),
        2
    )

    if auraSeedPending then
        return
    end
    auraSeedPending = true

    local function SeedNow()
        auraSeedPending = false
        ScanGroupExhaustionAuras(true)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, SeedNow)
    else
        SeedNow()
    end
end

local function StartAuraFallbackTicker()
    if auraFallbackTicker or not C_Timer or not C_Timer.NewTicker then
        return
    end

    auraFallbackTicker = C_Timer.NewTicker(1.0, function()
        if NS.DB and NS.DB.enabled then
            ScanGroupExhaustionAuras(false)
        end
    end)
end

-- ----------------------------------------------------------------------------
-- Reset to defaults
-- ----------------------------------------------------------------------------

-- Restores the default configuration in place (keeps the same table reference
-- used by SavedVariables) and refreshes the options panel if present.
function NS.ResetToDefaults()
    if LustSoundDB == nil then
        LustSoundDB = {}
    end
    wipe(LustSoundDB)
    local defaults = NS.GetDefaults()
    for k, v in pairs(defaults) do
        LustSoundDB[k] = v
    end
    NS.DB = LustSoundDB

    -- Reset transient state too.
    lastSoundHandle = nil
    lastActivationTime = 0
    auraBaselineStartedAt = 0
    auraBaselineUntil = 0
    wipe(seenExhaustionAuras)
    wipe(seededAuraGUIDs)
    wipe(debugThrottle)

    if NS.RefreshOptions then
        NS.RefreshOptions()
    end
    ChatMessage(NS.L.MSG_RESET_DONE)
end

-- ----------------------------------------------------------------------------
-- Event frame
-- ----------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_PET")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            -- Initialize / migrate SavedVariables.
            LustSoundDB = MergeDefaults(LustSoundDB, NS.defaultDB)
            NS.DB = LustSoundDB

            -- Build the initial GUID cache.
            NS.RebuildGroupGUIDs()
            StartAuraFallbackTicker()
            QueueExhaustionAuraSeed("loaded")
            NS.Debug("LustSound [debug]: loaded; enabled=" .. tostring(NS.DB.enabled) ..
                " groupOnly=" .. tostring(NS.DB.groupOnly) ..
                " selectedSound=" .. SafeToString(NS.DB.selectedSound))

            -- Register the AddOns category now so it appears in Options.
            -- The panel contents are still built lazily on first show.
            if NS.InitOptions then
                NS.InitOptions()
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if NS.DB then
            NS.RebuildGroupGUIDs()
            QueueExhaustionAuraSeed("world")
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        if NS.DB then
            NS.RebuildGroupGUIDs()
            QueueExhaustionAuraSeed("roster")
        end
    elseif event == "UNIT_PET" then
        -- UNIT_PET passes a unit token; we rebuild the cache for any pet change.
        if NS.DB then
            NS.RebuildGroupGUIDs()
            QueueExhaustionAuraSeed("pet")
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Direct cast path for visible spellcasts.
        local unitTarget, castGUID, spellID = ...
        OnUnitSpellcastSucceeded(unitTarget, castGUID, spellID)
    end
end)

local function UnitEventFrame_OnEvent(self, event, unitTarget, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local secretOk, hasSecret = pcall(HasAnySecretValues, unitTarget, ...)
        if secretOk and hasSecret then
            DebugThrottled(
                "secret-spellcast:" .. SafeToString(unitTarget),
                "LustSound [debug]: UNIT_SPELLCAST_SUCCEEDED skipped secret payload unit=" .. SafeToString(unitTarget),
                5
            )
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    ScanUnitExhaustionAuras(unitTarget, false)
                end)
            else
                ScanUnitExhaustionAuras(unitTarget, false)
            end
            return
        end
        local castGUID, spellID = ...
        OnUnitSpellcastSucceeded(unitTarget, castGUID, spellID)
    elseif event == "UNIT_AURA" then
        ScanUnitExhaustionAuras(unitTarget, false)
    end
end

for _, unitToken in ipairs(trackedUnitTokens) do
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", UnitEventFrame_OnEvent)
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", unitToken)
    frame:RegisterUnitEvent("UNIT_AURA", unitToken)
    unitEventFrames[unitToken] = frame
end

-- ----------------------------------------------------------------------------
-- Slash commands
-- ----------------------------------------------------------------------------

SLASH_LUSTSOUND1 = "/lustsound"
SLASH_LUSTSOUND2 = "/lsound"
SlashCmdList["LUSTSOUND"] = function(msg)
    local raw = msg and msg:lower() or ""
    local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", "")

    -- First token is the sub-command.
    local sub = trimmed:match("^(%S+)") or ""

    if sub == "test" then
        NS.TestSound()
    elseif sub == "stop" then
        NS.StopCurrentSound()
    elseif sub == "reset" then
        NS.RequestResetDefaults()
    elseif sub == "debug" then
        if NS.DB then
            NS.DB.debugMode = not NS.DB.debugMode
            ChatMessage(NS.L.MSG_DEBUG_STATE:format(
                NS.DB.debugMode and NS.L.MSG_DEBUG_ON or NS.L.MSG_DEBUG_OFF
            ))
            if NS.RefreshOptions then
                NS.RefreshOptions()
            end
        end
    elseif sub == "scan" then
        if NS.DB then
            NS.DB.debugMode = true
        end
        NS.RebuildGroupGUIDs()
        NS.DebugScanAuras()
    elseif sub == "help" then
        ChatMessage(NS.L.HELP_TITLE)
        ChatMessage(NS.L.HELP_OPEN)
        ChatMessage(NS.L.HELP_TEST)
        ChatMessage(NS.L.HELP_STOP)
        ChatMessage(NS.L.HELP_RESET)
        ChatMessage(NS.L.HELP_DEBUG)
        ChatMessage(NS.L.HELP_SCAN)
        ChatMessage(NS.L.HELP_HELP)
    else
        -- No sub-command (or unknown): open the options panel.
        if NS.OpenOptions then
            NS.OpenOptions()
        else
            ChatMessage(NS.L.ADDON_TITLE)
        end
    end
end
