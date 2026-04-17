#!/bin/bash
# MidwayBar Installer
# Usage: ./install.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

INSTALL_DIR="$HOME/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.neo.midwaybar.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  🔐 MidwayBar Installer"
echo "  ─────────────────────────"
echo ""

# 1. Check Swift
echo -n "  [1/5] Checking Swift... "
if command -v swift &>/dev/null; then
    echo -e "${GREEN}$(swift --version 2>&1 | head -1)${NC}"
else
    echo -e "${RED}Not found. Install Xcode Command Line Tools: xcode-select --install${NC}"
    exit 1
fi

# 2. Build
echo -n "  [2/5] Building... "
cd "$SCRIPT_DIR"
swift build -c release > /dev/null 2>&1
echo -e "${GREEN}done${NC}"

# 3. Install binary
echo -n "  [3/5] Installing to $INSTALL_DIR... "
mkdir -p "$INSTALL_DIR"
cp .build/release/MidwayBar "$INSTALL_DIR/midway-bar"
chmod +x "$INSTALL_DIR/midway-bar"
echo -e "${GREEN}done${NC}"

# 4. Install launchd plist
echo -n "  [4/5] Setting up background service... "
mkdir -p "$PLIST_DIR"
cat > "$PLIST_DIR/$PLIST_NAME" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.neo.midwaybar</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/midway-bar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST
echo -e "${GREEN}done${NC}"

# 5. Start
echo -n "  [5/5] Starting MidwayBar... "
launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$PLIST_DIR/$PLIST_NAME"
sleep 1
if ps aux | grep -v grep | grep midway-bar > /dev/null; then
    echo -e "${GREEN}running ✓${NC}"
else
    echo -e "${YELLOW}may need manual start${NC}"
fi

# Add ~/bin to PATH if needed
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    SHELL_RC="$HOME/.zshrc"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
    echo -e "  ${YELLOW}Added ~/bin to PATH in $SHELL_RC${NC}"
fi

echo ""
echo -e "  ${GREEN}✅ MidwayBar installed successfully!${NC}"
echo ""
echo "  Look for 'MW' with a percentage in your menu bar."
echo ""
echo "  Commands:"
echo "    mw-status          CLI session check"
echo "    ⌘R                 Refresh (in menu)"
echo "    ⌘M                 Run mwinit (in menu)"
echo "    ⌘L                 Toggle Launch at Login"
echo "    ⌘Q                 Quit"
echo ""
echo "  Uninstall:"
echo "    ./uninstall.sh"
echo ""
