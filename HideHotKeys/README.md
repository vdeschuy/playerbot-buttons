# HideHotKeys

Hides the keybind text on all action buttons, and optionally the macro name,
for the **WoW Classic TBC 2.5.3** client (`## Interface: 20503`).

## Behaviour

- Hides the keybind text on the main bar, all `MultiBar*` bars, the bonus bar
  and the pet bar.
- Hides the macro name on the action buttons.
- **Keeps the range indicator:** when an action is out of range, the game's own
  `"●"` marker is shown in red in place of the keybind. (In this client the range
  indicator shares the same fontstring as the keybind, and out-of-range is
  normally signalled by colouring that text red — see
  `ActionButton_UpdateRangeIndicator`.)
- Works both at login and while playing: it hooks `ActionButton_UpdateHotkeys`,
  `ActionButton_Update` and `ActionButton_UpdateRangeIndicator`, so a button
  refresh cannot bring the text back.

## Commands

| Command | Effect |
|---|---|
| `/hotkeyhide` | toggle keybind text |
| `/macrohide`  | toggle macro name text |
| `/hhk`        | help + current state |

Settings are stored per character in `HideHotKeysDB`
(`## SavedVariablesPerCharacter`).

## Install and development

Copy the `HideHotKeys/` folder into the client's `Interface/AddOns/`.
For development, a symlink from the client to this folder is optional.

Part of the `addons` monorepo (`../README.md`). Edit `HideHotKeys.lua`, then
`/reload`.
