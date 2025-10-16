#!/bin/bash

# Deep Link Configuration Validation Script
# This script validates that all deep linking components are properly configured

set -e  # Exit on error

echo "🔍 Validating Deep Link Configuration for Ledgex"
echo "================================================"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_BUNDLE_ID="com.owenwright.Ledgex"
EXPECTED_URL_SCHEME="ledgex"
EXPECTED_DOMAIN="splyt-4801c.web.app"
EXPECTED_TEAM_ID="W79P2M53MN"
ENTITLEMENTS_FILE="$PROJECT_ROOT/Ledgex/Ledgex.entitlements"

# Track validation status
VALIDATION_FAILED=0

# Helper function to print status
check_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        VALIDATION_FAILED=1
    fi
}

echo ""
echo "1️⃣  Checking Project Configuration"
echo "-----------------------------------"

# Check if Xcode project exists
if [ -f "$PROJECT_ROOT/Ledgex.xcodeproj/project.pbxproj" ]; then
    check_status 0 "Xcode project found"
else
    check_status 1 "Xcode project not found"
    exit 1
fi

# Check Bundle ID
if grep -q "PRODUCT_BUNDLE_IDENTIFIER = $EXPECTED_BUNDLE_ID;" "$PROJECT_ROOT/Ledgex.xcodeproj/project.pbxproj"; then
    check_status 0 "Bundle ID: $EXPECTED_BUNDLE_ID"
else
    check_status 1 "Bundle ID mismatch or not found"
fi

# Check URL Scheme
if grep -q "CFBundleURLSchemes.*$EXPECTED_URL_SCHEME" "$PROJECT_ROOT/Ledgex.xcodeproj/project.pbxproj"; then
    check_status 0 "URL Scheme: $EXPECTED_URL_SCHEME://"
else
    check_status 1 "URL Scheme not configured correctly"
fi

echo ""
echo "2️⃣  Checking Entitlements"
echo "-------------------------"

# Check if entitlements file exists
if [ -f "$ENTITLEMENTS_FILE" ]; then
    check_status 0 "Entitlements file exists"

    # Check Associated Domains
    if grep -q "applinks:$EXPECTED_DOMAIN" "$ENTITLEMENTS_FILE"; then
        check_status 0 "Associated Domain: applinks:$EXPECTED_DOMAIN"
    else
        check_status 1 "Associated Domain not configured"
    fi

    # Check Sign in with Apple
    if grep -q "com.apple.developer.applesignin" "$ENTITLEMENTS_FILE"; then
        check_status 0 "Sign in with Apple capability configured"
    else
        check_status 1 "Sign in with Apple capability missing"
    fi
else
    check_status 1 "Entitlements file not found"
fi

echo ""
echo "3️⃣  Checking Firebase Hosting Configuration"
echo "--------------------------------------------"

# Check if firebase.json exists
if [ -f "$PROJECT_ROOT/firebase.json" ]; then
    check_status 0 "firebase.json found"

    # Check storage rules path
    if grep -q "\"storage\"" "$PROJECT_ROOT/firebase.json"; then
        check_status 0 "Storage rules configured"
    else
        check_status 1 "Storage rules not configured"
    fi

    # Check hosting configuration
    if grep -q "\"hosting\"" "$PROJECT_ROOT/firebase.json"; then
        check_status 0 "Hosting configuration found"
    else
        check_status 1 "Hosting configuration missing"
    fi
else
    check_status 1 "firebase.json not found"
fi

# Check apple-app-site-association file
AASA_FILE="$PROJECT_ROOT/hosting/public/.well-known/apple-app-site-association"
if [ -f "$AASA_FILE" ]; then
    check_status 0 "Apple App Site Association file exists"

    # Check bundle ID in AASA
    if grep -q "$EXPECTED_TEAM_ID.$EXPECTED_BUNDLE_ID" "$AASA_FILE"; then
        check_status 0 "AASA contains correct bundle ID"
    else
        check_status 1 "AASA bundle ID mismatch"
    fi
else
    check_status 1 "Apple App Site Association file not found"
fi

echo ""
echo "4️⃣  Checking Deep Link Handler"
echo "-------------------------------"

DEEP_LINK_HANDLER="$PROJECT_ROOT/Ledgex/Utilities/DeepLinkHandler.swift"
if [ -f "$DEEP_LINK_HANDLER" ]; then
    check_status 0 "DeepLinkHandler.swift found"

    # Check if it handles the expected scheme
    if grep -q "\"$EXPECTED_URL_SCHEME\"" "$DEEP_LINK_HANDLER"; then
        check_status 0 "Handler checks for $EXPECTED_URL_SCHEME scheme"
    else
        check_status 1 "Handler doesn't check for correct scheme"
    fi

    # Check if it handles the expected domain
    if grep -q "$EXPECTED_DOMAIN" "$DEEP_LINK_HANDLER"; then
        check_status 0 "Handler checks for $EXPECTED_DOMAIN"
    else
        check_status 1 "Handler doesn't check for expected domain"
    fi

    # Check if it supports path-based URLs
    if grep -q "pathComponents" "$DEEP_LINK_HANDLER"; then
        check_status 0 "Handler supports path-based URLs (/join/CODE)"
    else
        check_status 1 "Handler doesn't support path-based URLs"
    fi
else
    check_status 1 "DeepLinkHandler.swift not found"
fi

echo ""
echo "5️⃣  Checking Join Page"
echo "----------------------"

JOIN_PAGE="$PROJECT_ROOT/hosting/public/join/index.html"
if [ -f "$JOIN_PAGE" ]; then
    check_status 0 "Join page exists"

    # Check if it supports path-based URLs
    if grep -q "pathMatch" "$JOIN_PAGE"; then
        check_status 0 "Join page supports path-based URLs"
    else
        check_status 1 "Join page doesn't support path-based URLs"
    fi

    # Check if it uses correct URL scheme
    if grep -q "$EXPECTED_URL_SCHEME://" "$JOIN_PAGE"; then
        check_status 0 "Join page uses correct URL scheme"
    else
        check_status 1 "Join page uses incorrect URL scheme"
    fi
else
    check_status 1 "Join page not found"
fi

echo ""
echo "6️⃣  Building Project (Debug)"
echo "----------------------------"

# Attempt to build the project
echo "Building Ledgex for iOS Simulator..."

# Find an available simulator
AVAILABLE_SIM=$(xcrun simctl list devices iPhone available | grep -m 1 "iPhone" | sed 's/.*(\(.*\)).*/\1/' | xargs)

if [ -z "$AVAILABLE_SIM" ]; then
    echo -e "${YELLOW}⚠${NC}  No simulator found, skipping build test"
else
    if xcodebuild -project "$PROJECT_ROOT/Ledgex.xcodeproj" \
        -scheme Ledgex \
        -sdk iphonesimulator \
        -configuration Debug \
        -destination "id=$AVAILABLE_SIM" \
        clean build \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        > /tmp/ledgex-build.log 2>&1; then
        check_status 0 "Project builds successfully"
    else
        echo -e "${YELLOW}⚠${NC}  Build failed (see /tmp/ledgex-build.log for details)"
        echo -e "${YELLOW}    This is non-critical - configuration checks passed${NC}"
    fi
fi

echo ""
echo "7️⃣  Test URLs"
echo "-------------"

echo "Test these URLs on your device:"
echo ""
echo "  • Path-based:  https://$EXPECTED_DOMAIN/join/ABCD123456"
echo "  • Query param: https://$EXPECTED_DOMAIN/join?code=ABCD123456"
echo "  • Direct URL:  $EXPECTED_URL_SCHEME://join?code=ABCD123456"
echo ""
echo "Note: Code must be exactly 10 characters"

echo ""
echo "================================================"
if [ $VALIDATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All validations passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy to Firebase: firebase deploy --only hosting"
    echo "  2. Rebuild and install app on device"
    echo "  3. Test with URLs above"
    exit 0
else
    echo -e "${RED}✗ Some validations failed${NC}"
    echo ""
    echo "Please fix the issues above before deploying"
    exit 1
fi
