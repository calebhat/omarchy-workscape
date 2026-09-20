# Contributing

Source of truth: this repository, installed as a normal Omarchy plugin.
Display name is **WorkScape**; plugin id is `io.github.calebhat.workscape`.

```bash
omarchy plugin add https://github.com/calebhat/omarchy-workscape.git --enable
omarchy plugin validate ~/.config/omarchy/plugins/io.github.calebhat.workscape
```

On a development machine, rsync into the user plugin dir (plugin folders must
not contain symlinks):

```bash
rsync -a --delete --exclude .git --exclude .gitignore --exclude test \
  --exclude CONTRIBUTING.md \
  ./ ~/.config/omarchy/plugins/io.github.calebhat.workscape/
omarchy restart shell
```

Run tests from the repo root:

```bash
test/run
omarchy plugin validate .
```

`test/run` is unit tests plus the dummy-profile self-check. It does **not** spawn windows or write `~/.local/state/omarchy/workscape/config.json`.

Dummy matrix (all layouts/extras, workspaces 11–19, user config untouched):

```bash
python3 test/dummy_live.py              # isolation self-check
python3 test/dummy_live.py --live       # spawn workscape-dummy-* foots only
```

Checklist, issue history, and scenario IDs: `test/CHECKLIST.md`, `test/ISSUES.md`. Read ISSUES.md before changing extras, restore, or layoutmsg.

Marketplace listing: only after this tree is on GitHub `master` (the site
clones HEAD). Submit via `omacom/omarchy-plugin-marketplace` using
`SUBMISSION.md` (category Desktop; tags hyprland, workspaces, bar).

Version in `manifest.json` is **1.11.0**.
