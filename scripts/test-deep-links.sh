#!/bin/bash

# Deep Link Testing Script
# Tests URL schemes and universal links on simulator or device

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BUNDLE_ID="com.owenwright.Ledgex"
URL_SCHEME="ledgex"
TEST_CODE="ABCD123456"

echo "🧪 Deep Link Testing Tool"
echo "=========================="
echo ""

# Function to list available simulators
list_simulators() {
    echo "Available iOS Simulators:"
    xcrun simctl list devices iPhone available | grep "iPhone" | nl
}

# Function to get booted simulator
get_booted_simulator() {
    xcrun simctl list devices | grep "Booted" | grep -o "[A-F0-9\-]\{36\}" | head -n 1
}

# Check if app is installed
check_app_installed() {
    local device_id=$1
    if xcrun simctl get_app_container "$device_id" "$BUNDLE_ID" &>/dev/null; then
        echo -e "${GREEN}✓${NC} App is installed on simulator"
        return 0
    else
        echo -e "${RED}✗${NC} App is not installed on simulator"
        return 1
    fi
}

# Main menu
echo "Select test type:"
echo "1) Test URL Scheme (ledgex://join?code=...)"
echo "2) Test Universal Link (https://splyt-4801c.web.app/join/...)"
echo "3) Test Universal Link with query param (https://splyt-4801c.web.app/join?code=...)"
echo "4) List app info on simulator"
echo "5) View Xcode console logs"
echo ""
read -p "Choose option (1-5): " option

# Get booted simulator
DEVICE_ID=$(get_booted_simulator)

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}No booted simulator found.${NC}"
    echo "Please boot a simulator first and run the app."
    exit 1
fi

echo -e "${BLUE}Using simulator: $DEVICE_ID${NC}"
echo ""

case $option in
    1)
        echo "Testing URL Scheme..."
        URL="${URL_SCHEME}://join?code=${TEST_CODE}"
        echo "Opening: $URL"
        if xcrun simctl openurl "$DEVICE_ID" "$URL"; then
            echo -e "${GREEN}✓${NC} URL opened successfully"
            echo ""
            echo "Check the Xcode console for logs starting with 📱 🔗 or 🎯"
        else
            echo -e "${RED}✗${NC} Failed to open URL"
        fi
        ;;
    2)
        echo "Testing Universal Link (path-based)..."
        URL="https://splyt-4801c.web.app/join/${TEST_CODE}"
        echo "Opening: $URL"
        if xcrun simctl openurl "$DEVICE_ID" "$URL"; then
            echo -e "${GREEN}✓${NC} URL opened successfully"
            echo ""
            echo "Check the Xcode console for logs starting with 📱 🔗 or 🎯"
        else
            echo -e "${RED}✗${NC} Failed to open URL"
        fi
        ;;
    3)
        echo "Testing Universal Link (query param)..."
        URL="https://splyt-4801c.web.app/join?code=${TEST_CODE}"
        echo "Opening: $URL"
        if xcrun simctl openurl "$DEVICE_ID" "$URL"; then
            echo -e "${GREEN}✓${NC} URL opened successfully"
            echo ""
            echo "Check the Xcode console for logs starting with 📱 🔗 or 🎯"
        else
            echo -e "${RED}✗${NC} Failed to open URL"
        fi
        ;;
    4)
        echo "App Info:"
        echo "--------"
        if check_app_installed "$DEVICE_ID"; then
            echo ""
            echo "Bundle ID: $BUNDLE_ID"
            echo "App Container:"
            xcrun simctl get_app_container "$DEVICE_ID" "$BUNDLE_ID" data 2>/dev/null || echo "  (not available)"
            echo ""
            echo "To check URL scheme registration, look for these logs when launching the app:"
            echo "  📋 Registered URL Schemes:"
            echo "     - ledgex"
        fi
        ;;
    5)
        echo "To view Xcode console logs:"
        echo ""
        echo "1. In Xcode, open: Window > Devices and Simulators"
        echo "2. Select your simulator"
        echo "3. Click 'Open Console'"
        echo ""
        echo "OR run this command:"
        echo "  xcrun simctl spawn booted log stream --level debug --predicate 'process == \"Ledgex\"'"
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Troubleshooting Tips:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "If the URL doesn't work:"
echo ""
echo "1. Make sure the app is running in the simulator"
echo "2. Check Xcode console for these logs:"
echo "   • '📋 Registered URL Schemes:' - confirms URL scheme is registered"
echo "   • '🌐 LedgexApp: onOpenURL' - confirms URL was received"
echo "   • '📱 ContentView: Received URL' - confirms ContentView got the URL"
echo "   • '🔗 DeepLinkHandler: Parsing' - confirms parser is processing"
echo "   • '✅ Successfully parsed' - confirms parsing succeeded"
echo "   • '🎯 Joining trip' - confirms action is being taken"
echo ""
echo "3. If no logs appear:"
echo "   • Rebuild and reinstall the app"
echo "   • Clean build folder (Cmd+Shift+K)"
echo "   • Reset simulator content and settings"
echo ""
echo "4. For universal links on real device:"
echo "   • Delete the app completely"
echo "   • Wait 15 minutes for Apple's CDN"
echo "   • Reinstall and test"
echo ""
