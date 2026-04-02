# OBS Studio CLI Skill

Use this skill to control OBS Studio remotely via `gobs-cli` (obs-websocket v5) and edit OBS settings via config files.

## Setup

- **Binary**: `{{GOBS_CLI}}`
- **Requires**: OBS Studio running with obs-websocket enabled (bundled in OBS 28+)
- **Default connection**: `localhost:4455` (obs-websocket v5)
- **Override**: `--host`, `--port`, `--password` flags or env vars `OBS_HOST`, `OBS_PORT`, `OBS_PASSWORD`

For brevity, `gobs-cli` below refers to the full path to the binary.

## Stream Control

```bash
gobs-cli stream start        # Begin streaming
gobs-cli stream stop         # End streaming
gobs-cli stream toggle       # Toggle streaming state
gobs-cli stream status       # Display streaming status
```

## Recording

```bash
gobs-cli record start                 # Begin recording
gobs-cli record stop                  # End recording
gobs-cli record toggle                # Toggle recording state
gobs-cli record pause                 # Pause active recording
gobs-cli record resume                # Resume paused recording
gobs-cli record status                # Display recording status
gobs-cli record split                 # Split current recording file
gobs-cli record chapter "Chapter 1"   # Mark chapter in recording
gobs-cli record directory             # Get recording folder
gobs-cli record directory "D:/Vids"   # Set recording folder
```

## Scene Management

```bash
gobs-cli scene list                    # List all scenes
gobs-cli scene current                 # Show current scene
gobs-cli scene switch "Scene Name"     # Switch program scene
gobs-cli scene switch --preview "X"    # Switch preview (studio mode)
```

## Scene Items

```bash
gobs-cli sceneitem list "Scene Name"                   # List scene items
gobs-cli sceneitem show "Scene" "Item"                 # Make item visible
gobs-cli sceneitem hide "Scene" "Item"                 # Hide item
gobs-cli sceneitem toggle "Scene" "Item"               # Toggle visibility
gobs-cli sceneitem transform "Scene" "Item" --scale-x 1.5 --scale-y 1.5  # Transform
```

## Groups

```bash
gobs-cli group list "Scene"                 # List all groups
gobs-cli group show "Scene" "Group"         # Show group
gobs-cli group hide "Scene" "Group"         # Hide group
gobs-cli group toggle "Scene" "Group"       # Toggle group
```

## Inputs

```bash
gobs-cli input list                         # List all inputs
gobs-cli input create "Name" "Kind"         # Create input
gobs-cli input mute "Name"                  # Mute audio input
gobs-cli input unmute "Name"                # Unmute audio input
gobs-cli input volume "Name" 0.8            # Set volume (0.0-1.0)
```

## Filters

```bash
gobs-cli filter list "Source"                    # List filters on source
gobs-cli filter enable "Source" "Filter"         # Enable filter
gobs-cli filter disable "Source" "Filter"        # Disable filter
gobs-cli filter toggle "Source" "Filter"         # Toggle filter
```

## Studio Mode

```bash
gobs-cli studiomode enable / disable / toggle / status
```

## Scene Collections & Profiles

```bash
gobs-cli scenecollection list / current / switch "Name" / create "Name"
gobs-cli profile list / current / switch "Name" / create "Name"
```

## Replay Buffer & Virtual Camera

```bash
gobs-cli replaybuffer start / stop / toggle / save
gobs-cli virtualcam start / stop / toggle / status
```

## Hotkeys

```bash
gobs-cli hotkey list
gobs-cli hotkey trigger "HotkeyName"
```

---

# OBS Settings via Config Files

Some OBS settings (base canvas resolution, output resolution, FPS, etc.) **cannot be changed via websocket** — they must be edited in OBS profile config files directly.

**IMPORTANT**: OBS must be **closed** (or the profile must not be active) when editing config files, otherwise OBS will overwrite your changes on exit.

## Config File Location

```
{{OBS_CONFIG_DIR}}/basic/profiles/<ProfileName>/basic.ini
```

To find the active profile name: `gobs-cli profile current`

## Video Settings — `[Video]` section in `basic.ini`

| Key | Description | Example |
|---|---|---|
| `BaseCX` / `BaseCY` | Base (canvas) resolution | `1920` / `1080` |
| `OutputCX` / `OutputCY` | Output (scaled) resolution | `1920` / `1080` |
| `FPSCommon` | Common FPS value | `60` |
| `ScaleType` | Downscale filter | `bicubic` |

## Troubleshooting

- **Connection refused**: OBS isn't running or obs-websocket isn't enabled (Tools → obs-websocket Settings)
- **Config changes not applied**: OBS was running when you edited basic.ini — close OBS first.
- **Scene names with spaces**: Always quote scene/item names.
