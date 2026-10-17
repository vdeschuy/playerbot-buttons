# BotButtons

A draggable, keybindable row of quick-command buttons for the **cmangos/playerbots**
module (the bot system this server runs). Built for the TBC Classic 2.5.3 client
(Interface 20503).

## Use

- **Drag** the bar by its grip (left edge) when it is unlocked.
- **Left-click** a button to fire its command; some have a **right-click** action
  (see the tooltip on each button).
- **Settings / keybinds:** open the window with `/bb` (there is no longer a gear
  button on the bar). Click a binding box in the window and press the key you
  want (ESC cancels). The same bindings also appear in the standard
  **Key Bindings → BotButtons** screen.
- Slash: `/bb` (open), `/bb lock`, `/bb unlock`, `/bb show`, `/bb hide`, `/bb announce`, `/bb reset`.

## Buttons

| Button | Left-click | Right-click |
|---|---|---|
| Follow | `/p follow` | `/p flee` (regroup) |
| Stay | `/p stay` | — |
| Regroup | `/p flee` (stop attacking + follow) | — |
| Summon | teleport the group's bots to you (`/p summon`) | — |
| Attack | `/p attack` | — |
| Pull | whisper `follow` to your tank, then `/p pull` | — |
| Stop / Go | toggle `passive` on all bots (`all +passive` / `all -passive`) | force attack (`all -passive`) |
| Melee Hold | toggle melee `passive` (`co +passive` / `co -passive`) | release melee (`co -passive`) |
| Wait at Pull | toggle `wait for attack` (`co +wait for attack` / `co -wait for attack`) | force off (`co -wait for attack`) |
| Tank Attack | `/p tank attack` | — |
| Max DPS | `/p max dps` | — |
| Healer Stay | whisper your healer `stay` | — |

`/p` broadcasts to every bot in your group; the pull, melee and healer buttons
whisper specific bots. The healer's and tank's names are configurable in settings.

**Pull whispers `follow` to the tank first.** A bot that is holding position
(`stay`) will not move, so it never walks to its pull target. `follow` clears that
and the pull then works; the bot walks back to where it started afterwards.

**Every press is announced in chat** (e.g. `BotButtons: Regroup`, or
`BotButtons: Stop / Go -> ON` for the toggles), so the chat log doubles as a record
of what you pressed. It is a private local message — nothing is sent to any
channel. Turn it off with the *Announce presses in chat* checkbox or
`/bb announce`.

`summon` pulls the bots to you. On a GM account — which this server's `ADMIN`
account is — it works anywhere; otherwise (no `AiPlayerbot.NonGmFreeSummon`) it
falls back to a meeting stone: bots to you if a stone is near you, or you to a bot
if a stone is near it.

The three toggles (Stop/Go, Melee Hold, Wait at Pull) send **absolute `+`/`-`
commands** driven by the addon's own toggle state, not `~`. An addon cannot read a
bot's real strategies, so a `~` toggle would flip whatever the server currently
has and compound any drift; with absolute commands the button always commands the
state it shows, and a one-off desync self-corrects on the next press.

## How commands are sent

The same way the Mangosbot addon sends them: as hidden `BOT` addon messages on
party/raid/whisper, so they do not spam chat. Enable **"Send as visible chat"** in
settings to send ordinary chat instead (useful for debugging).

## Development

Source of truth: **`~/Games/wow/addons/BotButtons`**, part of the addons monorepo
(see `../README.md`). The game client loads it through a symlink at
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
zip -qr ~/Games/wow/tbc/addons/BotButtons-1.4.0.zip BotButtons
```

## Notes / known limits

- **Indicator means "toggle ON", not "last pressed":** the green border is
  per-button and means *this toggle is commanded ON by the addon*; several can be
  lit at once. It is the addon's own view — **the client cannot read a bot's real
  strategies**, so a bot changed elsewhere (another addon, the mangosd console,
  `apply_bots.py`, or a relog onto a recreated bot) can be out of step until you
  press the button again. One-shot buttons only flash the border for ~0.6 s as
  "command sent" feedback. If things ever drift apart, **Settings → "Force toggles
  off (resync)"** clears the addon state and sends the matching off commands.
- **First install:** a brand-new addon folder may need a client restart (or a
  relog) before it appears in the AddOns list; once it is recognised, `/reload`
  re-reads the files.
- **Melee Hold** is class-based (warrior/rogue/paladin/shaman/druid) because
  addons cannot read a bot's spec, so a holy paladin or resto shaman counts as
  "melee". Use the whisper-by-name buttons if you need exact targeting.
- If the client lacks `SetPropagateKeyboardInput`, a key pressed while capturing a
  binding may also trigger its normal action; press the key once and it is bound.
