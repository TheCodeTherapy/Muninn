#!/usr/bin/env bash
#
# Odin Hot Reload Build Script with File Watching
# Cross-platform build script for hot reload development
#
# Usage:
#   ./build_hot_reload.sh            # Build once and exit
#   ./build_hot_reload.sh --watch    # Build and watch for file changes
#   ./build_hot_reload.sh --run      # Build and start the game
#   ./build_hot_reload.sh run        # Legacy compatibility
#

set -eu

# Configuration
OUT_DIR="build/hot_reload"
GAME_PDBS_DIR="$OUT_DIR/game_pdbs"
SOURCE_DIR="source"
DEBOUNCE_SECONDS=0.5  # Debounce time to prevent rapid rebuilds (500ms)
BUILD_TRIGGER_FILE="$OUT_DIR/build_trigger"

# Parse command line arguments
WATCH_MODE=false
RUN_MODE=false

# If no arguments provided, default to watch mode (like PowerShell version)
if [ $# -eq 0 ]; then
  WATCH_MODE=true
fi

for arg in "$@"; do
  case $arg in
    --watch|-w)
      WATCH_MODE=true
      shift
      ;;
    --run|-r)
      RUN_MODE=true
      shift
      ;;
    --build-only)
      WATCH_MODE=false
      shift
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--watch|--run|--build-only]"
      echo "  --watch      Build and watch for changes (default)"
      echo "  --run        Build and run once"
      echo "  --build-only Build only, don't watch or run"
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
      DLL_EXT=".dylib"
      EXE_EXT=""
      RAYLIB_PATH="$(odin root)/vendor/raylib/macos"
      EXTRA_LINKER_FLAGS="-Wl,-rpath $RAYLIB_PATH"
      ;;
    "Linux"|*)
      PLATFORM="linux"
      DLL_EXT=".so"
      EXE_EXT=".bin"
      RAYLIB_PATH="$(odin root)/vendor/raylib/linux"
      EXTRA_LINKER_FLAGS="'-Wl,-rpath=\$ORIGIN/linux'"
      ;;
  esac

  # Windows detection (for Git Bash, WSL, etc.)
  if [[ "$(uname -s)" == CYGWIN* ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
    PLATFORM="windows"
    DLL_EXT=".dll"
    EXE_EXT=".exe"
    RAYLIB_PATH="$(odin root)/vendor/raylib/windows"
    EXTRA_LINKER_FLAGS=""
  fi

  EXE="game_hot_reload$EXE_EXT"
}

# Check if game is running
is_game_running() {
  if [ "$PLATFORM" = "windows" ]; then
    # On Windows (Git Bash), use tasklist
    tasklist //FI "IMAGENAME eq $EXE" 2>/dev/null | grep -q "$EXE"
  else
    # On Unix-like systems, use pgrep
    pgrep -f "$EXE" >/dev/null 2>&1
  fi
}

# Initialize build directories
initialize_build_directories() {
  mkdir -p "$OUT_DIR"

  local game_running=false
  if is_game_running; then
    game_running=true
  else
    log_info "Game not running, cleaning build directory..."
    rm -rf "$OUT_DIR"/*
    mkdir -p "$GAME_PDBS_DIR"
    echo "0" > "$GAME_PDBS_DIR/pdb_number"
  fi

  echo "$game_running"
}

# Get next PDB number for debugging symbols
get_next_pdb_number() {
  local pdb_number_file="$GAME_PDBS_DIR/pdb_number"

  if [ -f "$pdb_number_file" ]; then
    local current_number=$(cat "$pdb_number_file")
  else
    local current_number=0
  fi

  local next_number=$((current_number + 1))
  echo "$next_number" > "$pdb_number_file"
  echo "$next_number"
}

# Build game DLL
build_game_dll() {
  local is_watch_mode=${1:-false}
  local pdb_number
  pdb_number=$(get_next_pdb_number)
  local pdb_path="$GAME_PDBS_DIR/game_$pdb_number.pdb"

  if [ "$is_watch_mode" = "true" ]; then
    log_info "🔄 Rebuilding game$DLL_EXT (PDB #$pdb_number)..."
  else
    log_info "Building game$DLL_EXT..."
  fi

  # Build arguments
  local build_args=(
    "build" "$SOURCE_DIR"
    "-strict-style" "-vet" "-debug"
    "-define:RAYLIB_SHARED=true"
    "-build-mode:dll"
    "-out:$OUT_DIR/game_tmp$DLL_EXT"
  )

  # Add PDB path on Windows
  if [ "$PLATFORM" = "windows" ]; then
    build_args+=("-pdb-name:$pdb_path")
  fi

  # Add extra linker flags on Unix
  if [ "$PLATFORM" != "windows" ] && [ -n "$EXTRA_LINKER_FLAGS" ]; then
    build_args+=("-extra-linker-flags:$EXTRA_LINKER_FLAGS")
  fi

  # Execute build
  if ! odin "${build_args[@]}" 2>&1; then
    log_error "❌ Build failed!"
    return 1
  fi

  # Atomic move to prevent loading incomplete DLL
  mv "$OUT_DIR/game_tmp$DLL_EXT" "$OUT_DIR/game$DLL_EXT"

  if [ "$is_watch_mode" = "true" ]; then
    log_success "✅ Hot reload complete!"
  else
    log_success "✅ Game DLL built successfully!"
  fi

  return 0
}

# Build game executable
build_game_exe() {
  log_info "Building $EXE..."

  local build_args=(
    "build" "source/main_hot_reload"
    "-strict-style" "-vet" "-debug"
    "-out:$EXE"
  )

  # Add PDB path on Windows
  if [ "$PLATFORM" = "windows" ]; then
    build_args+=("-pdb-name:$OUT_DIR/main_hot_reload.pdb")
  fi

  if ! odin "${build_args[@]}" 2>&1; then
    log_error "❌ Failed to build $EXE"
    return 1
  fi

  log_success "✅ $EXE built successfully!"
  return 0
}

# Copy platform-specific libraries
copy_platform_libraries() {
  case $PLATFORM in
    "linux")
      if [ ! -d "$OUT_DIR/linux" ]; then
        mkdir -p "$OUT_DIR/linux"
        if [ -d "$RAYLIB_PATH" ]; then
          cp -r "$RAYLIB_PATH"/libraylib*.so* "$OUT_DIR/linux/" 2>/dev/null || true
        fi
      fi
      ;;
    "windows")
      if [ ! -f "raylib.dll" ] && [ -f "$RAYLIB_PATH/raylib.dll" ]; then
        log_info "Copying raylib.dll from Odin installation..."
        cp "$RAYLIB_PATH/raylib.dll" .
      fi
      ;;
  esac
}

# File watching function
start_file_watcher() {
  log_info "🔍 Starting file watcher on '$SOURCE_DIR' directory..."
  log_warning "Press Ctrl+C to stop watching"

  local absolute_source_dir
  absolute_source_dir=$(realpath "$SOURCE_DIR")
  log_debug "👀 Watching: $absolute_source_dir"
  log_debug "📁 Filter: *.odin"

  # Create a checksum file to track changes
  local checksum_file="$OUT_DIR/.source_checksum"

  # Function to calculate checksum of all .odin files
  calculate_source_checksum() {
    find "$absolute_source_dir" -name "*.odin" -type f -exec cat {} \; 2>/dev/null |
      if command -v md5sum >/dev/null 2>&1; then
        md5sum
      elif command -v md5 >/dev/null 2>&1; then
        md5
      else
        # Fallback: use file modification times
        find "$absolute_source_dir" -name "*.odin" -type f -printf "%T@\n" 2>/dev/null | sort |
          if command -v shasum >/dev/null 2>&1; then
            shasum
          else
            cat | wc -c
          fi
      fi
  }

  # Store initial checksum
  calculate_source_checksum > "$checksum_file"

  log_success "✅ File watcher registered successfully"

  # Trap for cleanup
  trap 'cleanup_file_watcher' INT TERM EXIT

  # Main watch loop (polling-based for cross-platform compatibility)
  while true; do
    sleep 0.5

    # Check if game is still running
    if ! is_game_running; then
      log_warning "🎮 Game process has ended. Stopping file watcher..."
      break
    fi

    # Check for file changes
    local new_checksum
    new_checksum=$(calculate_source_checksum)
    local old_checksum=""
    if [ -f "$checksum_file" ]; then
      old_checksum=$(cat "$checksum_file")
    fi

    if [ "$new_checksum" != "$old_checksum" ]; then
      log_warning "📝 File changes detected in source directory"
      echo "$new_checksum" > "$checksum_file"
      handle_file_change "source"
    fi
  done
}

# Handle file change events
handle_file_change() {
  local file="$1"
  local relative_file
  relative_file=$(realpath --relative-to="." "$file" 2>/dev/null || echo "$file")

  log_warning "📝 File event detected: $relative_file (Changed)"
  log_info "⏰ Scheduling rebuild in 500ms..."

  # Create trigger file with timestamp
  echo "$(date +%s)" > "$BUILD_TRIGGER_FILE"

  # Debounced build check
  (
    sleep "$DEBOUNCE_SECONDS"
    if [ -f "$BUILD_TRIGGER_FILE" ]; then
      local trigger_time
      trigger_time=$(cat "$BUILD_TRIGGER_FILE")
      local current_time
      current_time=$(date +%s)

      # Only build if no newer trigger exists
      if [ "$trigger_time" -eq "$(cat "$BUILD_TRIGGER_FILE" 2>/dev/null || echo 0)" ]; then
        rm -f "$BUILD_TRIGGER_FILE"

        # Check if game is still running
        if ! is_game_running; then
          log_warning "🎮 Game process has ended. Stopping file watcher..."
          exit 0
        fi

        log_info "🔄 Debounce period elapsed, starting rebuild..."
        build_game_dll true
      fi
    fi
  ) &
}

# Cleanup function
cleanup_file_watcher() {
  log_info "🧹 Cleaning up file watcher..."

  # Kill any background processes
  jobs -p | xargs -r kill 2>/dev/null || true

  # Remove trigger and checksum files
  rm -f "$BUILD_TRIGGER_FILE"
  rm -f "$OUT_DIR/.source_checksum"

  log_success "✅ Cleanup complete"
}

# Main function
main() {
  log_info "🎮 Odin Hot Reload Build Script"
  log_info "================================"

  # Detect platform
  detect_platform
  log_debug "Platform detected: $PLATFORM"

  # Initialize build environment
  local game_running
  game_running=$(initialize_build_directories)

  # Build the game DLL
  if ! build_game_dll false; then
    exit 1
  fi

  # If game is already running, handle hot reload case
  if [ "$game_running" = "true" ]; then
    if [ "$WATCH_MODE" = "true" ]; then
      start_file_watcher
    else
      log_success "🔥 Hot reloading..."
    fi
    return 0
  fi

  # Build the executable
  if ! build_game_exe; then
    exit 1
  fi

  # Copy platform-specific libraries
  copy_platform_libraries

  # Handle run/watch modes
  if [ "$WATCH_MODE" = "true" ]; then
    # Always start the game if it's not running when in watch mode
    log_info "Starting $EXE..."
    "./$EXE" &
    sleep 2  # Give the game time to start
    start_file_watcher
  elif [ "$RUN_MODE" = "true" ]; then
    log_info "Starting $EXE..."
    "./$EXE" &
  fi

  log_success "🎉 Build complete!"
}

# Run main function
main "$@"
