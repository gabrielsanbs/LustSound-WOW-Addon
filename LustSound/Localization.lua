local ADDON_NAME, NS = ...

-- Localization table. NS.L is filled with enUS as the fallback, then
-- overridden by the client locale when a translation is available.
NS.L = NS.L or {}

local L = NS.L
local locale = GetLocale()

-- English (fallback / default)
local enUS = {
    -- Title / description
    ADDON_TITLE = "LustSound",
    ADDON_DESCRIPTION = "Plays a custom sound when Bloodlust, Heroism, Time Warp, Primal Rage or Fury of the Aspects is used.",

    -- Options panel labels
    ENABLE_ADDON = "Enable addon",
    GROUP_ONLY = "Detect only players and pets in my group",
    GROUP_ONLY_NOTE = "Patch 12.0+ restricts combat-log visibility, so enemy/outside-group casts are not attempted.",
    PREVENT_OVERLAP = "Prevent sound overlap",
    SHOW_CHAT = "Show in chat who used the ability",
    SELECTED_SOUND = "Selected sound",
    SOUND_CHANNEL = "Audio channel",
    TEST_SOUND = "Test sound",
    STOP_SOUND = "Stop sound",
    RESTORE_DEFAULTS = "Restore defaults",
    SOUNDS_HELP = "To add sounds, place .ogg or .mp3 files in the Sounds folder and list them in Sounds.lua. Then run /reload.",
    DETECTED_ABILITIES = "Detected abilities:",

    -- Context section
    CONTEXT_SECTION = "Game contexts (advanced)",
    CONTEXT_WORLD = "Open world",
    CONTEXT_PARTY = "Dungeon",
    CONTEXT_RAID = "Raid",
    CONTEXT_ARENA = "Arena",
    CONTEXT_BATTLEGROUNG = "Battleground",
    CONTEXT_SCENARIO = "Scenario",

    -- Channels
    CHANNEL_MASTER = "Master",
    CHANNEL_SFX = "SFX",
    CHANNEL_DIALOG = "Dialog",
    CHANNEL_MUSIC = "Music",
    CHANNEL_AMBIENCE = "Ambience",
    CHANNEL_HELP = "Master respects the game's master volume but does not depend on other channels.",

    -- Sound presets
    SOUND_READYCHECK = "WoW Ready Check",

    -- Popup
    RESET_CONFIRM_TITLE = "Restore defaults",
    RESET_CONFIRM_TEXT = "Are you sure you want to restore the default settings?",
    RESET_CONFIRM_ACCEPT = "Restore",
    RESET_CONFIRM_CANCEL = "Cancel",

    -- Messages
    MSG_PLAY_FAILED = "LustSound: could not play the sound. Check the file path and audio channel.",
    MSG_SPELL_USED = "LustSound: %s used by %s.",
    MSG_SPELL_ID_FALLBACK = "Spell %d",
    MSG_DEBUG_STATE = "LustSound: debug mode %s.",
    MSG_DEBUG_ON = "enabled",
    MSG_DEBUG_OFF = "disabled",
    MSG_RESET_DONE = "LustSound: settings restored to defaults.",

    -- Debug
    DEBUG_CAST = "LustSound [debug]: spellID=%s name=%s caster=%s inGroup=%s context=%s action=%s",

    -- Slash help
    HELP_TITLE = "LustSound commands:",
    HELP_OPEN = "  /lustsound - Open the options panel.",
    HELP_TEST = "  /lustsound test - Test the selected sound.",
    HELP_STOP = "  /lustsound stop - Stop the current sound.",
    HELP_RESET = "  /lustsound reset - Restore defaults.",
    HELP_DEBUG = "  /lustsound debug - Toggle debug mode.",
    HELP_SCAN = "  /lustsound scan - Force an aura scan and write debug lines.",
    HELP_HELP = "  /lustsound help - Show this help.",
}

-- Portuguese (Brazil)
local ptBR = {
    ADDON_DESCRIPTION = "Toca um som quando Bloodlust, Heroism, Time Warp, Primal Rage ou Fury of the Aspects e utilizado.",

    ENABLE_ADDON = "Ativar addon",
    GROUP_ONLY = "Detectar somente jogadores e pets do meu grupo",
    GROUP_ONLY_NOTE = "No Patch 12.0+, o log de combate e restrito; casts de inimigos/fora do grupo nao sao tentados.",
    PREVENT_OVERLAP = "Impedir sobreposicao de sons",
    SHOW_CHAT = "Exibir no chat quem utilizou a habilidade",
    SELECTED_SOUND = "Som selecionado",
    SOUND_CHANNEL = "Canal de audio",
    TEST_SOUND = "Testar som",
    STOP_SOUND = "Parar som",
    RESTORE_DEFAULTS = "Restaurar padroes",
    SOUNDS_HELP = "Para adicionar sons, coloque arquivos .ogg ou .mp3 na pasta Sounds e liste-os em Sounds.lua. Depois execute /reload.",
    DETECTED_ABILITIES = "Habilidades detectadas:",

    CONTEXT_SECTION = "Contextos de jogo (avancado)",
    CONTEXT_WORLD = "Mundo aberto",
    CONTEXT_PARTY = "Dungeon",
    CONTEXT_RAID = "Raid",
    CONTEXT_ARENA = "Arena",
    CONTEXT_BATTLEGROUNG = "Battleground",
    CONTEXT_SCENARIO = "Scenario",

    CHANNEL_HELP = "Master continua respeitando o volume mestre do jogo, mas nao depende dos outros canais.",

    SOUND_READYCHECK = "Ready Check do WoW",

    RESET_CONFIRM_TITLE = "Restaurar padroes",
    RESET_CONFIRM_TEXT = "Tem certeza de que deseja restaurar as configuracoes padrao?",
    RESET_CONFIRM_ACCEPT = "Restaurar",
    RESET_CONFIRM_CANCEL = "Cancelar",

    MSG_PLAY_FAILED = "LustSound: nao foi possivel reproduzir o som. Verifique o caminho do arquivo e o canal de audio.",
    MSG_SPELL_USED = "LustSound: %s utilizado por %s.",
    MSG_DEBUG_STATE = "LustSound: modo de debug %s.",
    MSG_DEBUG_ON = "ativado",
    MSG_DEBUG_OFF = "desativado",
    MSG_RESET_DONE = "LustSound: configuracoes restauradas para o padrao.",

    HELP_TITLE = "Comandos do LustSound:",
    HELP_OPEN = "  /lustsound - Abre o painel de opcoes.",
    HELP_TEST = "  /lustsound test - Testa o som selecionado.",
    HELP_STOP = "  /lustsound stop - Para o ultimo som.",
    HELP_RESET = "  /lustsound reset - Abre a confirmacao para restaurar os padroes.",
    HELP_DEBUG = "  /lustsound debug - Ativa ou desativa o debug.",
    HELP_SCAN = "  /lustsound scan - Forca uma varredura de auras e grava linhas de debug.",
    HELP_HELP = "  /lustsound help - Mostra os comandos disponiveis.",
}

-- Populate L with enUS (fallback) first.
for k, v in pairs(enUS) do
    L[k] = v
end

-- Override with the current locale when available.
if locale == "ptBR" then
    for k, v in pairs(ptBR) do
        L[k] = v
    end
end
