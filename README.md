# WoW addons (monorepo)

Custom World of Warcraft addons, one folder per addon and one repository.

## Layout

```text
addons/
├── BotButtons/     draggable, keybindable command bar for cmangos playerbots
└── HideHotKeys/    hides keybind / macro-name text on action buttons
```

## Install

Each addon documents its own install steps.

- **BotButtons**: run `BotButtons/install.sh` with the client path. It detects
  the client flavor and writes the correct TOC.
  ```sh
  ./BotButtons/install.sh "/path/to/World of Warcraft"
  ```
- **HideHotKeys**: copy `HideHotKeys/` into the client's
  `Interface/AddOns/` folder.

For development, a symlink from the client's `Interface/AddOns/` to the addon
source is optional. End-user installs are plain copies.

## Client flavours

`BotButtons` supports Classic Era 1.14.x, TBC 2.5.x, and WotLK 3.4.3
(experimental). `HideHotKeys` currently targets TBC 2.5.3.

Where possible, keep one copy of the Lua and select the TOC per client rather
than duplicating the addon.

## Packaging

Build zips into a local, ignored `dist/` directory:

```sh
mkdir -p dist
cd BotButtons
zip -qr ../dist/BotButtons.zip .
```
