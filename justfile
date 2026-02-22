# Hugora build tasks

# Default: build debug
default: build

# Build debug
build:
    swift build

# Build release
build-release:
    swift build -c release

# Run the app (debug)
run:
    swift run Hugora

# Run tests
test:
    swift test --build-path .build-tests

# Build release app bundle with CLI included
bundle: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    
    APP_NAME="Hugora"
    BUILD_DIR=".build/release"
    BUNDLE_DIR="${BUILD_DIR}/${APP_NAME}.app"
    ASSETS_DIR="Sources/Hugora/Resources/Assets.xcassets"
    
    echo "Creating app bundle..."
    
    # Create bundle structure
    mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
    mkdir -p "${BUNDLE_DIR}/Contents/Resources"
    
    # Copy main executable
    cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_DIR}/Contents/MacOS/"
    
    # Copy CLI tool
    cp "${BUILD_DIR}/hugora-cli" "${BUNDLE_DIR}/Contents/MacOS/hugora-cli"
    
    # Copy Info.plist
    cp Info.plist "${BUNDLE_DIR}/Contents/"
    
    # Copy Sparkle.framework and fix rpath
    mkdir -p "${BUNDLE_DIR}/Contents/Frameworks"
    cp -R "${BUILD_DIR}/Sparkle.framework" "${BUNDLE_DIR}/Contents/Frameworks/"
    install_name_tool -add_rpath @executable_path/../Frameworks "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"
    echo "Sparkle.framework copied"
    
    # Generate and copy app icon
    if [[ -d "${ASSETS_DIR}/AppIcon.appiconset" ]]; then
        ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
        rm -rf "${ICONSET_DIR}"
        mkdir -p "${ICONSET_DIR}"
        cp "${ASSETS_DIR}/AppIcon.appiconset/"*.png "${ICONSET_DIR}/"
        iconutil -c icns -o "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns" "${ICONSET_DIR}"
        rm -rf "${ICONSET_DIR}"
        echo "App icon created"
    fi
    
    # Copy resources if they exist
    if [[ -d "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle" ]]; then
        cp -R "${BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle/"* "${BUNDLE_DIR}/Contents/Resources/" 2>/dev/null || true
    fi
    
    echo "Bundle created: ${BUNDLE_DIR}"

# Clean build artifacts
clean:
    swift package clean
    rm -rf .build

# Ensure required dev tools are installed
ensure-swift-format:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v swift-format >/dev/null 2>&1; then
        echo "error: swift-format is required (install with: brew install swift-format)" >&2
        exit 127
    fi

# Format Swift code
fmt: ensure-swift-format
    swift-format format -i -r Sources/ Tests/

# Lint
lint: ensure-swift-format
    swift-format lint -r Sources/ Tests/
