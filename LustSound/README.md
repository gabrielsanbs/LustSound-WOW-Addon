# LustSound AddOn Package

![LustSound banner](lustsoundimg.png)

This folder is the actual World of Warcraft addon folder. Copy this whole
`LustSound` directory into:

```text
World of Warcraft\_retail_\Interface\AddOns\LustSound
```

LustSound plays a custom sound when a Bloodlust-style ability is used by you,
your pet, a party member, a raid member, or a group pet.

## Quick Use

```text
/lustsound
```

Use the options panel to select the sound, audio channel, enabled contexts, chat
message behavior, and overlap behavior.

## Detected Spells

| Spell ID | Ability | Source |
| --- | --- | --- |
| `2825` | Bloodlust | Shaman |
| `32182` | Heroism | Shaman |
| `80353` | Time Warp | Mage |
| `264667` | Primal Rage | Hunter Ferocity pet |
| `390386` | Fury of the Aspects | Evoker |

## Patch 12.0 Detection Model

WoW Patch 12.0 can hide or restrict combat-log and allied instant-cast payloads.
For that reason, LustSound does not depend on `COMBAT_LOG_EVENT_UNFILTERED` for
normal operation.

Detection uses:

- `UNIT_SPELLCAST_SUCCEEDED` when the client exposes the cast.
- `UNIT_AURA` plus a small fallback ticker when allied casts are hidden.
- Exhaustion-debuff mapping for Sated, Temporal Displacement, Fatigued, and
  Evoker Exhaustion.
- A short baseline window after zoning or roster changes so existing debuffs do
  not play the sound again.
- A global anti-spam gate so one group lust does not trigger one sound per unit.

## Commands

| Command | Action |
| --- | --- |
| `/lustsound` | Open options. |
| `/lsound` | Alias. |
| `/lustsound test` | Test selected sound. |
| `/lustsound stop` | Stop current sound. |
| `/lustsound reset` | Restore defaults. |
| `/lustsound debug` | Toggle debug logs. |
| `/lustsound scan` | Force aura scan for diagnostics. |
| `/lustsound help` | Show help. |

## Code Files

```text
LustSound.toc       Metadata and load order.
Localization.lua    UI and command strings.
Sounds.lua          Editable custom sound list.
Spells.lua          Spell IDs and debuff mapping.
SoundRegistry.lua   Sound lookup and path resolution.
Core.lua            Detection, SavedVariables, playback, debug.
Options.lua         AddOn options UI.
icon.tga            AddOns list icon.
Sounds/             Bundled example audio files.
```

The full project README is in the repository root.
