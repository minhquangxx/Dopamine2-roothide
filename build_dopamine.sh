#!/bin/bash

#####################################################################
# Dopamine2-roothide Build Script
# 
# Script này sẽ build Dopamine2-roothide thành file .tipa
# Yêu cầu:
#   - macOS (đã test trên macOS 14+)
#   - Xcode với iOS SDK
#   - Homebrew
#   - Internet để tải dependencies
#
# Cách sử dụng:
#   chmod +x build_dopamine.sh
#   ./build_dopamine.sh          # Build thường
#   ./build_dopamine.sh clean    # Clean rồi build
#   ./build_dopamine.sh force    # Force rebuild
#####################################################################

# Parse arguments
CLEAN_BUILD=false
FORCE_BUILD=false
for arg in "$@"; do
    case $arg in
        clean) CLEAN_BUILD=true ;;
        force) FORCE_BUILD=true ;;
    esac
done

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Get script directory (where Dopamine2-roothide is located)
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
THEOS="${BASEDIR}/theos"

print_step "Dopamine2-roothide Build Script"
echo "=================================="
echo "Base Directory: ${BASEDIR}"
echo ""

#####################################################################
# Step 1: Check Prerequisites
#####################################################################
print_step "Checking prerequisites..."

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    print_error "Xcode is not installed. Please install Xcode from the App Store."
    exit 1
fi
print_success "Xcode found: $(xcodebuild -version | head -1)"

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    print_error "Homebrew is not installed. Please install from https://brew.sh"
    exit 1
fi
print_success "Homebrew found"

# Check for git
if ! command -v git &> /dev/null; then
    print_error "Git is not installed"
    exit 1
fi
print_success "Git found"

#####################################################################
# Step 2: Install Procursus tools via Homebrew (alternatives)
#####################################################################
print_step "Installing required tools via Homebrew..."

# Install required packages
BREW_PACKAGES="ldid make coreutils gnu-sed findutils openssl libarchive"
for pkg in $BREW_PACKAGES; do
    if ! brew list $pkg &> /dev/null; then
        print_warning "Installing $pkg..."
        brew install $pkg
    else
        print_success "$pkg already installed"
    fi
done

# Add GNU tools to PATH
export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/findutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

# For Intel Macs
export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/findutils/libexec/gnubin:$PATH"
export PATH="/usr/local/opt/make/libexec/gnubin:$PATH"

#####################################################################
# Step 3: Install THEOS if not exists
#####################################################################
print_step "Checking THEOS installation..."

if [ ! -d "$THEOS" ]; then
    print_warning "THEOS not found. Installing..."
    mkdir -p "$THEOS"
    
    # Download and run install script
    curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos -o install-theos.sh
    
    # Modify script to create sdk placeholder
    if command -v gsed &> /dev/null; then
        gsed -E "/^\s*get_theos\s*$/,+1 s/^(\s*)(get_sdks)\s*$/\1mkdir -p \${THEOS}\/sdks\n\1touch \${THEOS}\/sdks\/sdk\n\1\2/g" -i install-theos.sh
    else
        sed -E "/^\s*get_theos\s*$/,+1 s/^(\s*)(get_sdks)\s*$/\1mkdir -p \${THEOS}\/sdks\n\1touch \${THEOS}\/sdks\/sdk\n\1\2/g" -i '' install-theos.sh
    fi
    
    export THEOS
    bash install-theos.sh
    rm install-theos.sh
    
    print_success "THEOS installed"
else
    print_success "THEOS already installed"
fi

export THEOS

#####################################################################
# Step 4: Download iOS SDK if not exists
#####################################################################
print_step "Checking iOS SDK..."

SDK_PATH="${THEOS}/sdks/iPhoneOS16.5.sdk"
if [ ! -d "$SDK_PATH" ]; then
    print_warning "iOS 16.5 SDK not found. Downloading..."
    mkdir -p "${THEOS}/sdks"
    
    curl -L "https://github.com/theos/sdks/releases/latest/download/iPhoneOS16.5.sdk.tar.xz" \
        --output "${THEOS}/sdks/iPhoneOS16.5.sdk.tar.xz"
    
    # Extract (xz format)
    cd "${THEOS}/sdks"
    if command -v xz &> /dev/null; then
        xz -d iPhoneOS16.5.sdk.tar.xz
    else
        # Use gunzip as fallback (may not work with xz)
        gunzip iPhoneOS16.5.sdk.tar.xz 2>/dev/null || brew install xz && xz -d iPhoneOS16.5.sdk.tar.xz
    fi
    tar -xf iPhoneOS16.5.sdk.tar
    rm -f iPhoneOS16.5.sdk.tar
    cd "$BASEDIR"
    
    print_success "iOS 16.5 SDK downloaded"
else
    print_success "iOS 16.5 SDK found"
fi

#####################################################################
# Step 5: Build and install trustcache
#####################################################################
print_step "Building trustcache..."

TRUSTCACHE_PATH="/usr/local/bin/trustcache"
if [ -f "/opt/homebrew/bin/trustcache" ]; then
    TRUSTCACHE_PATH="/opt/homebrew/bin/trustcache"
fi

if ! command -v trustcache &> /dev/null && [ ! -f "$TRUSTCACHE_PATH" ]; then
    print_warning "trustcache not found. Building..."
    
    TRUSTCACHE_BUILD_DIR="${BASEDIR}/trustcache_build"
    rm -rf "$TRUSTCACHE_BUILD_DIR"
    
    git clone https://github.com/CRKatri/trustcache "$TRUSTCACHE_BUILD_DIR"
    cd "$TRUSTCACHE_BUILD_DIR"
    
    # Set compiler flags for OpenSSL
    OPENSSL_PREFIX=$(brew --prefix openssl)
    export CFLAGS="-I${OPENSSL_PREFIX}/include -arch arm64"
    export LDFLAGS="-L${OPENSSL_PREFIX}/lib -arch arm64"
    
    # Build
    gmake -j$(sysctl -n hw.physicalcpu) OPENSSL=1 || make -j$(sysctl -n hw.physicalcpu) OPENSSL=1
    
    # Install
    if [ -w "/usr/local/bin" ]; then
        cp trustcache /usr/local/bin/
    elif [ -w "/opt/homebrew/bin" ]; then
        cp trustcache /opt/homebrew/bin/
    else
        sudo cp trustcache /usr/local/bin/
    fi
    
    cd "$BASEDIR"
    rm -rf "$TRUSTCACHE_BUILD_DIR"
    
    print_success "trustcache built and installed"
else
    print_success "trustcache already installed"
fi

#####################################################################
# Step 6: Update submodules
#####################################################################
print_step "Updating git submodules..."

cd "$BASEDIR"
git submodule update --init --recursive || print_warning "Some submodules may have failed"
print_success "Submodules updated"

#####################################################################
# Step 7: Remove conflicting XPC headers from SDK (if needed)
#####################################################################
print_step "Checking SDK XPC headers..."

SDK_XPC_PATH="$(xcrun --sdk iphoneos --show-sdk-path)/usr/include/xpc"
SDK_XPC_MODULEMAP="$(xcrun --sdk iphoneos --show-sdk-path)/usr/include/xpc.modulemap"

if [ -d "$SDK_XPC_PATH" ] || [ -f "$SDK_XPC_MODULEMAP" ]; then
    print_warning "Found conflicting XPC headers in SDK. You may need to remove them."
    print_warning "Run with sudo if needed:"
    echo "  sudo rm -rf \"$SDK_XPC_PATH\""
    echo "  sudo rm -f \"$SDK_XPC_MODULEMAP\""
    
    read -p "Do you want to remove them now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo rm -rf "$SDK_XPC_PATH" 2>/dev/null || true
        sudo rm -f "$SDK_XPC_MODULEMAP" 2>/dev/null || true
        print_success "XPC headers removed"
    fi
fi

#####################################################################
# Step 8: Build Dopamine
#####################################################################
print_step "Building Dopamine2-roothide..."

cd "$BASEDIR"

# Get version
VERSION=$(cat ./BaseBin/_external/basebin/.version 2>/dev/null || echo "unknown")
SHORT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
FINAL_NAME="roothide-Dopamine-${VERSION}-${SHORT_HASH}.tipa"

# Check if already built
if [ -f "./Application/Dopamine.tipa" ] && [ "$FORCE_BUILD" = false ] && [ "$CLEAN_BUILD" = false ]; then
    print_success "Dopamine.tipa already exists!"
    echo ""
    echo "Use './build_dopamine.sh clean' to rebuild from scratch"
    echo "Or './build_dopamine.sh force' to force rebuild"
    echo ""
    echo "Existing files:"
    ls -lh ./Application/*.tipa 2>/dev/null || true
    exit 0
fi

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    print_warning "Cleaning previous build..."
    make clean 2>/dev/null || true
fi

echo "Building version: ${VERSION}-${SHORT_HASH}"

# Run the main build
# Use gmake if available (GNU make)
set +e  # Don't exit on make errors (warnings are ok)
if command -v gmake &> /dev/null; then
    gmake -j$(sysctl -n hw.physicalcpu) 2>&1 | tee build.log
    BUILD_RESULT=${PIPESTATUS[0]}
else
    make -j$(sysctl -n hw.physicalcpu) 2>&1 | tee build.log
    BUILD_RESULT=${PIPESTATUS[0]}
fi
set -e

#####################################################################
# Step 9: Rename and show result
#####################################################################
print_step "Finalizing..."

FINAL_NAME="roothide-Dopamine-${VERSION}-${SHORT_HASH}.tipa"
if [ -f "./Application/Dopamine.tipa" ]; then
    cp "./Application/Dopamine.tipa" "./Application/${FINAL_NAME}"
    
    echo ""
    echo "========================================"
    print_success "BUILD SUCCESSFUL!"
    echo "========================================"
    echo ""
    echo "Output files:"
    echo "  📦 ./Application/Dopamine.tipa"
    echo "  📦 ./Application/${FINAL_NAME}"
    echo ""
    echo "File size: $(ls -lh ./Application/Dopamine.tipa | awk '{print $5}')"
    echo ""
    echo "Install via TrollStore or use Sideloadly/AltStore"
    echo ""
else
    print_error "Build failed! Dopamine.tipa not found"
    exit 1
fi
