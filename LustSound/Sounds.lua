local ADDON_NAME, NS = ...

-- ============================================================================
-- Sounds.lua
--
-- User-editable list of custom sounds. Each entry is shown in the options
-- dropdown in the order listed below. After adding or removing entries,
-- run /reload in-game.
--
-- Format:  { "Display Name", "filename.ogg" }
-- Accepted extensions: .ogg, .mp3
-- Place the actual audio files inside the addon's Sounds/ folder.
-- ============================================================================

NS.CustomSounds = {
    { "Bolinha de gorf", "bolinha_de_gorf.ogg" },
    {"SILENCE...I KILL YOU", "silence_i_kill_you.ogg"}

    -- Add more sounds below. Examples:
    -- { "Epic Horn", "epic_horn.ogg" },
    -- { "Air Raid Siren", "siren.mp3" },
}
