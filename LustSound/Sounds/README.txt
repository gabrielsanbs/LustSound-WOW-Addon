LustSound - Sounds folder
=========================

Place your custom sound file here.

The default expected file is:

    lust.ogg

MP3 files are also accepted (.mp3).

The path used by the addon (configurable in the options panel) is relative
to the addon folder, for example:

    Sounds\lust.ogg

which resolves internally to:

    Interface\AddOns\LustSound\Sounds\lust.ogg

After adding or replacing a file, run /reload in-game so the client can
pick up the new audio asset.

Notes
-----
- Only .ogg and .mp3 files are accepted.
- Do not use absolute Windows paths (e.g. C:\...) or ".." in the path.
- PlaySoundFile has no individual volume control for custom files; use the
  in-game audio channel dropdown (Master / SFX / Dialog / Music / Ambience).
- If playback fails, the addon prints a clear message in the chat. The failure
  may be caused by a missing file OR by a disabled/muted audio channel.
