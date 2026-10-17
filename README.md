# WoW addons (monorepo)

Source of truth for our custom World of Warcraft addons. One folder per addon,
one repository — so we do not end up with a repo per addon.

## Layout

```
addons/
├── BotButtons/     draggable, keybindable command bar for cmangos playerbots
└── HideHotKeys/    hides keybind / macro-name text on the action buttons
```

## How the client sees them

Each addon folder is symlinked into the client's `Interface/AddOns`, so there is
only ever one copy to edit:

```sh
clients/tbc-2.5.3/_classic_/Interface/AddOns/BotButtons -> ../../../../../addons/BotButtons
clients/tbc-2.5.3/_classic_/Interface/AddOns/HideHotKeys -> ../../../../../addons/HideHotKeys
```

After editing, `/reload` in-game applies it. **Newly added** addons need a client
restart to be picked up (a `/reload` alone is not enough).

## Adding a new addon

```sh
cd ~/Games/wow/addons
mkdir MyAddon                       # MyAddon/MyAddon.toc + MyAddon.lua
ln -s ../../../../../addons/MyAddon \
      ~/Games/wow/clients/tbc-2.5.3/_classic_/Interface/AddOns/MyAddon
```

## Client flavours

Primary target is **Classic TBC 2.5.3** (`## Interface: 20503`). The Lua here is
written to be as flavour-agnostic as possible (version-sensitive calls are
feature-guarded), so the same code should run on the other Classic clients.

When we actually set up a 1.14.x (Classic Era) or 3.4.x (Wrath) client, prefer a
**flavour-specific TOC inside the addon** over a separate folder — one copy of
code, several interfaces:

```
MyAddon/MyAddon.toc          # fallback / current
MyAddon/MyAddon-TBC.toc      # ## Interface: 20503
MyAddon/MyAddon-Classic.toc  # ## Interface: 114xx  (Classic Era)
MyAddon/MyAddon-Wrath.toc    # ## Interface: 304xx  (Wrath)
```

(Confirm the exact flavour-TOC suffix and interface number against the client we
install at that point; the base `.toc` always loads as a fallback, flagged "out of
date" until its `## Interface:` matches.)

## Distributables

Packaged zips for the server's addon pack live in `~/Games/wow/tbc/addons/`
(not tracked here):

```sh
cd ~/Games/wow/addons
zip -qr ~/Games/wow/tbc/addons/MyAddon-1.0.0.zip MyAddon
```
