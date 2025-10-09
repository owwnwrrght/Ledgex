#!/bin/sh

# Xcode Cloud post-clone script
# This script runs after the repository is cloned in Xcode Cloud

echo "🚀 Starting Xcode Cloud post-clone setup..."

# Print environment info
echo "📍 Working directory: $(pwd)"
echo "🔧 Xcode version: $(xcodebuild -version)"

# Check if CocoaPods is available
if ! command -v pod &> /dev/null; then
    echo "⚠️ CocoaPods not found in PATH"
    echo "📦 Attempting to install CocoaPods..."

    # Try to install without sudo (Xcode Cloud doesn't have sudo access)
    if gem install cocoapods --user-install 2>/dev/null; then
        echo "✅ CocoaPods installed successfully"
        # Add user gems to PATH
        export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"
    else
        echo "❌ Failed to install CocoaPods, but continuing..."
        echo "ℹ️  CocoaPods should be pre-installed in Xcode Cloud"
    fi
else
    echo "✅ CocoaPods already installed: $(pod --version)"
fi

# Install pod dependencies
echo "📦 Installing CocoaPods dependencies..."
if pod install; then
    echo "✅ Pod install successful"
else
    echo "❌ Pod install failed with exit code $?"
    exit 1
fi

# Handle GoogleService-Info.plist for CI
# Since this file is gitignored, we need to provide it for the build
PLIST_PATH="Ledgex/GoogleService-Info.plist"

if [ ! -f "$PLIST_PATH" ]; then
    echo "⚠️  GoogleService-Info.plist not found"
    echo "📝 Creating placeholder GoogleService-Info.plist for CI build..."

    # Create a minimal GoogleService-Info.plist for building
    # Note: This won't allow actual Firebase functionality in CI builds,
    # but it will allow the project to compile
    cat > "$PLIST_PATH" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>AIzaSyBJaYf5L5grmh0yUuu4zk-CwySpSEWhtNo</string>
	<key>GCM_SENDER_ID</key>
	<string>989033651157</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.OwenWright.Ledgex-ios</string>
	<key>PROJECT_ID</key>
	<string>splyt-4801c</string>
	<key>STORAGE_BUCKET</key>
	<string>splyt-4801c.firebasestorage.app</string>
	<key>IS_ADS_ENABLED</key>
	<false></false>
	<key>IS_ANALYTICS_ENABLED</key>
	<false></false>
	<key>IS_APPINVITE_ENABLED</key>
	<true></true>
	<key>IS_GCM_ENABLED</key>
	<true></true>
	<key>IS_SIGNIN_ENABLED</key>
	<true></true>
	<key>GOOGLE_APP_ID</key>
	<string>1:989033651157:ios:d3030c34ef5a2ea2137b5c</string>
</dict>
</plist>
EOF

    echo "✅ Created GoogleService-Info.plist"
else
    echo "✅ GoogleService-Info.plist already exists"
fi

echo "✅ Xcode Cloud post-clone setup complete!"
