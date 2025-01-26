
import os
import platform
import subprocess
import time
from pathlib import Path

OUT_DIR = Path("build/hot_reload")
EXE = "game_hot_reload.bin"
EXIT_SIGNAL_FILE = "exit_signal.tmp"
ROOT = subprocess.check_output(["odin", "root"], text=True).strip()

last_mtimes = {}


def setup_environment():
    system = platform.system()
    machine = platform.machine()

    if system == "Darwin":
        lib_path = "macos-arm66" if machine == "arm64" else "macos"
        dll_ext = ".dylib"
        extra_linker_flags = f"-Wl,-rpath {ROOT}/vendor/raylib/{lib_path}"
    else:
        dll_ext = ".so"
        extra_linker_flags = "-Wl,-rpath=$ORIGIN/linux"

        linux_dir = OUT_DIR / "linux"
        if not linux_dir.exists():
            linux_dir.mkdir(parents=True, exist_ok=True)
            raylib_files = Path(
                f"{ROOT}/vendor/raylib/linux").glob("libraylib*.so*")
            for file in raylib_files:
                dest = linux_dir / file.name
                dest.write_bytes(file.read_bytes())

    return dll_ext, extra_linker_flags


def build_dll(dll_ext, extra_linker_flags):
    print(f"Building game{dll_ext}")
    build_cmd = [
        "odin", "build", "source",
        f"-extra-linker-flags:{extra_linker_flags}",
        "-define:RAYLIB_SHARED=true",
        "-build-mode:dll",
        f"-out:{OUT_DIR}/game_tmp{dll_ext}",
        "-strict-style",
        "-vet",
        "-debug"
    ]
    try:
        subprocess.run(build_cmd, check=True)
        (OUT_DIR / f"game_tmp{dll_ext}").rename(OUT_DIR / f"game{dll_ext}")
        return True
    except subprocess.CalledProcessError:
        print("Shared library build failed.")
        return False


def build_and_run_binary():
    print(f"Building {EXE}")
    try:
        subprocess.run([
            "odin", "build", "source/main_hot_reload",
            f"-out:{EXE}", "-strict-style", "-vet", "-debug"
        ], check=True)
        return True
    except subprocess.CalledProcessError:
        print("Executable build failed.")
        return False


def is_binary_running():
    try:
        if platform.system() == "Windows":
            result = subprocess.check_output(["tasklist"], text=True)
            return EXE in result
        else:
            result = subprocess.check_output(["ps", "aux"], text=True)
            return EXE in result
    except Exception:
        return False


def run_binary():
    if not is_binary_running():
        print(f"Starting {EXE}...")
        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = f"{
            OUT_DIR}/linux:" + env.get("LD_LIBRARY_PATH", "")
        subprocess.Popen([f"./{EXE}"], env=env)
    else:
        print(f"Hot reloading {EXE}...")


def build_and_run_project(dll_ext, extra_linker_flags):
    dll_built = build_dll(dll_ext, extra_linker_flags)
    binary_built = build_and_run_binary()
    if dll_built and binary_built:
        run_binary()


def populate_last_mtimes(source_dir):
    """Populate the last_mtimes with the current state of all .odin files."""
    global last_mtimes
    last_mtimes = {
        Path(root) / file: (Path(root) / file).stat().st_mtime
        for root, _, files in os.walk(source_dir)
        for file in files
        if file.endswith(".odin")
    }


def check_for_changes(source_dir):
    """Check for changes in the .odin files based on last_mtimes."""
    global last_mtimes
    changes_detected = False

    for root, _, files in os.walk(source_dir):
        for file in files:
            if not file.endswith(".odin"):
                continue

            filepath = Path(root) / file
            try:
                mtime = filepath.stat().st_mtime
                not_checked = filepath not in last_mtimes
                changed = last_mtimes.get(filepath) != mtime
                if not_checked or changed:
                    last_mtimes[filepath] = mtime
                    print(f"Detected change in {filepath}.")
                    changes_detected = True
                    break
            except FileNotFoundError:
                # Handle cases where a file is deleted
                last_mtimes.pop(filepath, None)
        if changes_detected:
            break

    return changes_detected


def watch_for_changes(dll_ext, extra_linker_flags):
    source_dir = Path("source")

    while True:
        if check_for_changes(source_dir):
            print("Rebuilding due to detected changes...")
            build_and_run_project(dll_ext, extra_linker_flags)

        if Path(EXIT_SIGNAL_FILE).exists():
            print("Exit signal detected. Exiting...")
            Path(EXIT_SIGNAL_FILE).unlink()
            break

        time.sleep(1)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dll_ext, extra_linker_flags = setup_environment()

    # Initial build and run
    build_and_run_project(dll_ext, extra_linker_flags)

    # Populate last_mtimes after the initial build
    print("Populating initial file modification times...")
    populate_last_mtimes(Path("source"))

    # Start watching for changes
    print("Watching for changes in .odin files...")
    watch_for_changes(dll_ext, extra_linker_flags)


if __name__ == "__main__":
    main()
