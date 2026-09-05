# CICADAMATA Replay Theater
A small replay theater mod based off of ghost file replay data for the game [CICADAMATA](https://store.steampowered.com/app/3817250/CICADAMATA/).

This is my first go at using Go (haha) let alone using Godot Engine so go easy on me. I decompiled the game and made my own scene; this repo contains that codebase. You can drop the `ReplayTheater` folder in the game's decompiled `Scenes/` folder if you're looking to further develop in Gotdot Engine.

At the time of interest I didn't know about [GDPatch](https://github.com/GDPatch/GDPatch) so **_I currently have no knowledge about actually implementing this mod for use of GDPatch_**. I'm sure someone will package this before I regain the interest to carry it on. If you do, please open a PR; in my opinion all it would need is a wrapper as an entry point to open the theater, the UI includes an 'exit' button to switch the scene back to the main menu so you can play the game.

I had started this project the day before build `25015493` (Aug 29-2026). I had tested on the current build `25104378` (Sept. 3-2026) _briefly,_ everything still works. It's been about a week, there are some TODOs and bugs that are good to know.

---

## Index
  - [Features](#Features)
    - [File Picker](#file-picker)
    - [Player Controls](#player-controls)
    - [Path-line Visualization](#path-line-visualization)
    - [Free Cam](#free-cam)
  - [TODOs & Bugs](#todos--bugs)
  - [Credits](#credits)

---

# Features
Working e2e file picker; auto loads matching level (untested beyond lvl_2_1 & regular world files that match this naming convention, I haven't gotten that far in game :p). Scrubbable timeline with play/pause/seek/speed controls (0.25-2.00x presets). Event markers found in the ghost data with toasts (Fire & Jump; afaik this is all that is stored). POV camera is driven by the recorded input data. Path-line visualization. Free Cam for exploration.

### File Picker
File picker starts in `%USERPROFILE%/AppData/Roaming/CICADAMATA/{64BitSteamID}/Ghosts/` for ease of access, if not then you'll have to path your own way to the `Ghost/` directory. The level is loaded based upon the ghost replay filename; `lvl_1_1.res` will look for and load `lvl_1_1.tcsn`. I found a folder named `abandon_all_hope/` when developing and saw some level content within, so there is a recursive look for those levels assuming the ghost filename is the same as those tcsn scenes.

![file_picker](/assets/file_picker.png)

### Scrubbable timeline
Events found in ghost replay file are marked on the timeline; Fire (red flags) & Jump (blue flags).

![timeline](/assets/timelinegif.gif)

### Player controls
_Play / Pause_

![im_sure_you_get_it](/assets//play_no_pause.gif)

_Jump to Previous / Next event_

![jump_to_event](/assets/jump_to_event.gif)

_Speed Presets_

![speed_presets](/assets//speed_presets.gif)

### Path-line Visualization
A visual path of the run.

![path_line](/assets/path_line.png)

### Free Cam
Toggle Free Cam to do some exploration.

![freecam](/assets/free_cam.gif)

---

## TODOs & Bugs
These are items I believe would improve the system as well as some bugs that fight my overrides.

|  | Description |
|-------|-------------|
| Replay Interpolation | Replay motion at low speed is visually choppy since it's linear inperpolating between the raw recorded keyframes rather than a smoothed curve. Would fix with my own preprocessing integration as the `INTERPOLATION_CUBIC` doesn't seem to really have a big improvement (currently set) however smoothing out the frames would come at the cost of a 'strict' 1:1 reproduction of the run (or as 'strict' as the engine records/processes). |
| Timeline Scrubbing | Clicking the timeline jumps to that point in time, but the world (some enemies, goal states) doesn't seem to match. It just continues from wherever it already was. Live dragging with a accurate world state would need re-deriving the positions per-frame, not just seeking the animation. |
| Enemy state during pause | `ReplayTheater` runs with `PROCESS_MODE_ALWAYS` so it survives `get_tree().paused = true`, but a couple flying enemy types apparently don't respect this pause and will keep moving. |
| POV Camera | The POV camera is a bolted-on addition (not part of the original rig), parented to `BunnyGal`, so it can clip into the world geometry at close range. |
| Level intro subtitles/audio play | Levels with a ship-arrival intro (ambient subtitles, audio) still trigger normally when loaded as a replay backdrop, I haven't been able to trace it back to it's exact source call, only as far as `game_ui.gd`'s subtitle display function. |
| Mouse Mode | Upon level load the`Player2.gd` process drives the `global.showmouse` to false on spawn. I patched this by reasserting it to true after disabling the spawned player but is not a guarantee if the dev flips it unexpectedly later. |
| ESC Conflicts with native pause menu | Fires underneath the replay HUD and resets my mouse override. It needs it's own intercept on the real pause toggle script (I haven't been able to identify it). |
| Right Clicking the mouse in POV | Bound to an existing in game action, which fights the my mouse visibility override. |
| `global._player` reference churn | I'm not entirely sure what happens, however `player_spawn.gd` appears to only assign `global._player` when it's null, once, so upon reloading a second replay without completely restarting the game can leave that reference pointing at an already freed player unless it's reassigned. Currently patched around, not a 'guaranteed safe' fix under every code path that touches `global._player`. |
| Replay Recording/Saving | Currently not implemented but `save()` lives in `replay_file.gd`. The plan is to record in game operations as to have a smoother replay viewing experience. |
| Previous event snapping | Seeking to a previous event while playing will not sidestep the last event and will instead snap to itself. This is caused by `scrub_bar.step` being set to a low threshold of `0.001`. I had prepared for my replay record/save feature that would capture many events and key presses in sequence and would theoretically conflict with the skipping if it be a larger threshold. |

---

## Credits
Credits to [elysiaisalive](https://github.com/elysiaisalive) for the [Freecam logic](https://github.com/elysiaisalive/cicadamata-mataviewer).