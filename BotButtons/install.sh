#!/usr/bin/env bash
#
# Install BotButtons into a World of Warcraft Classic client.
#
# The script is independent of any particular install location. Point it at:
#   - the game root (the folder containing _classic_era_ or _classic_), or
#   - a _classic_era_ / _classic_ folder, or
#   - an Interface/AddOns folder.
#
# Usage:
#   ./install.sh /path/to/World\ of\ Warcraft
#   ./install.sh --flavor tbc /path/to/World\ of\ Warcraft/_classic_
#   ./install.sh --flavor classic /path/to/.../_classic_era_/Interface/AddOns
#   ./install.sh --dry-run /path/to/World\ of\ Warcraft
#
# Flavor is auto-detected from .build.info when possible. If the target is an
# ambiguous _classic_ folder without .build.info, pass --flavor tbc or --flavor
# wotlk. --interface overrides the TOC interface number for unusual client
# builds.

set -euo pipefail

ADDON="BotButtons"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

FLAVOR=""
INTERFACE=""
TARGET=""
DRY_RUN=0

usage() {
    cat <<'EOF'
Install BotButtons into a World of Warcraft Classic client.

Usage:
  ./install.sh /path/to/World of Warcraft
  ./install.sh --flavor tbc /path/to/World of Warcraft/_classic_
  ./install.sh --flavor classic /path/to/.../_classic_era_/Interface/AddOns
  ./install.sh --dry-run /path/to/World of Warcraft

The target may be the game root, a _classic_era_/_classic_ folder, or an
Interface/AddOns folder. Flavor is auto-detected from .build.info when
possible; for an ambiguous _classic_ folder pass --flavor tbc or --flavor
wotlk. --interface overrides the TOC interface number.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --flavor)
            [ "$#" -ge 2 ] || die "--flavor needs a value"
            FLAVOR="$2"
            shift 2
            ;;
        --interface)
            [ "$#" -ge 2 ] || die "--interface needs a value"
            INTERFACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1 (use --help)"
            ;;
        *)
            [ -z "$TARGET" ] || die "only one target path is accepted"
            TARGET="$1"
            shift
            ;;
    esac
done

[ -n "$TARGET" ] || { usage; exit 2; }
[ -d "$TARGET" ] || die "not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd -P)"
[ -f "$SCRIPT_DIR/BotButtons.lua" ] || die "BotButtons.lua not found next to install.sh"
[ -f "$SCRIPT_DIR/Bindings.xml" ] || die "Bindings.xml not found next to install.sh"

case "$FLAVOR" in
    "") ;;
    classic|classic-era|vanilla|era) FLAVOR="classic" ;;
    tbc|bcc|burning-crusade) FLAVOR="tbc" ;;
    wotlk|wrath|wotlk-classic) FLAVOR="wotlk" ;;
    *) die "unknown flavor '$FLAVOR' (use classic, tbc, or wotlk)" ;;
esac

# Walk up from the target looking for the client's .build.info.
find_build_info() {
    local dir="$1" i=0
    while [ "$i" -lt 6 ]; do
        if [ -f "$dir/.build.info" ]; then
            printf '%s\n' "$dir/.build.info"
            return 0
        fi
        case "$dir" in
            */*) dir="${dir%/*}" ;;
            *) return 1 ;;
        esac
        i=$((i + 1))
    done
    return 1
}

BUILD_INFO="$(find_build_info "$TARGET" || true)"
BUILD_VERSION=""
if [ -n "$BUILD_INFO" ]; then
    BUILD_VERSION="$(grep -oE '(1\.14|2\.5|3\.4)\.[0-9]+\.[0-9]+' "$BUILD_INFO" 2>/dev/null | tail -n 1 || true)"
    if [ -n "$BUILD_VERSION" ]; then
        BUILD_VERSION="$(printf '%s' "$BUILD_VERSION" | cut -d. -f1-3)"
    fi
fi

if [ -z "$FLAVOR" ] && [ -n "$BUILD_VERSION" ]; then
    case "$BUILD_VERSION" in
        1.14.*) FLAVOR="classic" ;;
        2.5.*)  FLAVOR="tbc" ;;
        3.4.*)  FLAVOR="wotlk" ;;
    esac
fi

if [ -z "$FLAVOR" ]; then
    case "$TARGET" in
        *_classic_era_*) FLAVOR="classic" ;;
    esac
fi

[ -n "$FLAVOR" ] || die "could not determine the client flavor; pass --flavor classic|tbc|wotlk"

if [ -z "$INTERFACE" ]; then
    case "$BUILD_VERSION" in
        1.14.0) INTERFACE=11400 ;;
        1.14.1) INTERFACE=11401 ;;
        1.14.2) INTERFACE=11402 ;;
        1.14.*) INTERFACE=11402 ;;
        2.5.2)  INTERFACE=20502 ;;
        2.5.3)  INTERFACE=20503 ;;
        2.5.*)  INTERFACE=20503 ;;
        3.4.3)  INTERFACE=30403 ;;
        3.4.*)  INTERFACE=30403 ;;
    esac
fi
[ -n "$INTERFACE" ] || {
    case "$FLAVOR" in
        classic) INTERFACE=11402 ;;
        tbc)     INTERFACE=20503 ;;
        wotlk)   INTERFACE=30403 ;;
    esac
}
case "$INTERFACE" in
    ''|*[!0-9]*) die "invalid interface number: $INTERFACE" ;;
esac

# Resolve the target to an Interface/AddOns directory.
ADDONS_DIR=""
case "$TARGET" in
    */Interface/AddOns|*/Interface/AddOns/) ADDONS_DIR="${TARGET%/}" ;;
esac

if [ -z "$ADDONS_DIR" ] && [ -d "$TARGET/Interface/AddOns" ]; then
    ADDONS_DIR="$TARGET/Interface/AddOns"
fi
if [ -z "$ADDONS_DIR" ] && [ -d "$TARGET/_classic_era_/Interface/AddOns" ] && [ "$FLAVOR" = "classic" ]; then
    ADDONS_DIR="$TARGET/_classic_era_/Interface/AddOns"
fi
if [ -z "$ADDONS_DIR" ] && [ -d "$TARGET/_classic_/Interface/AddOns" ]; then
    ADDONS_DIR="$TARGET/_classic_/Interface/AddOns"
fi
if [ -z "$ADDONS_DIR" ] && [ "$(basename "$TARGET")" = "AddOns" ] && [ "$(basename "$(dirname "$TARGET")")" = "Interface" ]; then
    ADDONS_DIR="$TARGET"
fi
[ -n "$ADDONS_DIR" ] || die "could not find Interface/AddOns under: $TARGET"

DEST="$ADDONS_DIR/$ADDON"
VERSION="$(grep -m1 '^## Version:' "$SCRIPT_DIR/BotButtons.toc" 2>/dev/null | sed 's/^## Version:[[:space:]]*//' || true)"
[ -n "$VERSION" ] || VERSION="dev"

printf 'flavor:    %s\n' "$FLAVOR"
printf 'interface: %s\n' "$INTERFACE"
printf 'target:    %s\n' "$DEST"

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'dry run: nothing written\n'
    exit 0
fi

# Never write through a development symlink; install real files.
if [ -L "$DEST" ]; then
    rm -f "$DEST"
fi

mkdir -p "$DEST"
cp "$SCRIPT_DIR/BotButtons.lua" "$DEST/BotButtons.lua"
cp "$SCRIPT_DIR/Bindings.xml" "$DEST/Bindings.xml"

cat > "$DEST/BotButtons.toc" <<EOF
## Interface: $INTERFACE
## Title: |cff33ff99Bot|r|cffffd100Buttons|r
## Notes: Draggable, keybindable quick-command buttons for cmangos playerbots
## Author: Roshkosh
## Version: $VERSION
## SavedVariables: BotButtonsDB
## DefaultState: Enabled

BotButtons.lua
EOF

printf 'installed: %s\n' "$DEST"
printf 'restart the client (or /reload after an initial install)\n'
