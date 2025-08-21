package build

import "core:fmt"
import "core:os"
import "core:strings"
import "core:encoding/base64"
import "core:strconv"
import "core:os/os2"
import "core:slice"
import "core:terminal/ansi"
import "core:time"
import "core:thread"
import win "core:sys/windows"

// Feature flag: Use WebGL2 context and shaders (false = WebGL1, true = WebGL2)
// WebGL2 has known vertex attribute issues with Raylib (GitHub issue #4330)
// TODO: I should figure this shit out.
USE_WEBGL2 :: false

// ANSI color codes for coloured output using core:terminal/ansi
RESET     :: ansi.CSI + ansi.RESET + ansi.SGR
RED       :: ansi.CSI + ansi.FG_RED + ansi.SGR
GREEN     :: ansi.CSI + ansi.FG_GREEN + ansi.SGR
YELLOW    :: ansi.CSI + ansi.FG_YELLOW + ansi.SGR
BLUE      :: ansi.CSI + ansi.FG_BLUE + ansi.SGR
MAGENTA   :: ansi.CSI + ansi.FG_MAGENTA + ansi.SGR
CYAN      :: ansi.CSI + ansi.FG_CYAN + ansi.SGR
WHITE     :: ansi.CSI + ansi.FG_WHITE + ansi.SGR
BOLD      :: ansi.CSI + ansi.BOLD + ansi.SGR

GLOBAL_WASM_PARAMS :: "-sUSE_GLFW=3 -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sASSERTIONS -s ALLOW_MEMORY_GROWTH=1 -s MEMORY_GROWTH_LINEAR_STEP=32MB -s STACK_SIZE=2MB -s INITIAL_MEMORY=32MB -s MAXIMUM_MEMORY=128MB"

// coloured output helpers with colors and simple text indicators
print_info :: proc(msg: string) {
  fmt.printf("%s[INFO] %s%s\n", BLUE, msg, RESET)
}

print_success :: proc(msg: string) {
  fmt.printf("%s[SUCCESS] %s%s\n", GREEN, msg, RESET)
}

print_error :: proc(msg: string) {
  fmt.printf("%s[ERROR] %s%s\n", RED, msg, RESET)
}

print_warning :: proc(msg: string) {
  fmt.printf("%s[WARNING] %s%s\n", YELLOW, msg, RESET)
}

print_header :: proc(msg: string) {
  fmt.printf("%s%s%s%s\n", BOLD, CYAN, msg, RESET)
  fmt.printf("%s===================%s\n", CYAN, RESET)
}

print_rebuild :: proc(msg: string) {
  fmt.printf("%s[REBUILD] %s%s\n", CYAN, msg, RESET)
}

// detect shell environment for cross-compatibility
detect_shell :: proc() -> string {
  // check if we're in GitBash by looking for common GitBash environment variables
  if os.get_env("MSYSTEM") != "" || os.get_env("BASH_VERSION") != "" {
    return "bash"
  }

  // check if we're in PowerShell
  if os.get_env("PSModulePath") != "" {
    return "powershell"
  }

  // default to cmd on Windows
  when ODIN_OS == .Windows {
    return "cmd"
  } else {
    return "bash"
  }
}

// convert Windows path to Unix path for GitBash
windows_to_unix_path :: proc(path: string) -> string {
  // convert C:\Users\... to /c/Users/...
  if len(path) >= 3 && path[1] == ':' && path[2] == '\\' {
    drive_letter := strings.to_lower(string([]u8{path[0]}))
    rest_path, _ := strings.replace_all(path[3:], "\\", "/")
    return fmt.tprintf("/%s/%s", drive_letter, rest_path)
  }

  // just replace backslashes with forward slashes
  result, _ := strings.replace_all(path, "\\", "/")
  return result
}

print_rocket :: proc(msg: string) {
  fmt.printf("%s[LAUNCH] %s%s\n", GREEN, msg, RESET)
}

// execute a command and return success
run_command :: proc(program: string, args: []string) -> bool {
  full_cmd := fmt.tprintf("%s %s", program, strings.join(args, " "))
  print_info(fmt.tprintf("Running: %s", full_cmd))

  // use the os2 package for proper process execution
  cmd_args := make([]string, len(args) + 1)
  cmd_args[0] = program
  copy(cmd_args[1:], args)

  process_desc := os2.Process_Desc{
    command = cmd_args,
    stdout = os2.stdout,
    stderr = os2.stderr,
    stdin = os2.stdin,
  }

  process, start_err := os2.process_start(process_desc)
  if start_err != nil {
    print_error(fmt.tprintf("Failed to start process: %v", start_err))
    return false
  }
  defer {
    close_err := os2.process_close(process)
    if close_err != nil {
      // ignoring close errors for now
    }
  }

  state, wait_err := os2.process_wait(process)
  if wait_err != nil {
    print_error(fmt.tprintf("Failed to wait for process: %v", wait_err))
    return false
  }

  return state.exit_code == 0
}

// execute a command and return success with output capture
run_command_with_output :: proc(program: string, args: []string) -> struct{success: bool, output: string} {
  full_cmd := fmt.tprintf("%s %s", program, strings.join(args, " "))
  print_info(fmt.tprintf("Running: %s", full_cmd))

  // use the os2 package for proper process execution with output capture
  cmd_args := make([]string, len(args) + 1)
  cmd_args[0] = program
  copy(cmd_args[1:], args)

  process_desc := os2.Process_Desc{
    command = cmd_args,
    // stdout and stderr are nil - this allows process_exec to capture them
  }

  state, stdout_bytes, stderr_bytes, exec_err := os2.process_exec(process_desc, context.temp_allocator)
  defer {
    if stdout_bytes != nil do delete(stdout_bytes)
    if stderr_bytes != nil do delete(stderr_bytes)
  }

  if exec_err != nil {
    print_error(fmt.tprintf("Failed to execute process: %v", exec_err))
    return {false, ""}
  }

  // convert stdout to string and trim whitespace
  output := strings.trim_space(string(stdout_bytes))

  return {state.exit_code == 0, output}
}

main :: proc() {
  print_header("Odin Build System")

  if len(os.args) < 2 {
    print_usage()
    return
  }

  command := os.args[1]

  // parse additional flags
  watch := false
  run_after := false
  build_only := false
  debug := false

  for i in 2..<len(os.args) {
    switch os.args[i] {
    case "--watch":
      watch = true
    case "--run":
      run_after = true
    case "--build-only":
      build_only = true
    case "--debug":
      debug = true
    }
  }

  switch command {
    case "hot-reload":
      build_hot_reload(watch, run_after, build_only)
    case "debug":
      build_debug()
    case "release":
      build_release()
    case "web":
      build_web(debug)
    case "web-single":
      build_web_single(debug)
    case "help", "--help":
      print_usage()
    case:
      print_error(fmt.tprintf("Unknown command: %s", command))
      print_usage()
  }
}

print_usage :: proc() {
  print_info("Usage:")
  print_info("  build hot-reload [--watch] [--run] [--build-only]")
  print_info("  build debug")
  print_info("  build release")
  print_info("  build web [--debug]")
  print_info("  build web-single [--debug]")
  print_info("  build help")
  print_info("")
  print_info("Commands:")
  print_info("  hot-reload   Build with hot-reload support and file watching")
  print_info("  debug        Build debug executable with debug symbols")
  print_info("  release      Build optimized release executable")
  print_info("  web          Build WebAssembly version (build/web or build/web_debug)")
  print_info("  web-single   Create single-file WebAssembly build (build/web_single or build/web_single_debug)")
  print_info("")
  print_info("Hot-reload flags:")
  print_info("  --watch      Watch files and rebuild on changes (default)")
  print_info("  --run        Run the game after building (default)")
  print_info("  --build-only Build once and exit")
  print_info("")
  print_info("Web build flags:")
  print_info("  --debug      Enable ODIN_DEBUG for web builds (uses separate debug directories)")
}

// copy a directory and its contents
copy_directory :: proc(src_dir: string, dst_dir: string) -> bool {
  // create destination directory
  os.make_directory(dst_dir)

  // read source directory
  src_handle, src_err := os.open(src_dir)
  if src_err != os.ERROR_NONE {
    print_error(fmt.tprintf("Failed to open source directory: %s", src_dir))
    return false
  }
  defer os.close(src_handle)

  files, read_err := os.read_dir(src_handle, -1)
  if read_err != os.ERROR_NONE {
    print_error(fmt.tprintf("Failed to read directory: %s", src_dir))
    return false
  }
  defer delete(files)

  for file in files {
    src_path := fmt.tprintf("%s/%s", src_dir, file.name)
    dst_path := fmt.tprintf("%s/%s", dst_dir, file.name)

    if file.is_dir {
      // recursively copy subdirectory
      if !copy_directory(src_path, dst_path) {
        return false
      }
    } else {
      // copy file
      data, read_ok := os.read_entire_file(src_path)
      if !read_ok {
        print_error(fmt.tprintf("Failed to read file: %s", src_path))
        return false
      }
      defer delete(data)

      write_ok := os.write_entire_file(dst_path, data)
      if !write_ok {
        print_error(fmt.tprintf("Failed to write file: %s", dst_path))
        return false
      }
    }
  }

  return true
}

build_web_single :: proc(debug := false) {
  print_info("Building web single-file version...")

  // check if web build exists - look in the appropriate directory based on debug flag
  web_dir := debug ? "build/web_debug" : "build/web"
  if !os.is_dir(web_dir) {
    print_error(fmt.tprintf("Web build directory not found: %s", web_dir))
    debug_suffix := debug ? " --debug" : ""
    print_info(fmt.tprintf("Run web build first: ./build.exe web%s", debug_suffix))
    return
  }

  // create output directory - use different directory based on debug flag
  output_dir := debug ? "build/web_single_debug" : "build/web_single"
  os.make_directory(output_dir)

  // read source files
  print_info("Reading source files...")
  html_data, html_ok := os.read_entire_file(fmt.tprintf("%s/index.html", web_dir))
  if !html_ok {
    print_error("Failed to read index.html")
    return
  }
  defer delete(html_data)

  odin_js_data, odin_ok := os.read_entire_file(fmt.tprintf("%s/odin.js", web_dir))
  if !odin_ok {
    print_error("Failed to read odin.js")
    return
  }
  defer delete(odin_js_data)

  index_js_data, index_ok := os.read_entire_file(fmt.tprintf("%s/index.js", web_dir))
  if !index_ok {
    print_error("Failed to read index.js")
    return
  }
  defer delete(index_js_data)

  // read binary files
  print_info("Reading binary files...")
  wasm_data, wasm_ok := os.read_entire_file(fmt.tprintf("%s/index.wasm", web_dir))
  if !wasm_ok {
    print_error("Failed to read index.wasm")
    return
  }
  defer delete(wasm_data)

  data_file_data, data_ok := os.read_entire_file(fmt.tprintf("%s/index.data", web_dir))
  if !data_ok {
    print_error("Failed to read index.data")
    return
  }
  defer delete(data_file_data)

  // read icon file for favicon injection
  print_info("Reading icon file...")
  icon_data, icon_ok := os.read_entire_file("assets/tri.png")
  icon_base64: string
  defer if icon_ok do delete(icon_base64)

  if icon_ok {
    icon_base64 = base64.encode(icon_data)
    defer delete(icon_data)
  } else {
    print_warning("Icon file not found: assets/tri.png - favicon will not be embedded")
  }

  // convert to strings
  html := string(html_data)
  odin_js := string(odin_js_data)
  index_js := string(index_js_data)

  // encode binary files to base64
  print_info("Encoding binary files...")
  wasm_base64 := base64.encode(wasm_data)
  defer delete(wasm_base64)

  data_base64 := base64.encode(data_file_data)
  defer delete(data_base64)

  // perform replacements
  print_info("Creating single-file HTML...")

  // inject favicon after viewport meta tag
  if icon_ok {
    favicon_links := fmt.tprintf(`
	<link rel="icon" type="image/png" href="data:image/png;base64,%s">
	<meta name="theme-color" content="#000000">`, icon_base64)

    html, _ = strings.replace_all(html,
      `<meta name="viewport" content="width=device-width">`,
      fmt.tprintf(`<meta name="viewport" content="width=device-width">%s`, favicon_links))
  }

  // replace script tags
  html, _ = strings.replace_all(html, `<script type="text/javascript" src="odin.js"></script>`, fmt.tprintf("<script>%s</script>", odin_js))
  html, _ = strings.replace_all(html, `<script async type="text/javascript" src="index.js"></script>`, fmt.tprintf("<script>%s</script>", index_js))

  // ! WARNING: volatile fix for passive event listeners to remove browser violations
  print_info("Patching event listeners for passive mode...")
  html, _ = strings.replace_all(html, `canvas.addEventListener('touchmove', GLFW.onMousemove, true);`, `canvas.addEventListener('touchmove', GLFW.onMousemove, {passive: false});`)
  html, _ = strings.replace_all(html, `canvas.addEventListener('touchstart', GLFW.onMouseButtonDown, true);`, `canvas.addEventListener('touchstart', GLFW.onMouseButtonDown, {passive: false});`)
  html, _ = strings.replace_all(html, `canvas.addEventListener('wheel', GLFW.onMouseWheel, true);`, `canvas.addEventListener('wheel', GLFW.onMouseWheel, {passive: false});`)
  html, _ = strings.replace_all(html, `canvas.addEventListener('mousewheel', GLFW.onMouseWheel, true);`, `canvas.addEventListener('mousewheel', GLFW.onMouseWheel, {passive: false});`)

  // ! WARNING: volatile fix for generic event handler registration for touch events
  html, _ = strings.replace_all(html, `eventHandler.useCapture);`, `eventHandler.eventTypeString === 'touchstart' || eventHandler.eventTypeString === 'touchmove' || eventHandler.eventTypeString === 'wheel' || eventHandler.eventTypeString === 'mousewheel' ? {passive: false} : eventHandler.useCapture);`)

  // replace WASM fetch
  wasm_data_url := fmt.tprintf("data:application/wasm;base64,%s", wasm_base64)
  html, _ = strings.replace_all(html, `fetch("index.wasm")`, fmt.tprintf(`fetch("%s")`, wasm_data_url))

  // replace data file references
  data_data_url := fmt.tprintf("data:application/octet-stream;base64,%s", data_base64)
  html, _ = strings.replace_all(html, `"index.data"`, fmt.tprintf(`"%s"`, data_data_url))
  html, _ = strings.replace_all(html, `'index.data'`, fmt.tprintf(`'%s'`, data_data_url))
  html, _ = strings.replace_all(html, `build/web/index.data`, data_data_url)
  html, _ = strings.replace_all(html, `index.data`, data_data_url)

  // write output file
  output_path := fmt.tprintf("%s/game_standalone.html", output_dir)
  output_ok := os.write_entire_file(output_path, transmute([]byte)html)

  if !output_ok {
    print_error("Failed to write output file")
    return
  }

  print_success("Single-file HTML created successfully!")
  print_info(fmt.tprintf("Output: %s", output_path))
  print_info(fmt.tprintf("Size: %d bytes (~ %d MB)", len(html), len(html)/1024/1024))
  print_success("Build completed!")
}

build_hot_reload :: proc(watch: bool, run_after: bool, build_only: bool) {
  print_info("Building hot-reload version...")

  // config
  OUT_DIR := "build/hot_reload"
  GAME_PDBS_DIR := fmt.tprintf("%s/game_pdbs", OUT_DIR)
  EXE := "game_hot_reload.exe"
  SOURCE_DIR := "src"

  // create directories
  os.make_directory(OUT_DIR)
  os.make_directory(GAME_PDBS_DIR)

  // if no flags specified default to watch mode
  actual_watch := watch
  if !watch && !run_after && !build_only {
    actual_watch = true
  }

  // first build the game DLL
  if !build_game_dll(OUT_DIR, GAME_PDBS_DIR, SOURCE_DIR, false) {
    return
  }

  // then build the hot-reload exe
  if !build_game_exe(OUT_DIR, EXE) {
    return
  }

  if actual_watch {
    start_file_watcher(OUT_DIR, GAME_PDBS_DIR, SOURCE_DIR, EXE)
  } else if run_after {
    print_info("Starting game...")
    start_game(EXE)
  } else {
    print_success("Hot-reload build completed!")
    print_info(fmt.tprintf("Run the game with: %s", EXE))
  }
}

// debug build function - creates debug executable
build_debug :: proc() {
  print_info("Building debug version...")

  // configuration
  OUT_DIR := "build/debug"
  SOURCE_DIR := "src/main_release"
  EXE_NAME := "game_debug.exe"
  EXE_PATH := fmt.tprintf("%s/%s", OUT_DIR, EXE_NAME)

  // create output directory
  os.make_directory(OUT_DIR)

  // copy shaders to debug directory
  if os.is_dir("shaders") {
    print_info("Copying shader files...")
    copy_directory("shaders", fmt.tprintf("%s/shaders", OUT_DIR))
  }

  // copy assets to debug directory
  if os.is_dir("assets") {
    print_info("Copying asset files...")
    copy_directory("assets", fmt.tprintf("%s/assets", OUT_DIR))
  }

  // build arguments matching PowerShell version
  build_args := []string{
    "build", SOURCE_DIR,
    "-strict-style", "-vet", "-debug",
    "-define:ODIN_DEBUG=true",
    fmt.tprintf("-out:%s", EXE_PATH),
  }

  print_info("Compiling debug build...")
  if !run_command("odin", build_args) {
    print_error("Debug build failed!")
    return
  }

  print_success("Debug build completed!")
  print_info(fmt.tprintf("Debug executable: %s", EXE_PATH))
}

// release build function - creates optimized release executable
build_release :: proc() {
  print_info("Building release version...")

  // configuration
  OUT_DIR := "build/release"
  SOURCE_DIR := "src/main_release"
  EXE_NAME := "game_release.exe"
  EXE_PATH := fmt.tprintf("%s/%s", OUT_DIR, EXE_NAME)

  // create output directory
  os.make_directory(OUT_DIR)

  // copy shaders to release directory
  if os.is_dir("shaders") {
    print_info("Copying shader files...")
    copy_directory("shaders", fmt.tprintf("%s/shaders", OUT_DIR))
  }

  // copy assets to release directory
  if os.is_dir("assets") {
    print_info("Copying asset files...")
    copy_directory("assets", fmt.tprintf("%s/assets", OUT_DIR))
  }

  // build arguments matching PowerShell version
  build_args := []string{
    "build", SOURCE_DIR,
    "-strict-style", "-vet",
    "-no-bounds-check", "-o:speed",
    "-subsystem:windows",
    fmt.tprintf("-out:%s", EXE_PATH),
  }

  print_info("Compiling optimized release build...")
  if !run_command("odin", build_args) {
    print_error("Release build failed!")
    return
  }

  print_success("Release build completed!")
  print_info(fmt.tprintf("Release executable: %s", EXE_PATH))
}

// web build function - creates WebAssembly build with complete EMSDK management
build_web :: proc(debug := false) {
  print_info("Building WebAssembly version...")

  // configuration - use different directories based on debug flag
  OUT_DIR := debug ? "build/web_debug" : "build/web"
  SOURCE_DIR := "src/main_web"
  ASSETS_DIR := "assets"

  // get user home directory for EMSDK
  user_home := os.get_env("USERPROFILE") // Windows
  if user_home == "" {
    user_home = os.get_env("HOME") // Unix fallback
  }

  EMSDK_DIR := fmt.tprintf("%s/.emsdk", user_home)
  EMSDK_REPO := "https://github.com/emscripten-core/emsdk.git"

  // check if source directory exists
  if !os.is_dir(SOURCE_DIR) {
    print_error(fmt.tprintf("Source directory not found: %s", SOURCE_DIR))
    return
  }

  // initialize EMSDK (install if needed)
  if !initialize_emsdk(EMSDK_DIR, EMSDK_REPO) {
    return
  }

  // create output directory
  if !os.is_dir(OUT_DIR) {
    os.make_directory(OUT_DIR)
  } else {
    print_info("Output directory exists - files will be overwritten")
  }

  print_info("Building Odin WebAssembly object...")

  // build odin webassembly object
  build_args := make([dynamic]string)
  defer delete(build_args)

  append(&build_args, "build", SOURCE_DIR)
  append(&build_args, "-target:js_wasm32", "-build-mode:obj")
  append(&build_args, "-define:RAYLIB_WASM_LIB=env.o", "-define:RAYGUI_WASM_LIB=env.o")
  append(&build_args, "-vet", "-strict-style")
  append(&build_args, fmt.tprintf("-out:%s/game.wasm.o", OUT_DIR))

  // add debug define if requested
  if debug {
    append(&build_args, "-define:ODIN_DEBUG=true")
  }

  if !run_command("odin", build_args[:]) {
    print_error("Odin WebAssembly build failed!")
    return
  }

  // get odin root path for library files
  print_info("Getting Odin runtime files...")
  odin_root_result := run_command_with_output("odin", []string{"root"})
  if !odin_root_result.success {
    print_error("Failed to get Odin root path")
    return
  }

  odin_root := strings.trim_space(odin_root_result.output)

  // copy odin.js runtime
  odin_js_source := fmt.tprintf("%s/core/sys/wasm/js/odin.js", odin_root)
  odin_js_dest := fmt.tprintf("%s/odin.js", OUT_DIR)

  odin_js_data, odin_js_ok := os.read_entire_file(odin_js_source)
  if !odin_js_ok {
    print_error(fmt.tprintf("Failed to read odin.js from %s", odin_js_source))
    return
  }
  defer delete(odin_js_data)

  odin_js_write_ok := os.write_entire_file(odin_js_dest, odin_js_data)
  if !odin_js_write_ok {
    print_error("Failed to copy odin.js")
    return
  }

  // now do the emcc linking step with proper environment
  print_info("Linking WebAssembly with emcc (activating EMSDK in same session)...")

  // build emcc arguments
  game_obj := fmt.tprintf("%s/game.wasm.o", OUT_DIR)
  raylib_a := fmt.tprintf("%s/vendor/raylib/wasm/libraylib.a", odin_root)
  raygui_a := fmt.tprintf("%s/vendor/raylib/wasm/libraygui.a", odin_root)
  final_html := fmt.tprintf("%s/index.html", OUT_DIR)
  shell_file := fmt.tprintf("%s/index_template.html", SOURCE_DIR)

  // concatenate the commands in a single session as it's the best
  // cross-compatible approach I could think of so far (shortcut)
  shell := detect_shell()

  emsdk_env_script: string
  emcc_cmd: string
  shell_cmd: []string
  cmd_separator: string

  switch shell {
  case "bash":
    // GitBash/Unix environment: use .sh scripts and bash with Unix paths
    unix_emsdk_dir := windows_to_unix_path(EMSDK_DIR)
    unix_final_html := windows_to_unix_path(final_html)
    unix_game_obj := windows_to_unix_path(game_obj)
    unix_raylib_a := windows_to_unix_path(raylib_a)
    unix_raygui_a := windows_to_unix_path(raygui_a)
    unix_shell_file := windows_to_unix_path(shell_file)
    unix_assets_dir := windows_to_unix_path(ASSETS_DIR)

    emsdk_env_script = fmt.tprintf("source %s/emsdk_env.sh", unix_emsdk_dir)
    when USE_WEBGL2 {
      emcc_cmd = fmt.tprintf("emcc -o %s %s %s %s %s -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 --shell-file %s --preload-file %s --preload-file shaders",
        unix_final_html, unix_game_obj, unix_raylib_a, unix_raygui_a, GLOBAL_WASM_PARAMS, unix_shell_file, unix_assets_dir)
    } else {
      emcc_cmd = fmt.tprintf("emcc -o %s %s %s %s %s --shell-file %s --preload-file %s --preload-file shaders",
        unix_final_html, unix_game_obj, unix_raylib_a, unix_raygui_a, GLOBAL_WASM_PARAMS, unix_shell_file, unix_assets_dir)
    }
    cmd_separator = " && "
    shell_cmd = []string{"bash", "-c"}
    print_info("Detected GitBash/Unix environment")

  case "powershell":
    // PowerShell environment: use .ps1 scripts
    emsdk_env_script = fmt.tprintf("& '%s/emsdk_env.ps1'", EMSDK_DIR)
    when USE_WEBGL2 {
      emcc_cmd = fmt.tprintf("emcc -o %s %s %s %s %s -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 --shell-file %s --preload-file %s --preload-file shaders",
        final_html, game_obj, raylib_a, raygui_a, GLOBAL_WASM_PARAMS, shell_file, ASSETS_DIR)
    } else {
      emcc_cmd = fmt.tprintf("emcc -o %s %s %s %s %s --shell-file %s --preload-file %s --preload-file shaders",
        final_html, game_obj, raylib_a, raygui_a, GLOBAL_WASM_PARAMS, shell_file, ASSETS_DIR)
    }
    cmd_separator = "; "
    shell_cmd = []string{"pwsh", "-Command"}
    print_info("Detected PowerShell environment")

  case:
    // Windows Command Prompt: use .bat scripts
    emsdk_env_script = fmt.tprintf("%s/emsdk_env.bat", EMSDK_DIR)
    when USE_WEBGL2 {
      emcc_cmd = fmt.tprintf("emcc -o %s %s %s %s %s -s MIN_WEBGL_VERSION=2 -s MAX_WEBGL_VERSION=2 --shell-file %s --preload-file %s --preload-file shaders",
        final_html, game_obj, raylib_a, raygui_a, GLOBAL_WASM_PARAMS, shell_file, ASSETS_DIR)
    } else {
      emcc_cmd = fmt.tprintf("emcc -o %s %s %s %s %s --shell-file %s --preload-file %s --preload-file shaders",
        final_html, game_obj, raylib_a, raygui_a, GLOBAL_WASM_PARAMS, shell_file, ASSETS_DIR)
    }
    cmd_separator = " && "
    shell_cmd = []string{"cmd", "/C"}
    print_info("Detected Windows Command Prompt environment")
  }

  // run BOTH commands in the same shell session using appropriate separator
  combined_cmd := fmt.tprintf("%s%s%s", emsdk_env_script, cmd_separator, emcc_cmd)

  shell_args := make([]string, len(shell_cmd) + 1)
  copy(shell_args, shell_cmd)
  shell_args[len(shell_cmd)] = combined_cmd

  if !run_command(shell_args[0], shell_args[1:]) {
    print_error("emcc linking failed!")
    return
  }

  // clean up temporary object file
  os.remove(game_obj)

  // post-process HTML to inject favicon
  print_info("Injecting favicon into HTML...")
  inject_favicon_into_web_html(final_html)

  print_success("Complete WebAssembly build finished!")
  print_info(fmt.tprintf("Web game ready at: %s/index.html", OUT_DIR))
  print_info("To test, serve files with: python -m http.server 8000 (from the build directory)")
}

// initialize EMSDK - complete installation and setup
initialize_emsdk :: proc(emsdk_dir: string, emsdk_repo: string) -> bool {
  print_info("Checking EMSDK installation...")

  // check if EMSDK is already installed
  if is_emsdk_installed(emsdk_dir) {
    print_info("EMSDK found, checking if activated...")

    if is_emsdk_activated(emsdk_dir) {
      print_success("EMSDK already installed and activated")
      return true
    } else {
      print_info("EMSDK found but not activated, updating...")
      return update_emsdk(emsdk_dir)
    }
  }

  // install EMSDK from scratch
  print_info("EMSDK not found, installing...")
  return install_emsdk(emsdk_dir, emsdk_repo)
}

// check if EMSDK is installed (cross-compatible)
is_emsdk_installed :: proc(emsdk_dir: string) -> bool {
  if !os.is_dir(emsdk_dir) do return false

  // always check Windows paths since os.is_file expects Windows paths
  // even when running in GitBash
  emsdk_script := fmt.tprintf("%s/emsdk.bat", emsdk_dir)
  emsdk_env_script := fmt.tprintf("%s/emsdk_env.bat", emsdk_dir)

  return os.is_file(emsdk_script) && os.is_file(emsdk_env_script)
}// check if EMSDK is activated (emcc available)
is_emsdk_activated :: proc(emsdk_dir: string) -> bool {
  // try to find emcc in expected location
  emcc_path := fmt.tprintf("%s/upstream/emscripten/emcc.bat", emsdk_dir)
  return os.is_file(emcc_path)
}

// install EMSDK from repository
install_emsdk :: proc(emsdk_dir: string, emsdk_repo: string) -> bool {
  print_info("Installing EMSDK...")

  // check prerequisites
  if !check_command_exists("git") {
    print_error("Git is required but not found. Please install Git first.")
    print_info("Download from: https://git-scm.com/download/win")
    return false
  }

  if !check_command_exists("python") {
    print_error("Python is required but not found. Please install Python first.")
    print_info("Download from: https://python.org/downloads/")
    return false
  }

  // remove existing directory if it exists
  if os.is_dir(emsdk_dir) {
    print_info("Removing existing EMSDK directory...")
    // Note: os.remove_directory only works for empty dirs, we'll just warn for now
    print_warning("Please manually remove existing .emsdk directory if git clone fails")
  }

  // clone EMSDK repository
  print_info(fmt.tprintf("Cloning EMSDK repository to %s...", emsdk_dir))
  git_args := []string{"clone", emsdk_repo, emsdk_dir}

  if !run_command("git", git_args) {
    print_error("Failed to clone EMSDK repository")
    return false
  }

  // install and activate latest EMSDK (cross-compatible)
  print_info("Installing latest EMSDK...")
  shell := detect_shell()

  emsdk_install_cmd: []string
  emsdk_activate_cmd: []string

  switch shell {
  case "bash":
    unix_emsdk_dir := windows_to_unix_path(emsdk_dir)
    emsdk_install_cmd = []string{"bash", "-c", fmt.tprintf("cd %s && ./emsdk install latest", unix_emsdk_dir)}
    emsdk_activate_cmd = []string{"bash", "-c", fmt.tprintf("cd %s && ./emsdk activate latest", unix_emsdk_dir)}
  case "powershell":
    emsdk_install_cmd = []string{"pwsh", "-Command", fmt.tprintf("cd %s; & './emsdk.ps1' install latest", emsdk_dir)}
    emsdk_activate_cmd = []string{"pwsh", "-Command", fmt.tprintf("cd %s; & './emsdk.ps1' activate latest", emsdk_dir)}
  case:
    emsdk_install_cmd = []string{"cmd", "/C", fmt.tprintf("%s/emsdk.bat install latest", emsdk_dir)}
    emsdk_activate_cmd = []string{"cmd", "/C", fmt.tprintf("%s/emsdk.bat activate latest", emsdk_dir)}
  }

  if !run_command(emsdk_install_cmd[0], emsdk_install_cmd[1:]) {
    print_error("Failed to install EMSDK")
    return false
  }

  print_info("Activating EMSDK...")
  if !run_command(emsdk_activate_cmd[0], emsdk_activate_cmd[1:]) {
    print_error("Failed to activate EMSDK")
    return false
  }

  print_success("EMSDK installed and activated successfully!")
  return true
}

// update existing EMSDK installation
update_emsdk :: proc(emsdk_dir: string) -> bool {
  print_info("Updating EMSDK...")

  // pull latest changes
  git_pull_args := []string{"-C", emsdk_dir, "pull"}
  if !run_command("git", git_pull_args) {
    print_error("Failed to update EMSDK repository")
    return false
  }

  // install and activate latest (cross-compatible)
  print_info("Installing latest EMSDK...")
  shell := detect_shell()

  emsdk_install_cmd: []string
  emsdk_activate_cmd: []string

  switch shell {
  case "bash":
    unix_emsdk_dir := windows_to_unix_path(emsdk_dir)
    emsdk_install_cmd = []string{"bash", "-c", fmt.tprintf("cd %s && ./emsdk install latest", unix_emsdk_dir)}
    emsdk_activate_cmd = []string{"bash", "-c", fmt.tprintf("cd %s && ./emsdk activate latest", unix_emsdk_dir)}
  case "powershell":
    emsdk_install_cmd = []string{"pwsh", "-Command", fmt.tprintf("cd %s; & './emsdk.ps1' install latest", emsdk_dir)}
    emsdk_activate_cmd = []string{"pwsh", "-Command", fmt.tprintf("cd %s; & './emsdk.ps1' activate latest", emsdk_dir)}
  case:
    emsdk_install_cmd = []string{"cmd", "/C", fmt.tprintf("%s/emsdk.bat install latest", emsdk_dir)}
    emsdk_activate_cmd = []string{"cmd", "/C", fmt.tprintf("%s/emsdk.bat activate latest", emsdk_dir)}
  }

  if !run_command(emsdk_install_cmd[0], emsdk_install_cmd[1:]) {
    print_error("Failed to install latest EMSDK")
    return false
  }

  print_info("Activating EMSDK...")
  if !run_command(emsdk_activate_cmd[0], emsdk_activate_cmd[1:]) {
    print_error("Failed to activate latest EMSDK")
    return false
  }

  print_success("EMSDK updated successfully!")
  return true
}

// check if a command exists in PATH
check_command_exists :: proc(command: string) -> bool {
  // try to run command --version to see if it exists
  test_result := run_command_with_output(command, []string{"--version"})
  return test_result.success
}

// run command with EMSDK environment setup - EXACTLY like PowerShell script
run_command_with_env :: proc(program: string, args: []string, emsdk_dir: string) -> bool {
  full_cmd := fmt.tprintf("%s %s", program, strings.join(args, " "))
  print_info(fmt.tprintf("Running: %s", full_cmd))

  current_path := os.get_env("PATH")

  // find Node.js
  node_dir := fmt.tprintf("%s/node", emsdk_dir)
  node_exe := ""
  if os.is_dir(node_dir) {
    // TODO: fix this shit
    // In a real implementation we'd scan
    node_exe = fmt.tprintf("%s/22.16.0_64bit/bin/node.exe", node_dir)
  }

  // find Python
  python_dir := fmt.tprintf("%s/python", emsdk_dir)
  python_exe := ""
  if os.is_dir(python_dir) {
    // TODO: fix this shit
    // In a real implementation we'd scan
    python_exe = fmt.tprintf("%s/3.13.3_64bit/python.exe", python_dir)
  }

  // clear any existing EMSDK paths from PATH (simplified)
  // add EMSDK paths to PATH in correct order (cross-compatible)
  shell := detect_shell()

  emsdk_normalized: string
  node_exe_normalized: string
  python_exe_normalized: string
  new_path: string

  if shell == "bash" {
    // convert Windows paths to Unix format for GitBash
    emsdk_unix := windows_to_unix_path(emsdk_dir)
    node_exe_normalized = windows_to_unix_path(node_exe)
    python_exe_normalized = windows_to_unix_path(python_exe)
    emsdk_normalized = emsdk_unix

    // use colon separator for Unix PATH
    emsdk_paths := fmt.tprintf("%s/upstream/emscripten:%s", emsdk_unix, emsdk_unix)
    new_path = fmt.tprintf("%s:%s", emsdk_paths, current_path)
  } else {
    // Keep Windows paths for PowerShell/CMD
    emsdk_normalized, _ = strings.replace_all(emsdk_dir, "\\", "/")
    node_exe_normalized = node_exe
    python_exe_normalized = python_exe

    // use semicolon separator for Windows PATH
    emsdk_paths := fmt.tprintf("%s/upstream/emscripten;%s", emsdk_dir, emsdk_dir)
    new_path = fmt.tprintf("%s;%s", emsdk_paths, current_path)
  }

  env_vars := []string{
    fmt.tprintf("PATH=%s", new_path),
    fmt.tprintf("EMSDK=%s", emsdk_normalized),
    fmt.tprintf("EMSDK_NODE=%s", node_exe_normalized),
    fmt.tprintf("EMSDK_PYTHON=%s", python_exe_normalized),
  }

  // use the os2 package for proper process execution with environment
  cmd_args: []string
  if program == "emcc" {
    // use appropriate emcc binary for shell type
    if shell == "bash" {
      emcc_path := fmt.tprintf("%s/upstream/emscripten/emcc", windows_to_unix_path(emsdk_dir))
      cmd_args = make([]string, len(args) + 1)
      cmd_args[0] = emcc_path
    } else {
      cmd_args = make([]string, len(args) + 1)
      cmd_args[0] = fmt.tprintf("%s/upstream/emscripten/emcc.bat", emsdk_dir)
    }
    copy(cmd_args[1:], args)
  } else {
    cmd_args = make([]string, len(args) + 1)
    cmd_args[0] = program
    copy(cmd_args[1:], args)
  }

  process_desc := os2.Process_Desc{
    command = cmd_args,
    stdout = os2.stdout,
    stderr = os2.stderr,
    stdin = os2.stdin,
    env = env_vars,
  }

  process, start_err := os2.process_start(process_desc)
  if start_err != nil {
    print_error(fmt.tprintf("Failed to start process: %v", start_err))
    return false
  }
  defer {
    close_err := os2.process_close(process)
    if close_err != nil {
      // ignoring close errors for now
    }
  }

  state, wait_err := os2.process_wait(process)
  if wait_err != nil {
    print_error(fmt.tprintf("Failed to wait for process: %v", wait_err))
    return false
  }

  return state.exit_code == 0
}

build_game_dll :: proc(out_dir: string, pdbs_dir: string, source_dir: string, is_watch_mode: bool) -> bool {
  // get next PDB number (simple implementation for now)
  pdb_number := get_next_pdb_number(pdbs_dir)
  pdb_path := fmt.tprintf("%s/game_%d.pdb", pdbs_dir, pdb_number)

  if is_watch_mode {
    print_rebuild(fmt.tprintf("Rebuilding game.dll (PDB #%d)...", pdb_number))
  } else {
    print_info("Building game.dll...")
  }

  // build the actual command
  build_args := []string{
    "build", source_dir,
    "-strict-style", "-vet", "-debug",
    "-define:RAYLIB_SHARED=true",
    "-define:ODIN_DEBUG=true",
    "-build-mode:dll",
    fmt.tprintf("-out:%s/game_tmp.dll", out_dir),
    fmt.tprintf("-pdb-name:%s", pdb_path),
  }

  // execute the build command
  if !run_command("odin", build_args) {
    print_error("Build failed!")
    return false
  }

  // atomic move to prevent loading incomplete DLL
  old_path := fmt.tprintf("%s/game_tmp.dll", out_dir)
  new_path := fmt.tprintf("%s/game.dll", out_dir)

  if os.exists(new_path) {
    os.remove(new_path)
  }

  rename_ok := os.rename(old_path, new_path)
  if rename_ok != os.ERROR_NONE {
    print_error("Failed to move DLL to final location")
    return false
  }

  if is_watch_mode {
    print_success("Hot reload complete!")
  } else {
    print_success("Game DLL built successfully!")
  }

  return true
}

build_game_exe :: proc(out_dir: string, exe_name: string) -> bool {
  print_info(fmt.tprintf("Building %s...", exe_name))

  build_args := []string{
    "build", "src/main_hot_reload",
    "-strict-style", "-vet", "-debug",
    fmt.tprintf("-out:%s", exe_name),
    fmt.tprintf("-pdb-name:%s/main_hot_reload.pdb", out_dir),
  }

  if !run_command("odin", build_args) {
    print_error(fmt.tprintf("Failed to build %s", exe_name))
    return false
  }

  print_success(fmt.tprintf("%s built successfully!", exe_name))
  return true
}

get_next_pdb_number :: proc(pdbs_dir: string) -> int {
  // simple implementation - read pdb_number file or start at 1
  pdb_file := fmt.tprintf("%s/pdb_number", pdbs_dir)

  if data, ok := os.read_entire_file(pdb_file); ok {
    defer delete(data)

    if number, parse_ok := strconv.parse_int(strings.trim_space(string(data))); parse_ok {
      next_number := number + 1

      // write next number back
      next_str := fmt.tprintf("%d", next_number)
      os.write_entire_file(pdb_file, transmute([]byte)next_str)

      return next_number
    }
  }

  // first time - start at 1
  initial_str := "1"
  os.write_entire_file(pdb_file, transmute([]byte)initial_str)
  return 1
}

// check if the game process is running
is_game_running :: proc(exe_name: string) -> bool {
  when ODIN_OS == .Windows {
    // Use Windows ToolHelp32 API to enumerate processes - pure Odin!
    snap := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPPROCESS, 0)
    if snap == win.INVALID_HANDLE_VALUE {
      return false
    }
    defer win.CloseHandle(snap)

    entry := win.PROCESSENTRY32W{dwSize = size_of(win.PROCESSENTRY32W)}
    status := win.Process32FirstW(snap, &entry)

    exe_name_lower := strings.to_lower(exe_name, context.temp_allocator)

    for status {
      // convert WCHAR array to UTF-8 string using Windows utils
      exe_file_utf16 := entry.szExeFile[:]
      exe_file_utf8, err := win.utf16_to_utf8_alloc(exe_file_utf16, context.temp_allocator)
      if err == nil {
        exe_file_lower := strings.to_lower(exe_file_utf8, context.temp_allocator)
        if exe_file_lower == exe_name_lower {
          return true
        }
      }

      status = win.Process32NextW(snap, &entry)
    }
    return false
  } else {
    // for Unix systems, use pgrep???
    process_name := strings.trim_suffix(exe_name, ".exe")
    cmd_args := []string{"pgrep", process_name}

    process_desc := os2.Process_Desc{
      command = cmd_args,
      stdout = os2.stdout,
      stderr = os2.stderr,
    }

    process, start_err := os2.process_start(process_desc)
    if start_err != nil {
      return false
    }
    defer {
      close_err := os2.process_close(process)
      if close_err != nil {
        // ignore close errors for now
      }
    }

    state, wait_err := os2.process_wait(process)
    return wait_err == nil && state.exit_code == 0
  }
}

// start the game process
start_game :: proc(exe_name: string) -> bool {
  print_info(fmt.tprintf("Starting %s...", exe_name))

  when ODIN_OS == .Windows {
    // use cmd /c start to launch the game in a new process
    cmd_args := []string{"cmd", "/c", "start", "/B", exe_name}
  } else {
    cmd_args := []string{fmt.tprintf("./%s", exe_name), "&"}
  }

  process_desc := os2.Process_Desc{
    command = cmd_args,
    stdout = os2.stdout,
    stderr = os2.stderr,
  }

  process, start_err := os2.process_start(process_desc)
  if start_err != nil {
    print_error(fmt.tprintf("Failed to start game: %v", start_err))
    return false
  }
  defer {
    close_err := os2.process_close(process)
    if close_err != nil {
      // ignore close errors for background process
    }
  }

  // for cmd /c start, we don't need to wait, it returns immediately
  print_success("Game started!")
  return true
}

// get the last modification time of a file
get_file_mod_time :: proc(filepath: string) -> time.Time {
  file_info, err := os.stat(filepath)
  if err != os.ERROR_NONE {
    return {}
  }
  return file_info.modification_time
}

// store file timestamps for change detection
File_Info :: struct {
  path: string,
  mod_time: time.Time,
}

// get all .odin files in a directory and their modification times
get_source_files :: proc(source_dir: string, allocator := context.allocator) -> []File_Info {
  files := make([dynamic]File_Info, allocator)
  get_source_files_recursive(source_dir, &files)
  return files[:]
}

// clean up file paths from File_Info array
cleanup_file_info :: proc(files: []File_Info) {
  for file in files {
    delete(file.path)
  }
}

get_source_files_recursive :: proc(dir: string, files: ^[dynamic]File_Info) {
  handle, err := os.open(dir)
  if err != os.ERROR_NONE {
    return
  }
  defer os.close(handle)

  dir_entries, read_err := os.read_dir(handle, -1)
  if read_err != os.ERROR_NONE {
    return
  }
  defer delete(dir_entries)

  for entry in dir_entries {
    when ODIN_OS == .Windows {
      full_path := fmt.tprintf("%s\\%s", dir, entry.name)
    } else {
      full_path := fmt.tprintf("%s/%s", dir, entry.name)
    }

    // skip hidden files, build dirs, and temp files
    if strings.has_prefix(entry.name, ".") ||
      strings.has_prefix(entry.name, "build") ||
      strings.has_suffix(entry.name, ".tmp") ||
      strings.has_suffix(entry.name, "~") {
      continue
    }

    if entry.is_dir {
      get_source_files_recursive(full_path, files)
    } else if strings.has_suffix(entry.name, ".odin") {
      mod_time := get_file_mod_time(full_path)
      // store the normalized path for consistent comparison
      normalized_path := strings.clone(full_path, context.allocator)
      append(files, File_Info{path = normalized_path, mod_time = mod_time})
    }
  }
}

// Get all shader files (.vert/.frag) in a directory recursively
get_shader_files_recursive :: proc(dir: string, files: ^[dynamic]File_Info) {
  handle, err := os.open(dir)
  if err != os.ERROR_NONE {
    return
  }
  defer os.close(handle)

  dir_entries, read_err := os.read_dir(handle, -1)
  if read_err != os.ERROR_NONE {
    return
  }
  defer delete(dir_entries)

  for entry in dir_entries {
    when ODIN_OS == .Windows {
      full_path := fmt.tprintf("%s\\%s", dir, entry.name)
    } else {
      full_path := fmt.tprintf("%s/%s", dir, entry.name)
    }

    // skip hidden files, build dirs, and temp files
    if strings.has_prefix(entry.name, ".") ||
      strings.has_prefix(entry.name, "build") ||
      strings.has_suffix(entry.name, ".tmp") ||
      strings.has_suffix(entry.name, "~") {
      continue
    }

    if entry.is_dir {
      get_shader_files_recursive(full_path, files)
    } else if strings.has_suffix(entry.name, ".vert") || strings.has_suffix(entry.name, ".frag") {
      mod_time := get_file_mod_time(full_path)
      normalized_path := strings.clone(full_path, context.allocator)
      append(files, File_Info{path = normalized_path, mod_time = mod_time})
    }
  }
}

// check if any source files have been modified since the stored timestamps
check_files_changed :: proc(current_files: []File_Info, stored_files: []File_Info) -> (bool, string) {
  // first check if file count changed
  if len(current_files) != len(stored_files) {
      return true, "File count changed"
  }

  // create a map of stored files for quick lookup
  stored_map := make(map[string]time.Time)
  defer delete(stored_map)

  for stored in stored_files {
    stored_map[stored.path] = stored.mod_time
  }

  // check each current file against stored timestamps
  for current in current_files {
    if stored_time, exists := stored_map[current.path]; exists {
      // Convert to nanoseconds for comparison since time.diff returns Duration
      stored_ns := time.to_unix_nanoseconds(stored_time)
      current_ns := time.to_unix_nanoseconds(current.mod_time)

      if current_ns > stored_ns {  // Current is newer than stored
        return true, current.path
      }
    } else {
      return true, fmt.tprintf("New file: %s", current.path)
    }
  }

  return false, ""
}

// main file watching loop
start_file_watcher :: proc(out_dir: string, pdbs_dir: string, source_dir: string, exe_name: string) {
  print_info("Starting file watcher...")
  print_info("Press Ctrl+C to stop watching")

  // start the game first
  if !is_game_running(exe_name) {
    if !start_game(exe_name) {
      print_error("Failed to start game, exiting...")
      return
    }

    // give the game time to start
    time.sleep(3 * time.Second)
  } else {
    print_info("Game is already running")
  }

  print_success("File watcher started!")
  print_info("Monitoring source files for changes...")

  // get initial file timestamps from both source directory and shaders directory
  stored_files := make([dynamic]File_Info)
  defer {
    for file in stored_files {
      delete(file.path)
    }
    delete(stored_files)
  }

  // Monitor source directory (.odin files)
  get_source_files_recursive(source_dir, &stored_files)

  // Monitor shaders directory (.vert/.frag files) if it exists
  if os.is_dir("shaders") {
    get_shader_files_recursive("shaders", &stored_files)
  }

  final_files := stored_files[:]

  print_info(fmt.tprintf("Watching %d source files (.odin + shaders) in %s + shaders/", len(final_files), source_dir))

  // debug: print first few files being watched
  print_info("Sample files being watched:")
  for i in 0..<min(5, len(final_files)) {
    file := final_files[i]
    print_info(fmt.tprintf("  %s (modified: %v)", file.path, file.mod_time))
  }

  debounce_duration := 500 * time.Millisecond
  last_change_time := time.Time{}
  pending_build := false
  changed_file := ""

  // main watch loop
  for {
    // poll with a reasonable sleep interval before checking again
    time.sleep(500 * time.Millisecond)

    // check if the game is still running
    if !is_game_running(exe_name) {
      print_warning("\nGame process has ended. Stopping file watcher...")
      break
    }

    // check for file modifications - collect files from both directories
    current_files := make([dynamic]File_Info)
    defer {
      for file in current_files {
        delete(file.path)
      }
      delete(current_files)
    }

    // Monitor source directory (.odin files)
    get_source_files_recursive(source_dir, &current_files)

    // Monitor shaders directory (.vert/.frag files) if it exists
    if os.is_dir("shaders") {
      get_shader_files_recursive("shaders", &current_files)
    }

    if files_changed, change_info := check_files_changed(current_files[:], final_files); files_changed {
      if !pending_build {
        // first time detecting this change
        pending_build = true
        last_change_time = time.now()
        changed_file = change_info
        print_info(fmt.tprintf("Files changed: %s - waiting for debounce...", change_info))
      }
    }

    // if we have pending changes and debounce period has passed, trigger build
    if pending_build && time.diff(last_change_time, time.now()) > debounce_duration {
      print_rebuild(fmt.tprintf("Debounce elapsed, rebuilding due to: %s", changed_file))

      if build_game_dll(out_dir, pdbs_dir, source_dir, true) {
        // update stored file timestamps only after successful build
        for file in stored_files {
          delete(file.path)
        }
        clear(&stored_files)

        // Refresh file list
        get_source_files_recursive(source_dir, &stored_files)
        if os.is_dir("shaders") {
          get_shader_files_recursive("shaders", &stored_files)
        }
        final_files = stored_files[:]

        print_success("Hot reload complete!")
      } else {
        print_error("Hot reload build failed!")
      }

      // reset pending build state
      pending_build = false
      changed_file = ""
    }
  }

  print_success("File watching stopped.")
}

// inject favicon into web HTML file
inject_favicon_into_web_html :: proc(html_path: string) {
  // read icon file
  icon_data, icon_ok := os.read_entire_file("assets/tri.png")
  if !icon_ok {
    print_warning("Icon file not found: assets/tri.png - favicon will not be injected")
    return
  }
  defer delete(icon_data)

  // read HTML file
  html_data, html_ok := os.read_entire_file(html_path)
  if !html_ok {
    print_error(fmt.tprintf("Failed to read HTML file: %s", html_path))
    return
  }
  defer delete(html_data)

  // encode icon to base64
  icon_base64 := base64.encode(icon_data)
  defer delete(icon_base64)

  // inject favicon after viewport meta tag
  html_content := string(html_data)
  favicon_links := fmt.tprintf(`
	<link rel="icon" type="image/png" href="data:image/png;base64,%s">
	<meta name="theme-color" content="#000000">`, icon_base64)

  modified_html, replaced := strings.replace_all(html_content,
    `<meta name="viewport" content="width=device-width">`,
    fmt.tprintf(`<meta name="viewport" content="width=device-width">%s`, favicon_links))

  if !replaced {
    print_warning("Could not find viewport meta tag to inject favicon")
    return
  }

  // write back modified HTML
  if !os.write_entire_file(html_path, transmute([]byte)modified_html) {
    print_error(fmt.tprintf("Failed to write modified HTML file: %s", html_path))
    return
  }

  print_success("Favicon injected successfully")
}
