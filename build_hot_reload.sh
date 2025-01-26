#!/bin/bash -e

OUT_DIR=build/hot_reload
EXE=game_hot_reload.bin
EXIT_SIGNAL_FILE="exit_signal.tmp"

mkdir -p $OUT_DIR

ROOT=$(odin root)

case $(uname) in
"Darwin")
  case $(uname -m) in
  "arm64") LIB_PATH="macos-arm64" ;;
  *) LIB_PATH="macos" ;;
  esac

  DLL_EXT=".dylib"
  EXTRA_LINKER_FLAGS="-Wl,-rpath $ROOT/vendor/raylib/$LIB_PATH"
  ;;
*)
  DLL_EXT=".so"
  EXTRA_LINKER_FLAGS="'-Wl,-rpath=\$ORIGIN/linux'"

  # Copy the Linux libraries into the project automatically.
  if [ ! -d "$OUT_DIR/linux" ]; then
    mkdir -p $OUT_DIR/linux
    cp -r "$ROOT"/vendor/raylib/linux/libraylib*.so* $OUT_DIR/linux
  fi
  ;;
esac

build_and_run_project() {
  echo "Building game$DLL_EXT"
  BUILD_CMD=(odin build source
    -extra-linker-flags:"$EXTRA_LINKER_FLAGS"
    -define:RAYLIB_SHARED=true
    -build-mode:dll
    -out:"$OUT_DIR/game_tmp$DLL_EXT"
    -strict-style
    -vet
    -debug)
  if ! "${BUILD_CMD[@]}"; then
    echo "Shared library build failed. Fix errors and save to retry."
    return
  fi

  mv $OUT_DIR/game_tmp$DLL_EXT $OUT_DIR/game$DLL_EXT

  if ! pgrep -f "./$EXE" >/dev/null; then
    echo "Game binary is not running. Starting $EXE..."
    echo "Building $EXE"
    if ! odin build source/main_hot_reload -out:$EXE -strict-style -vet -debug; then
      echo "Executable build failed. Fix errors and save to retry."
      return
    fi
    echo "Running $EXE"
    ./$EXE &
  else
    PID=$(pgrep -f "./$EXE")
    echo "Hot reloading ./$EXE [PID $PID] ..."
  fi
}

# Initial build and run
build_and_run_project "$@"

# Watch for changes in .odin files
echo "Watching for changes in .odin files..."

# Run inotifywait in the background
inotifywait -m -r -e close_write --format '%w%f' . |
  while read -r file; do
    if [[ "$file" == *.odin ]]; then
      echo "Detected change in $file. Rebuilding..."
      build_and_run_project
    fi
  done &

INOTIFY_PID=$!

# Monitor for the exit signal in the foreground
while true; do
  if [ -f "$EXIT_SIGNAL_FILE" ]; then
    echo "Exit signal detected. Exiting..."
    rm -f "$EXIT_SIGNAL_FILE"
    kill "$INOTIFY_PID" 2>/dev/null
    exit 0
  fi
  sleep 1
done
