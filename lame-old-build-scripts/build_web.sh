#!/usr/bin/env bash
#
# Odin Web Build Script with Automatic EMSDK Management
# Cross-platform web build script with automatic EMSDK installation and management
#
# Usage:
#   ./build_web.sh            # Build web version (default)
#   ./build_web.sh --run      # Build and start local web server
#   ./build_web.sh --build-only # Build only and exit
#   ./build_web.sh --force-update # Force EMSDK update and build
#

set -eu

# Configuration
OUT_DIR="build/web"
SOURCE_DIR="source/main_web"
ASSETS_DIR="assets"
EMSDK_DIR="$HOME/.emsdk"
EMSDK_REPO="https://github.com/emscripten-core/emsdk.git"

# Parse command line arguments
RUN_MODE=false
BUILD_ONLY=false
FORCE_UPDATE=false

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
    --force-update|-f)
      FORCE_UPDATE=true
      shift
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--run|--build-only|--force-update]"
      echo "  --run         Build and start local web server"
      echo "  --build-only  Build only and exit (default)"
      echo "  --force-update Force EMSDK update and build"
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

# Convert Windows paths to Unix paths in Git Bash
convert_path() {
  local path="$1"
  if [ "$PLATFORM" = "windows" ] || [[ "$(uname -s)" == CYGWIN* ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
    # Convert C:\path\to\file to /c/path/to/file
    echo "$path" | sed 's|\\|/|g' | sed 's|^\([A-Za-z]\):|/\L\1|'
  else
    echo "$path"
  fi
}

# Platform detection
detect_platform() {
  case $(uname) in
    "Darwin")
      PLATFORM="macos"
      EXE_EXT=""
      RAYLIB_LIB="libraylib.dylib"
      SUBSYSTEM_FLAG=""
      ;;
    "Linux"|*)
      PLATFORM="linux"
      EXE_EXT=".bin"
      RAYLIB_LIB="libraylib.so"
      SUBSYSTEM_FLAG=""
      ;;
  esac

  # Windows detection (for Git Bash, WSL, etc.)
  if [[ "$(uname -s)" == CYGWIN* ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
    PLATFORM="windows"
    EXE_EXT=".exe"
    RAYLIB_LIB="raylib.dll"
    SUBSYSTEM_FLAG="-subsystem:windows"
  fi

  EXE="game_release$EXE_EXT"

  # Set RAYLIB_PATH after we know the platform
  if command -v odin >/dev/null 2>&1; then
    local odin_root_raw
    if odin_root_raw=$(odin root 2>/dev/null); then
      local odin_root_converted
      odin_root_converted=$(convert_path "$odin_root_raw")
      case $PLATFORM in
        "macos") RAYLIB_PATH="$odin_root_converted/vendor/raylib/macos" ;;
        "linux") RAYLIB_PATH="$odin_root_converted/vendor/raylib/linux" ;;
        "windows") RAYLIB_PATH="$odin_root_converted/vendor/raylib/windows" ;;
      esac
    fi
  fi
}

# Detect platform early
detect_platform

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if EMSDK is installed
is_emsdk_installed() {
  [ -d "$EMSDK_DIR" ] && [ -f "$EMSDK_DIR/emsdk" ] && [ -f "$EMSDK_DIR/emsdk_env.sh" ]
}

# Check if EMSDK is activated
is_emsdk_activated() {
  if [ -f "$EMSDK_DIR/emsdk_env.sh" ]; then
    # Source EMSDK environment in subshell to test
    (
      export EMSDK_QUIET=1
      source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
      command -v emcc >/dev/null 2>&1 && emcc --version >/dev/null 2>&1
    )
  else
    return 1
  fi
}

# Install EMSDK
install_emsdk() {
  log_info "📦 Installing EMSDK..."

  # Check prerequisites
  if ! command_exists git; then
    log_error "❌ Git is required but not found. Please install Git first."
    log_info "   On Ubuntu/Debian: sudo apt-get install git"
    log_info "   On macOS: xcode-select --install or brew install git"
    return 1
  fi

  # Python check - more flexible for Windows
  local has_python=false
  if command_exists python3; then
    # Test if python3 actually works (not just an alias)
    if python3 --version >/dev/null 2>&1; then
      has_python=true
      log_debug "Found working python3"
    fi
  elif command_exists python; then
    # Test if python actually works (not just Windows Store alias)
    if python --version >/dev/null 2>&1; then
      has_python=true
      log_debug "Found working python"
    fi
  fi

  if [ "$has_python" = "false" ]; then
    log_warning "⚠️  Python not found, but EMSDK will download its own Python"
    log_info "   If you want to install Python manually:"
    log_info "   On Ubuntu/Debian: sudo apt-get install python3"
    log_info "   On macOS: brew install python"
    log_info "   On Windows: Download from https://python.org/downloads/"
    log_info "   Continuing with EMSDK installation..."
  fi

  # Clone EMSDK repository
  log_info "Cloning EMSDK repository to $EMSDK_DIR..."
  if [ -d "$EMSDK_DIR" ]; then
    rm -rf "$EMSDK_DIR"
  fi

  if ! git clone "$EMSDK_REPO" "$EMSDK_DIR"; then
    log_error "❌ Failed to clone EMSDK repository"
    return 1
  fi

  # Install and activate latest EMSDK
  local original_dir="$(pwd)"
  cd "$EMSDK_DIR"

  log_info "Installing latest EMSDK..."
  if ! ./emsdk install latest; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to install EMSDK"
    return 1
  fi

  log_info "Activating EMSDK..."
  if ! ./emsdk activate latest; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to activate EMSDK"
    return 1
  fi

  # Add to PATH and environment
  export PATH="$PATH:$EMSDK_DIR"
  if [ -d "$EMSDK_DIR/upstream/emscripten" ]; then
    export PATH="$PATH:$EMSDK_DIR/upstream/emscripten"
  fi

  if ! source "$EMSDK_DIR/emsdk_env.sh"; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to source emsdk_env.sh"
    return 1
  fi

  # Return to original directory
  cd "$original_dir"

  log_success "✅ EMSDK installed and activated successfully!"
  return 0
}

# Update EMSDK
update_emsdk() {
  log_info "🔄 Updating EMSDK..."

  # Remember current directory
  local original_dir="$(pwd)"

  cd "$EMSDK_DIR"

  # Pull latest changes
  if ! git pull; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to update EMSDK repository"
    return 1
  fi

  # On Windows (Git Bash), we might need to use EMSDK's bundled Python
  local python_cmd="python3"
  if [ "$PLATFORM" = "windows" ]; then
    # Check if we have EMSDK's bundled Python available
    if [ -f "$EMSDK_DIR/python"/*_64bit/python.exe ]; then
      local emsdk_python=$(find "$EMSDK_DIR/python" -name "python.exe" | head -n 1)
      if [ -n "$emsdk_python" ]; then
        log_debug "Using EMSDK bundled Python: $emsdk_python"
        export EMSDK_PYTHON="$emsdk_python"
      fi
    fi
    python_cmd="python"  # On Windows, try python instead of python3
  fi

  # Install and activate latest
  if ! ./emsdk install latest; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to install latest EMSDK"
    return 1
  fi

  if ! ./emsdk activate latest; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to activate latest EMSDK"
    return 1
  fi

  # Add to PATH and environment
  export PATH="$PATH:$EMSDK_DIR"
  if [ -d "$EMSDK_DIR/upstream/emscripten" ]; then
    export PATH="$PATH:$EMSDK_DIR/upstream/emscripten"
  fi

  if ! source "$EMSDK_DIR/emsdk_env.sh"; then
    cd "$original_dir"  # Return to original directory
    log_error "❌ Failed to source emsdk_env.sh"
    return 1
  fi

  # Return to original directory
  cd "$original_dir"

  log_success "✅ EMSDK updated successfully!"
  return 0
}

# Initialize EMSDK
initialize_emsdk() {
  if [ "$FORCE_UPDATE" = "true" ] || ! is_emsdk_installed; then
    if ! install_emsdk; then
      return 1
    fi
  elif is_emsdk_installed && ! is_emsdk_activated; then
    log_info "EMSDK found but not activated, updating..."
    if ! update_emsdk; then
      return 1
    fi
  else
    log_success "✅ EMSDK already installed and activated"
    # Still need to source environment for this session
    export EMSDK_QUIET=1
    export PATH="$PATH:$EMSDK_DIR"
    if [ -d "$EMSDK_DIR/upstream/emscripten" ]; then
      export PATH="$PATH:$EMSDK_DIR/upstream/emscripten"
    fi
    if ! source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1; then
      log_error "❌ Failed to source EMSDK environment"
      return 1
    fi
  fi

  # Verify emcc is available
  log_debug "Testing emcc availability..."
  if command -v emcc >/dev/null 2>&1; then
    local emcc_version
    if emcc_version=$(emcc --version 2>/dev/null | head -n 1); then
      log_debug "emcc version: $emcc_version"
      log_success "✅ EMSDK environment activated for build"
      return 0
    else
      log_error "❌ emcc found but version check failed"
      return 1
    fi
  else
    log_error "❌ emcc not found after environment setup"
    log_debug "Current PATH includes:"
    echo "$PATH" | tr ':' '\n' | grep -E "(emsdk|emscripten)" | while IFS= read -r path_entry; do
      log_debug "  $path_entry"
    done
    return 1
  fi
}

# Initialize build directories
initialize_build_directories() {
  mkdir -p "$OUT_DIR"

  # Clean the output directory for fresh web build
  log_info "Cleaning web build directory..."
  rm -rf "$OUT_DIR"/*
}

# Build web game
build_web_game() {
  log_info "Building WebAssembly game..."

  # Ensure we're in the project root directory
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir"

  log_debug "Working directory: $(pwd)"
  log_debug "Checking source directory: $(ls -la source/ 2>/dev/null || echo 'source/ not found')"

  # For Windows/Git Bash, we need to use Windows-style paths for the odin command
  local source_arg="$SOURCE_DIR"
  local out_arg="$OUT_DIR/game.wasm.o"

  if [ "$PLATFORM" = "windows" ]; then
    # Convert Unix paths back to Windows format for odin.exe
    source_arg=$(echo "$SOURCE_DIR" | sed 's|/|\\|g')
    out_arg=$(echo "$OUT_DIR/game.wasm.o" | sed 's|/|\\|g')
    log_debug "Using Windows-style paths for odin: source='$source_arg', out='$out_arg'"
  fi

  # Build Odin WebAssembly object
  local build_args=(
    "build" "$source_arg"
    "-target:js_wasm32" "-build-mode:obj"
    "-define:RAYLIB_WASM_LIB=env.o" "-define:RAYGUI_WASM_LIB=env.o"
    "-vet" "-strict-style"
    "-out:$out_arg"
  )

  log_debug "Odin build command: odin ${build_args[*]}"

  if ! odin "${build_args[@]}"; then
    log_error "❌ Odin build failed!"
    return 1
  fi

  # Get Odin root path for library files
  local odin_path_raw
  if ! odin_path_raw=$(odin root); then
    log_error "❌ Failed to get Odin root path"
    return 1
  fi

  # Convert Windows path to Unix path for Git Bash
  local odin_path
  odin_path=$(convert_path "$odin_path_raw")
  log_debug "Odin path: $odin_path_raw -> $odin_path"

  # Copy odin.js runtime
  local odin_js_source="$odin_path/core/sys/wasm/js/odin.js"
  if [ -f "$odin_js_source" ]; then
    cp "$odin_js_source" "$OUT_DIR/odin.js"
    log_success "✅ Copied Odin WebAssembly runtime"
  else
    log_error "❌ odin.js not found at $odin_js_source"
    log_debug "Checked path: $odin_js_source"
    return 1
  fi

  # Build final WebAssembly with emcc
  log_info "Linking WebAssembly with emcc..."

  local files=(
    "$OUT_DIR/game.wasm.o"
    "$odin_path/vendor/raylib/wasm/libraylib.a"
    "$odin_path/vendor/raylib/wasm/libraygui.a"
  )

  local flags=(
    "-sUSE_GLFW=3" "-sWASM_BIGINT" "-sWARN_ON_UNDEFINED_SYMBOLS=0" "-sASSERTIONS"
    "--shell-file" "$SOURCE_DIR/index_template.html"
    "--preload-file" "$ASSETS_DIR"
  )

  if ! emcc -o "$OUT_DIR/index.html" "${files[@]}" "${flags[@]}"; then
    log_error "❌ emcc linking failed!"
    # Clean up temporary object file
    rm -f "$OUT_DIR/game.wasm.o"
    return 1
  fi

  # Clean up temporary object file
  rm -f "$OUT_DIR/game.wasm.o"

  log_success "✅ WebAssembly game built successfully!"
  return 0
}

# Start web server
start_web_server() {
  log_info "🌐 Starting local web server..."

  cd "$OUT_DIR"

  # Try to find a suitable web server
  if command_exists python3; then
    log_info "Starting Python 3 HTTP server on http://localhost:8000"
    python3 -m http.server 8000
  elif command_exists python; then
    log_info "Starting Python HTTP server on http://localhost:8000"
    python -m http.server 8000
  elif command_exists npx; then
    log_info "Starting Node.js HTTP server on http://localhost:8000"
    npx http-server -p 8000
  else
    log_warning "⚠️  No suitable web server found. Please serve files from $OUT_DIR manually."
    log_info "   You can use: python3 -m http.server 8000"
    log_info "   Or install Node.js and use: npx http-server"
  fi
}

# Main function
main() {
  log_info "🌐 Odin Web Build Script"
  log_info "========================"

  # Platform was detected at script start
  log_debug "Platform detected: $PLATFORM"

  # Initialize EMSDK
  if ! initialize_emsdk; then
    exit 1
  fi

  # Initialize build environment
  initialize_build_directories

  # Build the web game
  if ! build_web_game; then
    exit 1
  fi

  # Handle run mode
  if [ "$RUN_MODE" = "true" ]; then
    start_web_server
  fi

  log_success "🎉 Web build complete!"
  log_info "Web build created in $OUT_DIR"

  if [ "$RUN_MODE" != "true" ]; then
    log_info "To test, serve files from $OUT_DIR with a web server:"
    log_info "  python3 -m http.server 8000"
  fi
}

# Run main function
main "$@"