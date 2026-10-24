# BotButtons

A draggable, keybindable row of quick-command buttons for the
**cmangos/playerbots** module.

Supported clients:

| Client | Interface |
|---|---|
| Classic Era 1.14.x | 11400–11402 |
| TBC Classic 2.5.2 / 2.5.3 | 20502 / 20503 |
| WotLK Classic 3.4.3 | 30403 (experimental) |

## Install

`install.sh` is independent of any particular game install. It requires Bash
(Linux, macOS, or WSL). Point it at the game root, a `_classic_era_` / `_classic_`
folder, or an `Interface/AddOns` folder.

```sh
./install.sh "/path/to/World of Warcraft"
./install.sh --flavor tbc     "/path/to/World of Warcraft/_classic_"
./install.sh --flavor wotlk   "/path/to/World of Warcraft/_classic_"
./install.sh --flavor classic "/path/to/World of Warcraft/_classic_era_/Interface/AddOns"
```

- Flavor is detected from `.build.info` when possible.
- A bare `_classic_` folder is ambiguous between TBC and WotLK; pass
  `--flavor tbc` or `--flavor wotlk` if `.build.info` is unavailable.
- `--interface 11400` overrides the TOC interface for an unusual client build.
- `--dry-run` shows what would be installed.
- Files are copied to `Interface/AddOns/BotButtons/`; no symlinks are used.

Restart the client after the first install. Later updates usually need only
`/reload`.

### Manual install

Copy `BotButtons.lua` and `Bindings.xml` into
`Interface/AddOns/BotButtons/`, then create `BotButtons.toc`:

```toc
## Interface: 11402
## Title: |cff33ff99Bot|r|cffffd100Buttons|r
## Notes: Draggable, keybindable quick-command buttons for cmangos playerbots
## Author: Roshkosh
## Version: 1.4.7
## SavedVariables: BotButtonsDB
## DefaultState: Enabled

BotButtons.lua
```

Use the interface number for your client from the table above.

## Use

- **Drag** the bar by its grip (left edge) when it is unlocked.
- **Left-click** a button to fire its command; some have a **right-click** action
  (see the tooltip on each button).
- **Settings / keybinds:** open the window with `/bb`. Click a binding box and
  press the key you want (ESC cancels). Bindings also appear in the standard
  **Key Bindings → BotButtons** screen.
- Slash: `/bb` (open), `/bb lock`, `/bb unlock`, `/bb show`, `/bb hide`,
  `/bb announce`, `/bb reset`, `/bb tank <name>`, `/bb healer <name>`.

## Buttons

| Button | Left-click | Right-click |
|---|---|---|
| Follow | `/p follow` | `/p flee` (regroup) |
| Stay | `/p stay` | — |
| Regroup | `/p flee` (stop attacking + follow) | — |
| Summon | teleport the group's bots to you (`/p summon`) | — |
| Attack | `/p attack` | — |
| Pull | whisper `follow` to your tank, wait for its reply, then `/p pull` | — |
| Stop / Go | toggle `passive` on all bots (`all +passive` / `all -passive`) | force attack (`all -passive`) |
| Melee Hold | toggle melee `passive` (`co +passive` / `co -passive`) | release melee (`co -passive`) |
| Wait at Pull | toggle `wait for attack` (`co +wait for attack` / `co -wait for attack`) | force off (`co -wait for attack`) |
| Tank Attack | whisper your tank `tank attack`, wait for its reply, then whisper `attack` | — |
| Max DPS | `/p max dps` | — |
| Healer Stay | whisper your healer `stay` | — |

`/p` broadcasts to every bot in your group; the pull, tank-attack, melee and
healer buttons whisper specific bots. The healer's and tank's names are
configurable in settings, or with `/bb tank <name>` / `/bb healer <name>`.

If a name is not in your group, the whisper is skipped and a one-line hint is
printed instead.

**Pull whispers `follow` to the tank first.** A bot that is holding position
(`stay`) will not move, so it never walks to its pull target. The pull waits for
the tank to answer the follow before going out. If the tank stays silent (stale
name, another player's bot, `silent` bots, or a rate-limited reply), the pull
still goes out after a 1.5 s fallback.

**Tank Attack is a tank-only attack.** It tells the tank to drop `passive` and
then attack your current target. It uses the same answer-then-act handshake as
the pull, so `attack` cannot arrive before `passive` is gone.

**Every press is announced in chat** (e.g. `BotButtons: Regroup`). It is a
private local message; nothing is sent to a channel. Turn it off with the
*Announce presses in chat* checkbox or `/bb announce`.

`summon` pulls the bots to you. On a GM account it works anywhere; otherwise it
falls back to a meeting stone: bots to you if a stone is near you, or you to a
bot if a stone is near it.

The three toggles (Stop/Go, Melee Hold, Wait at Pull) send absolute `+`/`-`
commands driven by the addon's own toggle state, not `~`. An addon cannot read a
bot's real strategies, so absolute commands keep the button state predictable.
If things drift, use **Settings → Force toggles off (resync)**.

## How commands are sent

Commands are hidden `BOT` addon messages on party/raid/whisper, so they do not
spam chat. Enable **Send as visible chat** in settings to send ordinary chat
instead (useful for debugging).

## Development

The addon source is this folder:

```text
BotButtons.lua
Bindings.xml
BotButtons.toc
install.sh
README.md
```

Edit `BotButtons.lua`, then install it into the client with `./install.sh` and
restart the client or `/reload`.

## Notes / known limits

- **Indicator means "toggle ON", not "last pressed":** the green border shows
  what the addon has commanded, not the bot's real state. A bot changed
  elsewhere can be out of step until you press the button again. One-shot
  buttons flash for about 0.6 s as "command sent" feedback.
- **First install:** a new addon folder may need a client restart before it
  appears in the AddOns list; after that, `/reload` is enough.
- **Melee Hold** is class-based (warrior/rogue/paladin/shaman/druid; death knight
  on WotLK) because addons cannot read a bot's spec. Use the whisper-by-name
  buttons when you need exact targeting.
- If the client lacks `SetPropagateKeyboardInput`, a key pressed while capturing
  a binding may also trigger its normal action; press the key once and it is
  bound.
- WotLK 3.4.3 support is experimental. Please report any client-specific issues.
- Icons are limited to the vanilla texture set (all present in 1.14.2, 2.5.3
  and 3.4.3). A TBC-only icon such as `Ability_Hunter_Readiness` renders as a
  green square on Classic, so check a texture exists in `ICONS` for the oldest
  client you support before using it.
