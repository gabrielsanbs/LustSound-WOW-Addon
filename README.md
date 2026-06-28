# LustSound

![LustSound banner](LustSound/lustsoundimg.png)

LustSound is a lightweight World of Warcraft Retail addon for players who want
a clear custom sound when a Bloodlust-style ability is used by the group.

It targets **Retail Interface 120007** for **Midnight / patch 12.0.7** and is
built around the newer addon restrictions introduced in Patch 12.0.

## What It Does

- Plays a selected sound when you, your pet, a party member, a raid member, or a
  group pet uses a Bloodlust-equivalent ability.
- Supports party, dungeon, raid, arena, battleground, scenario, and open-world
  contexts.
- Detects hidden allied casts by watching the visible exhaustion debuffs.
- Avoids repeated sound spam when the same lust applies to many group members.
- Ignores existing exhaustion auras when you join a group, enter a dungeon, zone
  out, zone back in, or reload the UI.
- Keeps chat output optional and local only.

## Detected Abilities

| Cast Spell ID | Ability | Common Source |
| --- | --- | --- |
| `2825` | Bloodlust | Shaman |
| `32182` | Heroism | Shaman |
| `80353` | Time Warp | Mage |
| `264667` | Primal Rage | Hunter Ferocity pet |
| `390386` | Fury of the Aspects | Evoker |

Power Infusion, drums, and generic haste buffs are not detected on purpose.

## How Detection Works

Patch 12.0 changed how much combat information addon code can safely read. In
particular, `COMBAT_LOG_EVENT_UNFILTERED`, `CombatLogGetCurrentEventInfo()`, and
some allied instant spellcast payloads can be hidden or contain restricted
values.

LustSound avoids relying on combat-log payloads for the main flow:

| Layer | Purpose |
| --- | --- |
| `UNIT_SPELLCAST_SUCCEEDED` | Direct path for visible casts, especially your own casts and exposed pet/group casts. |
| `UNIT_AURA` and a small ticker | Fallback path for hidden allied casts by checking visible exhaustion debuffs. |
| GUID group cache | Keeps detection scoped to you, your group, raid members, and pets. |
| Baseline seeding | Prevents false positives from existing Sated/Exhaustion auras after zoning or joining a group. |
| Global anti-spam | Makes one sound play for the lust event instead of one sound per affected unit. |

The aura fallback maps exhaustion debuffs back to the original cast:

| Debuff Spell ID | Debuff | Treated As |
| --- | --- | --- |
| `57723` | Exhaustion | Heroism |
| `57724` | Sated | Bloodlust |
| `80354` | Temporal Displacement | Time Warp |
| `95809` | Insanity | Primal Rage legacy pet lust |
| `160455` | Fatigued | Primal Rage legacy pet lust |
| `264689` | Fatigued | Primal Rage |
| `390435` | Exhaustion | Fury of the Aspects |

## Install

Copy the `LustSound` folder into your Retail AddOns directory:

```text
World of Warcraft\_retail_\Interface\AddOns\LustSound
```

Then restart the game or run `/reload`.

Open the options with:

```text
/lustsound
```

or through:

```text
Esc -> Options -> AddOns -> LustSound
```

## Custom Sounds

The addon already includes example `.ogg` files in `LustSound/Sounds/`.

To add more:

1. Put `.ogg` or `.mp3` files in `LustSound/Sounds/`.
2. Register them in `LustSound/Sounds.lua`.
3. Run `/reload`.
4. Use the Test button in the options panel.

Example:

```lua
NS.CustomSounds = {
    { "Bolinha de gorf", "bolinha_de_gorf.ogg" },
    { "SILENCE...I KILL YOU", "silence_i_kill_you.ogg" },
}
```

`PlaySoundFile` does not provide per-file volume. Use the in-game audio channel
selection instead: Master, SFX, Dialog, Music, or Ambience.

## Commands

| Command | Action |
| --- | --- |
| `/lustsound` | Opens the options panel. |
| `/lsound` | Alias for `/lustsound`. |
| `/lustsound test` | Plays the selected sound for testing. |
| `/lustsound stop` | Stops the currently playing sound. |
| `/lustsound reset` | Restores default settings with confirmation. |
| `/lustsound debug` | Toggles debug mode. |
| `/lustsound scan` | Forces an aura scan and writes debug output. |
| `/lustsound help` | Shows the command list. |

## Settings

All settings are stored in the `LustSoundDB` SavedVariable.

| Setting | Meaning |
| --- | --- |
| Enable addon | Master on/off switch. |
| Selected sound | Sound from `Sounds.lua` or the built-in Ready Check fallback. |
| Audio channel | Channel passed to `PlaySoundFile`. |
| Prevent sound overlap | Stops the previous sound before playing the next one. |
| Show chat message | Prints a local message when lust is detected. |
| Group only | Ignores units outside your group/raid cache. |
| Contexts | Enables or disables world, party, raid, arena, PvP, and scenario detection. |
| Debug mode | Stores recent diagnostic lines in `LustSoundDB.debugLogs`. |

## Code Map

```text
LustSound/
|-- LustSound.toc       Addon metadata, Interface version, load order.
|-- Localization.lua    UI text and command messages.
|-- Sounds.lua          User-facing custom sound list.
|-- Spells.lua          Lust spell IDs and exhaustion-debuff mapping.
|-- SoundRegistry.lua   Sound lookup and file path resolution.
|-- Core.lua            SavedVariables, detection, anti-spam, debug, playback.
|-- Options.lua         Taint-conscious options panel UI.
|-- icon.tga            AddOns list icon.
|-- lustsoundimg.png    Project banner used by the README.
`-- Sounds/            Bundled example audio files.
```

## Troubleshooting

If no sound plays, first try `/lustsound test`. If the test works but a real cast
does not, enable debug mode:

```text
/lustsound debug
```

Useful debug lines:

| Debug text | Meaning |
| --- | --- |
| `UNIT_SPELLCAST_SUCCEEDED` | A visible cast event was received. |
| `skipped secret payload` | WoW exposed an event but hid part of its payload. The addon will use aura fallback. |
| `exhaustion aura found` | A new lust exhaustion debuff was detected and mapped back to a cast. |
| `seeded existing exhaustion aura` | Existing Sated/Exhaustion was ignored as baseline state. |
| `playback requested` | The addon asked WoW to play the selected sound. |

Common cases:

- No sound in raids: enable the Raid context.
- No sound after joining a group that already used lust: expected; existing
  exhaustion auras are ignored.
- No enemy battleground lust detection: expected; the addon intentionally avoids
  outside-group combat-log detection under Patch 12.0 restrictions.
- Sound file missing: confirm the file exists in `LustSound/Sounds/` and is
  registered in `Sounds.lua`.

## Interface Updates

If a future WoW build marks the addon out of date, check the current interface
number in-game:

```text
/dump select(4, GetBuildInfo())
```

Then update only the `## Interface:` line in `LustSound/LustSound.toc`.

## License

MIT License. See [LICENSE](LICENSE).
