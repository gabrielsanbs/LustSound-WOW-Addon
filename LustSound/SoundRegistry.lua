local ADDON_NAME, NS = ...

-- ============================================================================
-- SoundRegistry.lua
--
-- Builds the sound registry dynamically from the user-editable NS.CustomSounds
-- (defined in Sounds.lua) and adds static presets like WoW Ready Check.
-- Also contains the audio-channel list and channel validation.
-- ============================================================================

-- Prefix used to build the full path of a custom file inside the addon folder.
NS.ADDON_SOUND_ROOT = "Interface\\AddOns\\LustSound\\"

-- Build the ordered sound registry from NS.CustomSounds + static presets.
NS.SoundRegistry = {}

if NS.CustomSounds then
    for _, entry in ipairs(NS.CustomSounds) do
        local displayName = entry[1]
        local fileName = entry[2]
        if type(displayName) == "string" and type(fileName) == "string"
           and fileName ~= "" then
            NS.SoundRegistry[#NS.SoundRegistry + 1] = {
                key       = fileName,
                name      = displayName,
                soundType = "file",
                path      = "Sounds\\" .. fileName,
            }
        end
    end
end

-- Static preset: WoW Ready Check (always available).
NS.SoundRegistry[#NS.SoundRegistry + 1] = {
    key        = "readycheck",
    name       = NS.L.SOUND_READYCHECK,
    soundType  = "soundKit",
    -- SOUNDKIT may be nil in some contexts; guard against that.
    soundKitID = (SOUNDKIT and SOUNDKIT.READY_CHECK) or nil,
}

-- Fast lookup by key.
NS.SoundRegistryByKey = {}
for _, entry in ipairs(NS.SoundRegistry) do
    NS.SoundRegistryByKey[entry.key] = entry
end

-- Ordered list of audio channels offered in the dropdown.
NS.AudioChannels = {
    { key = "Master",   name = NS.L.CHANNEL_MASTER },
    { key = "SFX",      name = NS.L.CHANNEL_SFX },
    { key = "Dialog",   name = NS.L.CHANNEL_DIALOG },
    { key = "Music",    name = NS.L.CHANNEL_MUSIC },
    { key = "Ambience", name = NS.L.CHANNEL_AMBIENCE },
}

-- Returns the registry entry for a given key. Falls back to the first entry
-- when the key is missing/invalid so playback never errors.
function NS.GetSoundPreset(key)
    if key and NS.SoundRegistryByKey[key] then
        return NS.SoundRegistryByKey[key]
    end
    return NS.SoundRegistry[1]
end

-- Returns the localized display name for a channel key.
function NS.GetChannelName(channelKey)
    for _, ch in ipairs(NS.AudioChannels) do
        if ch.key == channelKey then
            return ch.name
        end
    end
    return channelKey
end

-- Returns true when a channel key is one of the known channels.
function NS.IsValidChannel(channelKey)
    for _, ch in ipairs(NS.AudioChannels) do
        if ch.key == channelKey then
            return true
        end
    end
    return false
end
