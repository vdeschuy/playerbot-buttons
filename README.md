# BotButtons

A draggable, keybindable row of quick-command buttons for the **cmangos/playerbots**
module (the bot system this server runs). Built for the TBC Classic 2.5.3 client
(Interface 20503).

## Use

- **Drag** the bar by its grip (left edge) when it is unlocked.
- **Left-click** a button to fire its command; some have a **right-click** action
  (see the tooltip on each button).
- **Settings / keybinds:** type `/bb`, or click the gear button. Click a binding
  box in the window and press the key you want (ESC cancels). The same bindings
  also appear in the standard **Key Bindings → BotButtons** screen.
- Slash: `/bb` (open), `/bb lock`, `/bb unlock`, `/bb show`, `/bb hide`, `/bb reset`.

## Buttons

| Button | Left-click | Right-click |
|---|---|---|
| Follow | `/p follow` | `/p flee` (regroup) |
| Stay | `/p stay` | — |
| Regroup | `/p flee` (stop attacking + follow) | — |
| Attack | `/p attack` | — |
| Pull | `/p pull` | — |
| Stop / Go | `/p all ~passive` (toggle) | `/p all -passive` |
| Melee Hold | toggle melee `co ~passive` (melee keep following, stop attacking) | melee `co -passive` |
| Wait at Pull | `/p co ~wait for attack` (toggle) | — |
| Tank Attack | `/p tank attack` | — |
| Max DPS | `/p max dps` | — |
| Healer Stay | whisper your healer `stay` | — |
| Settings | open the settings window | — |

`/p` broadcasts to every bot in your group; the melee and healer buttons whisper
specific bots. The healer's name is configurable in settings.

## How commands are sent

The same way the Mangosbot addon sends them: as hidden `BOT` addon messages on
party/raid/whisper, so they do not spam chat. Enable **"Send as visible chat"** in
settings to send ordinary chat instead (useful for debugging).

## Development

Source of truth: **`~/Games/wow/addons/BotButtons`** (a git repository). The game
client loads it through a symlink at
`clients/tbc-2.5.3/_classic_/Interface/AddOns/BotButtons`, so there is only one
copy to edit:

```sh
cd ~/Games/wow/addons/BotButtons
$EDITOR BotButtons.lua        # edit the source
```

Then `/reload` in-game (or restart the client) to apply. Build a distributable
zip into the shared addon folder with:

```sh
cd ~/Games/wow/addons
zip -qr ~/Games/wow/tbc/addons/BotButtons-1.1.0.zip BotButtons -x 'BotButtons/.git/*'
```

## Notes / known limits

- **Last-pressed indicator:** the button you press gets a green border that stays
  until you press another one. The three toggles (Stop/Go, Melee Hold, Wait at
  Pull) toggle their own highlight off when pressed a second time. This is a
  "last pressed" cue only — the addon cannot read real bot state.
- **Restart the client** (or at least re-login) after installing so the addon
  loads; new addons are not picked up by `/reload` alone.
- **Melee Hold** is class-based (warrior/rogue/paladin/shaman/druid) because
  addons cannot read a bot's spec, so a holy paladin or resto shaman counts as
  "melee". Use the whisper-by-name buttons if you need exact targeting.
- If the client lacks `SetPropagateKeyboardInput`, a key pressed while capturing a
  binding may also trigger its normal action; press the key once and it is bound.
