#!/bin/bash
# MidwayBar Uninstaller
set -e

echo ""
echo "  🔐 MidwayBar Uninstaller"
echo "  ─────────────────────────"
echo ""

echo -n "  Stopping MidwayBar... "
launchctl unload ~/Library/LaunchAgents/com.neo.midwaybar.plist 2>/dev/null || true
pkill -f midway-bar 2>/dev/null || true
echo "done"

echo -n "  Removing binary... "
rm -f ~/bin/midway-bar
echo "done"

echo -n "  Removing launchd config... "
rm -f ~/Library/LaunchAgents/com.neo.midwaybar.plist
echo "done"

echo ""
echo "  ✅ MidwayBar uninstalled."
echo ""
