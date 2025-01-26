import subprocess
import os
import pathlib


def run_command(command, env=None):
    """
    Run a shell command and raise an error if it fails.
    """
    result = subprocess.run(command, shell=True, check=True, env=env)
    return result


def main():
    # Constants
    CURRENT_DIR = os.path.abspath(os.path.curdir)
    OUT_DIR = "build/web"
    EMSCRIPTEN_SDK_DIR = os.path.expanduser("~/.emsdk")
    print(f"Emscripten path: {EMSCRIPTEN_SDK_DIR}")

    # Ensure the output directory exists
    os.makedirs(OUT_DIR, exist_ok=True)

    # Set environment variables
    env = os.environ.copy()
    env["EMSDK_QUIET"] = "1"

    # Load emsdk environment if available
    emsdk_env_script = pathlib.Path(EMSCRIPTEN_SDK_DIR) / "emsdk_env.sh"
    if emsdk_env_script.is_file():
        command = f"source {emsdk_env_script} && env"
        result = subprocess.run(command, shell=True,
                                capture_output=True, text=True)
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                key, _, value = line.partition("=")
                env[key] = value

    # Odin build command
    run_command(
        f"odin build source/main_web "
        f"-target:freestanding_wasm32 "
        f"-build-mode:obj "
        f"-define:RAYLIB_WASM_LIB=env.o "
        f"-vet -strict-style "
        f"-o:speed "
        f"-out:{OUT_DIR}/game"
    )

    # Get ODIN_PATH
    odin_root_command = "odin root"
    ODIN_PATH = subprocess.run(
        odin_root_command, shell=True,
        check=True, text=True, capture_output=True).stdout.strip()

    # Files and flags
    files = [
        "source/main_web/main_web.c",
        f"{OUT_DIR}/game.wasm.o",
        f"{ODIN_PATH}/vendor/raylib/wasm/libraylib.a",
    ]
    flags = [
        "-sUSE_GLFW=3",
        "-sMIN_WEBGL_VERSION=2",
        "-sMAX_WEBGL_VERSION=2",
        "-sASSERTIONS",
        "-sSINGLE_FILE",
        "--embed-file assets",
        "--shell-file source/main_web/index_template.html",
    ]

    # Convert lists to space-separated strings
    files_str = " ".join(files)
    flags_str = " ".join(flags)

    # Run emcc command
    emcc_command = f"emcc -o {OUT_DIR}/index.html {files_str} {flags_str}"
    run_command(emcc_command)

    # Clean up intermediate files
    intermediate_file = f"{OUT_DIR}/game.wasm.o"
    if os.path.exists(intermediate_file):
        os.remove(intermediate_file)

    FILE = f"file://{CURRENT_DIR}/{OUT_DIR}/index.html"
    print(f"Web build created in {OUT_DIR}")
    print(f"file: {FILE}")


if __name__ == "__main__":
    main()
