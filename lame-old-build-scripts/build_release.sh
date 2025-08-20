#!/usr/bin/env bash
#
# Odin Release Build Script
# Cross-platform release build script for optimized distributable builds
#
# Usage:
#   ./build_release.sh            # Build release version (default)
#   ./build_release.sh --run      # Build and start the release version
#   ./build_release.sh --build-only # Build only and exit
#

set -eu

# Configuration
OUT_DIR="build/release"
SOURCE_DIR="source/main_release"
ASSETS_DIR="assets"

# Parse command line arguments
RUN_MODE=false
BUILD_ONLY=false

# If no arguments provided, default to build only mode (like PowerShell version)
if [ $# -eq 0 ]; then
  BUILD_ONLY=true
fi

for arg in "$@"; do
  case $arg in
    --run|-r)
      RUN_MODE=true
      shift
      ;;
    --build-only)
      BUILD_ONLY=true
      shift
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--run|--build-only]"
      echo "  --run        Build and run release version"
      echo "  --build-only Build only and exit (default)"
      exit 1
      ;;
  esac
done

# Colors for output (with fallback for terminals without color support)
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  CYAN=$(tput setaf 6)
  GRAY=$(tput setaf 8)
  RESET=$(tput sgr0)
else
  RED="" GREEN="" YELLOW="" BLUE="" CYAN="" GRAY="" RESET=""
fi

# Logging functions
log_info() {
  echo "${CYAN}$*${RESET}"
}

log_success() {
  echo "${GREEN}$*${RESET}"
}

log_warning() {
  echo "${YELLOW}$*${RESET}"
}

log_error() {
  echo "${RED}$*${RESET}"
}

log_debug() {
  echo "${GRAY}$*${RESET}"
}

# Platform detection
detect_platform() {
  case $(uname) in
    "Darwin")
      PLATFORM="macos"
      EXE_EXT=""
      RAYLIB_PATH="$(odin root)/vendor/raylib/macos"
      RAYLIB_LIB="libraylib.dylib"
      SUBSYSTEM_FLAG=""
      ;;
    "Linux"|*)
      PLATFORM="linux"
      EXE_EXT=".bin"
      RAYLIB_PATH="$(odin root)/vendor/raylib/linux"
      RAYLIB_LIB="libraylib.so"
      SUBSYSTEM_FLAG=""
      ;;
  esac

  # Windows detection (for Git Bash, WSL, etc.)
  if [[ "$(uname -s)" == CYGWIN* ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
    PLATFORM="windows"
    EXE_EXT=".exe"
    RAYLIB_PATH="$(odin root)/vendor/raylib/windows"
    RAYLIB_LIB="raylib.dll"
    SUBSYSTEM_FLAG="-subsystem:windows"
  fi

  EXE="game_release$EXE_EXT"
}

# Initialize build directories
initialize_build_directories() {
  mkdir -p "$OUT_DIR"

  # Clean the output directory for fresh release build
  log_info "Cleaning release build directory..."
  rm -rf "$OUT_DIR"/*
}

# Build release executable
build_release_game() {
  log_info "Building optimized release executable..."

  # Build arguments
  local build_args=(
    "build" "$SOURCE_DIR"
    "-strict-style" "-vet"
    "-no-bounds-check" "-o:speed"
    "-out:$OUT_DIR/$EXE"
  )

  # Add subsystem flag on Windows
  if [ "$PLATFORM" = "windows" ] && [ -n "$SUBSYSTEM_FLAG" ]; then
    build_args+=("$SUBSYSTEM_FLAG")
  fi

  # Execute build
  if ! odin "${build_args[@]}" 2>&1; then
    log_error "❌ Build failed!"
    return 1
  fi

  log_success "✅ Release executable built successfully!"
  return 0
}

# Copy assets to build directory
copy_assets() {
  if [ -d "$ASSETS_DIR" ]; then
    log_info "Copying assets..."
    cp -R "$ASSETS_DIR" "$OUT_DIR/"
    log_success "✅ Assets copied successfully!"
  else
    log_warning "⚠️  Assets directory not found, skipping..."
  fi
}

# Copy platform-specific libraries
copy_platform_libraries() {
  if [ ! -f "$OUT_DIR/$RAYLIB_LIB" ]; then
    if [ -f "$RAYLIB_PATH/$RAYLIB_LIB" ]; then
      cp "$RAYLIB_PATH/$RAYLIB_LIB" "$OUT_DIR/"
      log_success "✅ $RAYLIB_LIB copied to build directory"
    else
      log_warning "⚠️  $RAYLIB_LIB not found in Odin installation"
    fi
  fi
}

# Main function
main() {
  log_info "🚀 Odin Release Build Script"
  log_info "============================"

  # Detect platform
  detect_platform
  log_debug "Platform detected: $PLATFORM"

  # Initialize build environment
  initialize_build_directories

  # Build the release executable
  if ! build_release_game; then
    exit 1
  fi

  # Copy assets
  copy_assets

  # Copy platform-specific libraries
  copy_platform_libraries

  # Handle run mode
  if [ "$RUN_MODE" = "true" ]; then
    log_info "Starting release game..."
    cd "$OUT_DIR"
    "./$EXE" &
    cd - > /dev/null
    log_success "🎮 Release game started!"
  fi

  log_success "🎉 Release build complete!"
  log_info "Release build created in $OUT_DIR"
}

# Run main function
main "$@"