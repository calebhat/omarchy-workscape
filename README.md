# WorkScape

**Monitor and workspace management suite for [Omarchy](https://omarchy.org) + Hyprland.**

WorkScape is the control panel for how this machine should look in each place you sit: which displays are on, which workspace lives on which monitor, which apps open where, how tiling behaves, and what happens when a new window does not fit. Profiles switch from the bar (or at login) when the connected displays — and optionally Wi‑Fi / LAN — match.

It is a fork of [tenzin.auto-workspace](https://github.com/yesheytenzin/auto-workspace), extended into a full workspace automation suite.

Plugin id: `io.github.calebhat.workscape`  
Formerly **WorkBook**. Existing data under `~/.local/state/omarchy/workbook/` is copied on first run.

<p align="center"><img src="preview.png" alt="WorkScape — workspace presets, overflow, and live preview" width="900"></p>

| Workspaces | Displays | Gestures | Profiles |
|---|---|---|---|
| [![Workspaces](docs/screenshots/workspaces.png)](docs/screenshots/workspaces.png) | [![Displays](docs/screenshots/displays.png)](docs/screenshots/displays.png) | [![Gestures](docs/screenshots/gestures.png)](docs/screenshots/gestures.png) | [![Profiles](docs/screenshots/profiles.png)](docs/screenshots/profiles.png) |

`preview.png` is the omarchyplugins.com card image. Extra shots live in `docs/screenshots/` and in this README.

---

## Marketplace blurb

Use this on [omarchyplugins.com](https://omarchyplugins.com) / the marketplace issue form.

**Short (listing description)**

> Monitor and workspace management suite for Omarchy. Preset windows per workspace, bind workspaces to displays, automate overflow and locks, and switch the whole layout from the bar when you dock, undock, or change networks.

**Longer (about / README excerpt)**

> WorkScape is an Omarchy + Hyprland suite for people who live on more than one monitor layout. Save a **laptop** profile and a **desk** profile: connected displays (EDID, not `DP-1`) pick the match, optional Wi‑Fi SSID / LAN subnet splits two identical laptop-only setups. Each profile presets apps onto workspaces, pins those workspaces to named monitors, and chooses native tiling (dwindle, scrolling, master) and whether extras stay or move to the next workspace. The **organizer** edits up to 20 panes with horizontal and vertical splits, drag-to-swap, tile vs float, and per-window opacity/borders. **Fill next open workspace** chains unused workspaces with a global max windows per workspace. Trackpad workspace swipes can follow the profile or stay global. Apply from the bar, a middle-click, or optionally at login. Occupied workspaces are left alone unless you **Fresh Workscape**. A profile that does not match the connected displays cannot be applied.

**Suggested listing metadata**

| Field | Value |
|---|---|
| Category | Desktop |
| Tags | Hyprland, Workspaces, Bar |
| Install | `omarchy plugin add https://github.com/calebhat/omarchy-workscape.git --enable` |

---

## Install

```sh
omarchy plugin add https://github.com/calebhat/omarchy-workscape.git --enable
```

The widget defaults to the **right** of the bar:

```sh
omarchy bar move io.github.calebhat.workscape --section right
```

If `tenzin.auto-workspace` is still enabled, disable it so both do not launch apps:

```sh
omarchy plugin disable tenzin.auto-workspace
```

### Dependencies

Stock Omarchy already has these:

- `python3`, `jq`, `hyprctl`, `notify-send`, `flock`, `socat`
- Optional: `nmcli` / `iw` (Wi‑Fi SSID for network matching)

### Remove

```sh
omarchy plugin remove io.github.calebhat.workscape
```

That does **not** delete saved profiles or a Hyprland persist file you opted into:

```sh
rm -rf ~/.local/state/omarchy/workscape ~/.local/state/omarchy/workbook
rm -f ~/.config/hypr/workscape-gestures.lua ~/.config/hypr/workbook-gestures.lua
```

Then restore Hyprland files this plugin may have written **only if you opted into persist**:

```sh
~/.config/omarchy/plugins/io.github.calebhat.workscape/workscape.sh --restore-hypr
```

That removes only the marked WorkScape require block from the current `hyprland.lua` (later user edits stay). The backup is used only if `hyprland.lua` is missing after an interrupted write. Generated lua files are deleted only if their content still matches the digest recorded when this plugin wrote them; a later edit is left in place as a conflict. Old `workscape-layout.lua` (custom tape) is unused — delete it if present.

---

## User manual

Open the panel from the workspace chip in the bar (left click) — the chip draws the focused workspace’s split. **Middle-click** the chip to apply the matching profile without opening the panel.

The **header profile** is what you are editing — same idea as picking a theme in ThemeBook. Tabs: **Workspaces**, **Displays**, **Gestures**, **Profiles**.

### 1. Profiles — one setup per environment

A profile is a named snapshot: monitors, workspace pins, app presets, layout prefs, optional network bind, optional overflow chain, optional gestures.

**Save current layout as profile** asks for a name, then stores the connected displays. Optionally bind the current network (on by default).

**How a profile is chosen**

1. Connected displays, matched by EDID serial then description — **not** `DP-1` / `DVI-I-1` (those names swap on a dock).
2. If the profile has a bound network, Wi‑Fi SSID or the default-route IPv4 subnet must match (never Tailscale or public IP).
3. If two still match, the network-bound profile wins. Only one layout applies.

**Network**

- **Bind this network / Rebind now** snapshots the live SSID + subnet.
- **Edit network** types SSID/subnet when you are not on that LAN.
- **Clear network** makes that profile the any-network fallback for its display set (only one fallback per display set).
- A display set + network can belong to one profile; binding a network already used on the same displays takes those tokens off the other profile.

SSID names can be spoofed. Treat network matching as home vs office convenience, not a security boundary.

**Apply matching profile at login** is **off** by default. When on, login waits for Hyprland; if this layout has no any-network fallback it also waits up to 45s for Wi‑Fi/LAN, then applies the unique match.

**Apply matching** (or middle-click the bar chip) does the same match any time. Plugging in a dock (or unplugging) switches the selected profile to the matching layout so **Fresh Workscape** targets that profile. **Apply** on a profile card runs that profile as saved **only if it matches the connected displays** (and bound network). A desk-dock profile will not apply on a laptop-only setup. Empty assigned workspaces still get their apps and layouts. Occupied assigned workspaces are not relaunched. If the matching profile **changed** (undock → laptop, dock → desk), Apply matching still moves those workspaces onto the new pins and restamps their layouts; it does not close windows. Same-profile Apply matching leaves occupied geometry alone. **Fresh Workscape** closes windows on this profile’s preset workspaces, then applies from scratch and closes the panel; workspaces that are not part of the profile (for example a terminal on WS 8) stay put. **Escape** closes the panel (and any open overlay first).

### 2. Displays — monitors for this profile

- Canvas of the profile’s monitors; drag to arrange; **Apply this profile** writes Hyprland output layout when the profile matches live displays. **Fresh Workscape** closes windows on this profile’s preset workspaces, then applies empty so apps and layouts load from scratch.
- Turn a display **off** for this profile (keep at least one on).
- Match mode: **exact layout** vs **all required present**.
- Capture live arrangement after you rearrange in the compositor.

### 3. Workspaces — presets, tiling, locks, overflow

Pick workspace **1–10** for app presets (overflow chain can use **1–20**).

**Load workspace on** pins that workspace to a named monitor in this profile.

**Toggle apps** in the list to place them on the selected workspace. The name shows a live **×N** count of that app on this workspace; the subtitle says **N on this workspace** when there is more than one. **+** adds another window of the same app (two Braves, two terminals). Toggle off removes one instance (the last). Custom commands go in the bottom row.

**Capture WS** snapshots whatever is open on this workspace into the profile: the exact on-screen split ratios, size/place, terminal working directory (from the shell child of `foot` / Ghostty), and a URL when Hyprland exposes it (Brave *web apps* encode the site in the window class; a normal Brave tab only has the page title — that URL cannot be read). Two or more tiled windows are locked to those ratios. Apps without a `.desktop` file (TUIs) need a desktop entry or WorkScape **extraApps** in config.

**What can be saved per window:** exec, name, class, title, tile vs float, geometry, opacity/borders, lock, **cwd** (terminals), **url** (web apps / explicit `https://` in the command). Not available: the URL of an ordinary browser tab, scroll position, cookies/login, tmux sessions, SSH remote cwd unless it is the local shell.

**Layouts** (per workspace)

| Layout | Behavior |
|---|---|
| Dwindle | Hyprland default split tree |
| Scrolling | First window fills; new windows are 1/Visible columns. Super+Left/Right pan on this workspace |
| Master | Large pane + stack |

**Split shapes** (Even, Focus 25/50/25, Main, Golden, Thirds, Wide centre, Stacked, Grid) stamp pane sizes. Two or more tiled apps also **lock** those sizes so Apply can restore them. They do not change dwindle/scrolling/master. Drag splitters to snap (Shift = free; double-click evens). Click a workspace number to edit it in the panel (Hyprland focus stays put). The bar chip is a miniature of the focused workspace.

**Visible columns** (1–20) is **per scrolling workspace**. It is *not* the global overflow max.

**Keep extra windows on this workspace** (on) leaves extras on this workspace. Off: extras still open, then move to the next unused workspace (assigned workspaces and leave-alone pins are skipped).

Controls that do not apply to the selected workspace are **hidden**, not greyed out:

| Workspace setup | Layout picker | Visible columns | Keep extra windows |
|---|---|---|---|
| Dwindle, extras stay or bounce | Dwindle / Scrolling / Master | hidden | shown |
| Scrolling | Dwindle / Scrolling / Master | shown | shown |
| Master | Dwindle / Scrolling / Master | hidden | shown |
| Locked split (every assigned window pinned to a size, two or more apps) | hidden (stays dwindle) | hidden | hidden — extras always bounce so the split stays put |

**Fill next open workspace** (Profiles tab) is hidden unless a workspace bounces extras, or the overflow chain is already on. − / max / + / Choose… only appear once that chain is on.

**Super+W** closes the focused column and focuses the **next** one in left-to-right order, including a strip you resized very small.

**SUPER+J** (Omarchy toggle split) is dwindle-only. On scrolling it does nothing, so Hyprland does not show a Lua error overlay.

**Fill next open workspace** is the **global** chain for this profile:

- Toggle it on; unused workspaces (no pinned apps) are added if the chain is empty.
- **− / N / +** is **max windows per overflow workspace**, separate from each unique Stage workspace’s Visible columns.
- **Choose…** lists workspaces 1–20. Dots mark workspaces that already have pinned apps. **Set Stage** selects unused workspaces and uses Stage on them. **None** clears the list. **Max / workspace** in that dialog is the same global cap.
- Assigned workspaces keep their own send-extra / lock / Visible columns. Overflow only fills the chain (typically empty Stage workspaces).

The extras watcher listens to Hyprland window events (no extra polling). A bounced window focuses the **destination workspace and that window**. After **Apply**, leftover windows on blocked workspaces are swept off so they do not steal lock geometry — except **occupied** workspaces, which Apply never touches.

**Preview and organizer**

- Mini preview (right column): drag **vertical and horizontal** splitters. **🔓/🔒** on a pane (or right-click) locks its size; **×** removes it. The app list has the same lock button. **Expand** opens the full organizer.
- **Organizer** (almost the whole panel): up to **20** panes.
  - Drag a **shared edge** to resize both tiled neighbors.
  - Drag a **tiled** pane as a whole: onto another pane’s **center** to **swap** cells; onto an **edge** to **split** that way (left/right/up/down). Dropping off a pane snaps back. Tiled panes stay in the grid (no overlapping).
  - **← → ↑ ↓** split the selected pane with the next tiled app.
  - **Tile / Float** per window. **Float** lifts that pane out of the tiling set; remaining tiled panes **expand to fill the hole** (like Hyprland when you float a window). The float is drawn and applied **above** tiled windows (`alter_zorder top`). Drag a float by the body (clamped to the workspace); drag its edges to resize it alone.
  - **Tile** again **snaps** the window into the tiled cell under it (left/right/top/bottom of the tile you are over), and neighbors shrink — same idea as unfloating in Hyprland.
  - **⚙** sets focused and unfocused **opacity**, border on/off, and border width for that window. Focus changes update chrome without extra polling.
  - **×** removes that window from the workspace.
  - **Reset** clears custom geoms and re-packs from the workspace layout.
- Apply places tiled splits in the compositor; float windows are placed at their organizer boxes and raised above tiles. Workspaces that already have windows are still skipped on Apply.

### 4. Gestures — trackpad workspace swipes

Edits save and apply on change (no Apply button).

- **Global** is the default store and the default view. Every profile uses it until you opt into **This profile**.
- Profile gestures are a separate store; editing one does not overwrite the other.
- **Swipe method** (Natural vs Swap left/right) is one row.
- Workspace swipe is registered for this session when the shell starts (`hyprctl eval`). It does **not** edit `hyprland.lua` unless you opt in.
- **Keep swipes after Hyprland reload** is **off** by default. Turning it on writes `~/.config/hypr/workscape-gestures.lua` and inserts `pcall(require, "hypr.workscape-gestures")` into `hyprland.lua` (backed up first). `workscape.sh --restore-hypr` undoes that.
- **SUPER+, / .** previous and next workspace (follows Skip empty).
- **SUPER+J** toggles dwindle split only; ignored on scrolling so the compositor does not show a Lua error.

### 5. Typical day

**Laptop-only (home Wi‑Fi bound)**  
One profile, laptop panel, browser / mail / chat presets, overflow chain for spare Stage workspaces.

**Same laptop at the office (different SSID or subnet)**  
Second profile, same monitors, different network bind and maybe different apps.

**Desk dock**  
Three-display profile, workspaces pinned to named monitors, locked two-pane coding workspace with extras sent away.

Undock → **Apply matching** (or login apply) → laptop profile. Dock → desk profile.

---

## Config and CLI

Config: `~/.local/state/omarchy/workscape/config.json` (outside the plugin tree so saves do not reload the shell).

```sh
workscape.sh --live-status
workscape.sh --apply-matching
workscape.sh --apply-profile desk-dock
workscape.sh --fresh-apply-profile laptop   # close that profile’s preset workspaces, then apply empty
workscape.sh --capture-workspace 2          # snapshot live windows on WS 2 as JSON
omarchy-shell -q io.github.calebhat.workscape applyMatching
omarchy-shell -q io.github.calebhat.workscape applyProfile laptop
omarchy-shell -q io.github.calebhat.workscape applyFresh desk-dock
omarchy-shell -q io.github.calebhat.workscape status
omarchy-shell -q io.github.calebhat.workscape.panel toggle   # open/close the popout
```

---

## Hyprland files

Apply copies `hypr/workscape-binds.lua` to `~/.config/hypr/workscape-binds.lua` so Super+arrows on scrolling stay on this workspace. Gesture apply writes `workscape-gestures.lua` and inserts `pcall(require, "hypr.workscape-gestures")` into `hyprland.lua` when missing. For Super+arrow binds at compositor start (before the first Apply), add:

```lua
pcall(require, "hypr.workscape-binds")
```

## Marketplace readiness

- `omarchy plugin validate .` must pass (no symlinks in the plugin folder).
- Listing uses this README’s **Marketplace blurb**, category **Desktop**, tags **Hyprland, Workspaces, Bar**.
- `preview.png` is 16:9 for the store card. Extra shots: `docs/screenshots/`.
- Do not file the omarchyplugins.com issue until the GitHub `master` commit has been day-to-day tested. The site clones HEAD.

## Security notes

Plugins run unsandboxed. WorkScape only interpolates allowlisted values into `hyprctl eval` (workspace 1–20, `0x` addresses, connector names). User-authored launch commands in the profile are executed as that user. Config is `0600` under `~/.local/state`. Gesture persist and `hyprland.lua` edits are **off until you enable Keep swipes after Hyprland reload**. `workscape.sh --restore-hypr` removes those files. Network matching is convenience, not a trust boundary (SSIDs can be spoofed). Apply/Fresh of a profile that does not match live displays is refused.

## License

MIT. See `NOTICE.md` for upstream attribution.
