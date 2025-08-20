package docs

import "core:fmt"
import "core:os"
import "core:strings"
import "core:path/filepath"
import "core:time"
import "core:c/libc"

// Colors for terminal output
ANSI_RESET     :: "\033[0m"
ANSI_BOLD      :: "\033[1m"
ANSI_RED       :: "\033[31m"
ANSI_GREEN     :: "\033[32m"
ANSI_YELLOW    :: "\033[33m"
ANSI_BLUE      :: "\033[34m"
ANSI_MAGENTA   :: "\033[35m"
ANSI_CYAN      :: "\033[36m"

print_step :: proc(step: string) {
	fmt.printf("%s==> %s%s%s\n", ANSI_CYAN, ANSI_BOLD, step, ANSI_RESET)
}

print_success :: proc(msg: string) {
	fmt.printf("%s✓%s %s\n", ANSI_GREEN, ANSI_RESET, msg)
}

print_warning :: proc(msg: string) {
	fmt.printf("%s⚠%s %s\n", ANSI_YELLOW, ANSI_RESET, msg)
}

print_error :: proc(msg: string) {
	fmt.printf("%s✗%s %s\n", ANSI_RED, ANSI_RESET, msg)
}

// Repository configuration
Repo :: struct {
	name:        string,
	url:         string,
	target_dir:  string,
	description: string,
}

repos := []Repo{
	{
		name = "odin-lang.org",
		url = "https://github.com/odin-lang/odin-lang.org",
		target_dir = "website",
		description = "Official Odin documentation website",
	},
	{
		name = "examples",
		url = "https://github.com/odin-lang/examples",
		target_dir = "examples",
		description = "Official Odin code examples",
	},
	{
		name = "Odin",
		url = "https://github.com/odin-lang/Odin",
		target_dir = "source",
		description = "Odin language source code",
	},
}

// Simple command execution - leveraging existing build system approach
execute_command :: proc(command: string) -> bool {
	fmt.printf("  Running: %s\n", command)

	// Use the same approach as our build system
	when ODIN_OS == .Windows {
		// Use cmd /c to run the command and return to shell
		full_cmd := fmt.aprintf("cmd /c \"%s\"", command)
		defer delete(full_cmd)

		// Simple system call using libc - similar to build.odin approach
		result := libc.system(strings.clone_to_cstring(full_cmd, context.temp_allocator))
		return result == 0
	} else {
		result := libc.system(strings.clone_to_cstring(command, context.temp_allocator))
		return result == 0
	}
}

check_git_available :: proc() -> bool {
	print_step("Checking if git is available")

	if execute_command("git --version") {
		print_success("Git is available")
		return true
	} else {
		print_error("Git is not available. Please install git and add it to PATH")
		return false
	}
}

ensure_odin_directory :: proc() -> bool {
	// Get the directory where this script is located
	script_dir := filepath.dir(#file)
	odin_dir := filepath.join({script_dir, "odin"})

	print_step(fmt.aprintf("Ensuring odin directory exists: %s", odin_dir))

	if !os.exists(odin_dir) {
		if err := os.make_directory(odin_dir); err != os.ERROR_NONE {
			print_error(fmt.aprintf("Failed to create odin directory: %v", err))
			return false
		}
	}

	print_success(fmt.aprintf("Directory ready: %s", odin_dir))
	return true
}

clone_or_update_repo :: proc(repo: Repo) -> bool {
	// Get the directory where this script is located
	script_dir := filepath.dir(#file)
	target_path := filepath.join({script_dir, "odin", repo.target_dir})

	print_step(fmt.aprintf("Processing %s (%s)", repo.name, repo.description))

	// Check if directory exists and has .git
	git_dir := filepath.join({target_path, ".git"})
	if os.exists(git_dir) && os.is_dir(git_dir) {
		// Repository exists, update it
		print_step(fmt.aprintf("Updating existing repository: %s", target_path))

		// Change to directory and fetch
		git_fetch := fmt.aprintf("cd \"%s\" && git fetch --all --prune", target_path)
		defer delete(git_fetch)

		if !execute_command(git_fetch) {
			print_error("Failed to fetch latest changes")
			return false
		}

		// Try to reset to origin/main, fallback to origin/master
		branch_reset_success := false
		branches := []string{"origin/main", "origin/master"}
		for branch in branches {
			reset_cmd := fmt.aprintf("cd \"%s\" && git reset --hard %s", target_path, branch)
			defer delete(reset_cmd)

			if execute_command(reset_cmd) {
				branch_reset_success = true
				break
			}
		}

		if !branch_reset_success {
			print_warning("Could not reset to origin/main or origin/master, trying pull")
			pull_cmd := fmt.aprintf("cd \"%s\" && git pull", target_path)
			defer delete(pull_cmd)

			if !execute_command(pull_cmd) {
				print_error("Failed to update repository")
				return false
			}
		}

		print_success(fmt.aprintf("Updated: %s", repo.name))
	} else {
		// Repository doesn't exist, clone it
		print_step(fmt.aprintf("Cloning new repository: %s", repo.url))

		// Remove target directory if it exists but isn't a git repo
		if os.exists(target_path) {
			print_warning(fmt.aprintf("Directory exists but is not a git repo: %s", target_path))
			print_warning("Please manually remove it and run the script again")
			return false
		}

		// Create parent directory if needed
		parent_dir := filepath.dir(target_path)
		if !os.exists(parent_dir) {
			if err := os.make_directory(parent_dir); err != os.ERROR_NONE {
				print_error(fmt.aprintf("Failed to create parent directory: %v", err))
				return false
			}
		}

		// Clone the repository with depth 1 for faster cloning
		clone_cmd := fmt.aprintf("git clone --depth 1 \"%s\" \"%s\"", repo.url, target_path)
		defer delete(clone_cmd)

		if !execute_command(clone_cmd) {
			print_error(fmt.aprintf("Failed to clone %s", repo.name))
			return false
		}

		print_success(fmt.aprintf("Cloned: %s", repo.name))
	}

	return true
}

create_readme :: proc() -> bool {
	// Get the directory where this script is located
	script_dir := filepath.dir(#file)
	readme_path := filepath.join({script_dir, "odin", "README.md"})

	print_step("Creating documentation README")

	readme_content := `# Odin Documentation Archive

This directory contains local copies of official Odin language resources for offline development and AI assistance.

## Contents

### website/
Official Odin documentation website source
- **Source**: https://github.com/odin-lang/odin-lang.org
- **Contains**: Website source, documentation pages, guides
- **Usage**: Reference for language documentation and tutorials

### examples/
Official Odin code examples
- **Source**: https://github.com/odin-lang/examples
- **Contains**: Example programs, best practices, package usage
- **Usage**: Learn idiomatic Odin coding patterns

### source/
Odin language source code
- **Source**: https://github.com/odin-lang/Odin
- **Contains**: Compiler source, core library, vendor packages
- **Usage**: Reference for core/vendor package APIs and implementation details

## Usage

This documentation is automatically updated by running:
` + "`" + `
odin run docs/update_odin_docs.odin
` + "`" + `

The script will clone repositories initially and update them on subsequent runs.

## AI Development Workflow

These resources enable AI assistants to:
1. Reference current Odin language APIs and syntax
2. Check cross-platform compatibility of core library functions
3. Find implementation examples for specific tasks
4. Understand best practices and idiomatic code patterns
5. Access complete package documentation offline

## Last Updated

Generated automatically by docs/update_odin_docs.odin script.
`

	if !os.write_entire_file(readme_path, transmute([]u8)readme_content) {
		print_error("Failed to create README")
		return false
	}

	print_success("Created documentation README")
	return true
}

print_summary :: proc() {
	fmt.printf("\n%s%s=== Odin Documentation Archive Summary ===%s\n", ANSI_BOLD, ANSI_CYAN, ANSI_RESET)

	script_dir := filepath.dir(#file)

	for repo in repos {
		target_path := filepath.join({script_dir, "odin", repo.target_dir})
		if os.exists(target_path) && os.is_dir(target_path) {
			print_success(fmt.aprintf("%-12s: %s", repo.target_dir, repo.description))
		} else {
			print_error(fmt.aprintf("%-12s: MISSING", repo.target_dir))
		}
	}

	fmt.printf("\n%sLocation%s: docs/odin/\n", ANSI_BOLD, ANSI_RESET)
	fmt.printf("%sUsage%s: Reference these directories for complete Odin language information\n", ANSI_BOLD, ANSI_RESET)
	fmt.printf("%sAI Access%s: AI assistants can now reference current Odin APIs and examples\n", ANSI_BOLD, ANSI_RESET)
	fmt.printf("\nTo update: %sodin run docs/update_odin_docs.odin -file%s\n", ANSI_CYAN, ANSI_RESET)
}

main :: proc() {
	fmt.printf("%s%sOdin Documentation Updater%s\n", ANSI_BOLD, ANSI_MAGENTA, ANSI_RESET)
	fmt.printf("Maintaining local copies of Odin language resources\n\n")

	start_time := time.now()

	// Check prerequisites
	if !check_git_available() {
		os.exit(1)
	}

	// Ensure directory structure
	if !ensure_odin_directory() {
		os.exit(1)
	}

	// Process each repository
	success := true
	for repo in repos {
		if !clone_or_update_repo(repo) {
			success = false
		}
		fmt.println()
	}

	// Create documentation README
	if !create_readme() {
		success = false
	}

	elapsed := time.diff(start_time, time.now())

	if success {
		print_success(fmt.aprintf("All repositories updated successfully in %v", elapsed))
		print_summary()
	} else {
		print_error("Some operations failed")
		os.exit(1)
	}
}
