#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Odin Hot Reload Build Script with File Watching
.DESCRIPTION
  Builds the hot reload version of the game with optional file watching.
  When watch mode is enabled, monitors source files and automatically
  rebuilds on changes.
.PARAMETER Watch
  Enable file watching mode to automatically rebuild on source file changes
.PARAMETER Run
  Start the game after building (only when not in watch mode)
.PARAMETER BuildOnly
  Build only, don't watch or run the game
.EXAMPLE
  .\build_hot_reload.ps1
  Build and watch for file changes (default)
.EXAMPLE
  .\build_hot_reload.ps1 -Watch
  Build and watch for file changes (explicit)
.EXAMPLE
  .\build_hot_reload.ps1 -Run
  Build and start the game once
.EXAMPLE
  .\build_hot_reload.ps1 -BuildOnly
  Build only and exit
#>

param(
  [switch]$Watch,
  [switch]$Run,
  [switch]$BuildOnly
)

# If no parameters are provided, default to Watch mode
if (-not $Watch -and -not $Run -and -not $BuildOnly) {
  $Watch = $true
}

# Configuration
$OUT_DIR = "build\hot_reload"
$GAME_PDBS_DIR = "$OUT_DIR\game_pdbs"
$EXE = "game_hot_reload.exe"
$SOURCE_DIR = "source"
$DEBOUNCE_MS = 500  # Debounce time to prevent rapid rebuilds (0.5 seconds)

# Colors for better output
$script:Colors = @{
  Success = "Green"
  Warning = "Yellow"
  Error = "Red"
  Info = "Cyan"
  Debug = "Gray"
}

function Write-ColorOutput {
  param(
    [string]$Message,
    [string]$Color = "White"
  )
  Write-Host $Message -ForegroundColor $Color
}

function Test-GameRunning {
  try {
    $process = Get-Process -Name ($EXE -replace '\.exe$', '') -ErrorAction SilentlyContinue
    return $null -ne $process
  }
  catch {
    return $false
  }
}

function Initialize-BuildDirectories {
  if (-not (Test-Path $OUT_DIR)) {
    New-Item -ItemType Directory -Path $OUT_DIR -Force | Out-Null
  }

  $gameRunning = Test-GameRunning

  if (-not $gameRunning) {
    Write-ColorOutput "Game not running, cleaning build directory..." $Colors.Info

    # Clean the output directory
    if (Test-Path $OUT_DIR) {
      Remove-Item "$OUT_DIR\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create PDB directory and reset counter
    if (-not (Test-Path $GAME_PDBS_DIR)) {
      New-Item -ItemType Directory -Path $GAME_PDBS_DIR -Force | Out-Null
    }
    Set-Content -Path "$GAME_PDBS_DIR\pdb_number" -Value "0"
  }

  return $gameRunning
}

function Get-NextPdbNumber {
  $pdbNumberFile = "$GAME_PDBS_DIR\pdb_number"

  if (Test-Path $pdbNumberFile) {
    $currentNumber = [int](Get-Content $pdbNumberFile -ErrorAction SilentlyContinue)
  } else {
    $currentNumber = 0
  }

  $nextNumber = $currentNumber + 1
  Set-Content -Path $pdbNumberFile -Value $nextNumber.ToString()
  return $nextNumber
}

function Build-GameDll {
  param([bool]$IsWatchMode = $false)

  try {
    $pdbNumber = Get-NextPdbNumber
    $pdbPath = "$GAME_PDBS_DIR\game_$pdbNumber.pdb"

    if ($IsWatchMode) {
      Write-ColorOutput "🔄 Rebuilding game.dll (PDB #$pdbNumber)..." $Colors.Info
    } else {
      Write-ColorOutput "Building game.dll..." $Colors.Info
    }

    # Build the game DLL
    $buildArgs = @(
      "build", $SOURCE_DIR,
      "-strict-style", "-vet", "-debug",
      "-define:RAYLIB_SHARED=true",
      "-build-mode:dll",
      "-out:$OUT_DIR/game_tmp.dll",
      "-pdb-name:$pdbPath"
    )

    # Use & operator for direct execution instead of Start-Process to avoid hanging
    $output = & odin @buildArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
      Write-ColorOutput "❌ Build failed!" $Colors.Error
      if ($output) {
        Write-ColorOutput ($output | Out-String) $Colors.Error
      }
      return $false
    }

    # Atomic move to prevent loading incomplete DLL (like the shell script)
    Move-Item -Path "$OUT_DIR/game_tmp.dll" -Destination "$OUT_DIR/game.dll" -Force

    if ($IsWatchMode) {
      Write-ColorOutput "✅ Hot reload complete!" $Colors.Success
    } else {
      Write-ColorOutput "✅ Game DLL built successfully!" $Colors.Success
    }
    return $true
  }
  catch {
    Write-ColorOutput "❌ Build error: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Build-GameExe {
  Write-ColorOutput "Building $EXE..." $Colors.Info

  try {
    $buildArgs = @(
      "build", "source\main_hot_reload",
      "-strict-style", "-vet", "-debug",
      "-out:$EXE",
      "-pdb-name:$OUT_DIR\main_hot_reload.pdb"
    )

    # Use & operator for direct execution instead of Start-Process
    $output = & odin @buildArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
      Write-ColorOutput "❌ Failed to build $EXE" $Colors.Error
      if ($output) {
        Write-ColorOutput ($output | Out-String) $Colors.Error
      }
      return $false
    }

    Write-ColorOutput "✅ $EXE built successfully!" $Colors.Success
    return $true
  }
  catch {
    Write-ColorOutput "❌ Build error: $($_.Exception.Message)" $Colors.Error
    return $false
  }
}

function Copy-RaylibDll {
  if (-not (Test-Path "raylib.dll")) {
    try {
      $odinRoot = & odin root
      $raylibSource = "$odinRoot\vendor\raylib\windows\raylib.dll"

      if (Test-Path $raylibSource) {
        Write-ColorOutput "Copying raylib.dll from Odin installation..." $Colors.Info
        Copy-Item $raylibSource -Destination "." -Force
        return $true
      } else {
        Write-ColorOutput "❌ raylib.dll not found. Please copy it from your Odin installation." $Colors.Error
        return $false
      }
    }
    catch {
      Write-ColorOutput "❌ Failed to copy raylib.dll: $($_.Exception.Message)" $Colors.Error
      return $false
    }
  }
  return $true
}

function Start-FileWatcher {
  Write-ColorOutput "🔍 Starting file watcher on '$SOURCE_DIR' directory..." $Colors.Info
  Write-ColorOutput "Press Ctrl+C to stop watching" $Colors.Warning

  # Create the file watcher
  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = (Resolve-Path $SOURCE_DIR).Path
  $watcher.Filter = "*.odin"
  $watcher.IncludeSubdirectories = $true
  $watcher.EnableRaisingEvents = $true

  Write-ColorOutput "👀 Watching: $($watcher.Path)" $Colors.Debug
  Write-ColorOutput "📁 Filter: $($watcher.Filter)" $Colors.Debug

  # Debouncing variables
  $script:lastEventTime = [DateTime]::MinValue
  $script:pendingBuild = $false

  # Event handler for file changes
  $action = {
    $fileName = $Event.SourceEventArgs.Name
    $changeType = $Event.SourceEventArgs.ChangeType

    Write-Host "📝 File event detected: $fileName ($changeType)" -ForegroundColor Yellow

    # Only respond to Changed events (saves)
    if ($changeType -eq 'Changed') {
      $now = Get-Date
      $script:lastEventTime = $now
      $script:pendingBuild = $true

      Write-Host "⏰ Scheduling rebuild in 500ms..." -ForegroundColor Cyan

      # Schedule a delayed build
      Start-Job -ScriptBlock {
        param($delayMs, $sourceDir, $outDir)
        Start-Sleep -Milliseconds $delayMs

        # Signal that we should build
        $triggerFile = "$outDir\build_trigger"
        Set-Content -Path $triggerFile -Value (Get-Date).ToString()
      } -ArgumentList 500, "source", "build\hot_reload" | Out-Null
    }
  }

  # Register the event
  $eventSubscription = Register-ObjectEvent -InputObject $watcher -EventName "Changed" -Action $action
  Write-ColorOutput "✅ File watcher registered successfully" $Colors.Success

  try {
    # Main watch loop
    while ($true) {
      Start-Sleep -Milliseconds 100

      # Check if the game is still running - exit gracefully if not
      if (-not (Test-GameRunning)) {
        Write-ColorOutput "`n🎮 Game process has ended. Stopping file watcher..." $Colors.Warning
        break
      }

      # Check for pending builds
      $triggerFile = "$OUT_DIR\build_trigger"
      if (Test-Path $triggerFile) {
        $timeSinceLastEvent = (Get-Date) - $script:lastEventTime

        # Only build if enough time has passed since the last file change
        if ($timeSinceLastEvent.TotalMilliseconds -ge $DEBOUNCE_MS) {
          Remove-Item $triggerFile -Force -ErrorAction SilentlyContinue
          $script:pendingBuild = $false

          Write-ColorOutput "🔄 Debounce period elapsed, starting rebuild..." $Colors.Info
          Build-GameDll -IsWatchMode $true
        }
      }

      # Clean up completed jobs
      Get-Job | Where-Object { $_.State -eq 'Completed' } | Remove-Job -Force
    }
  }
  catch [System.Management.Automation.HaltCommandException] {
    Write-ColorOutput "`n🛑 File watching stopped by user." $Colors.Warning
  }
  catch {
    Write-ColorOutput "❌ File watcher error: $($_.Exception.Message)" $Colors.Error
  }
  finally {
    # Cleanup
    Write-ColorOutput "🧹 Cleaning up file watcher..." $Colors.Info
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    if ($eventSubscription) {
      Unregister-Event -SourceIdentifier $eventSubscription.Name -ErrorAction SilentlyContinue
    }

    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

    if (Test-Path "$OUT_DIR\build_trigger") {
      Remove-Item "$OUT_DIR\build_trigger" -Force -ErrorAction SilentlyContinue
    }
    Write-ColorOutput "✅ Cleanup complete" $Colors.Success
  }
}

function Main {
  Write-ColorOutput "🎮 Odin Hot Reload Build Script" $Colors.Info
  Write-ColorOutput "================================" $Colors.Info

  # Platform detection (for consistency with shell script)
  Write-ColorOutput "Platform detected: windows" $Colors.Debug

  # Initialize build environment
  $gameRunning = Initialize-BuildDirectories

  # Build the game DLL
  if (-not (Build-GameDll)) {
    exit 1
  }

  # If game is already running, we're done (hot reload case)
  if ($gameRunning) {
    if ($Watch) {
      Start-FileWatcher
    } else {
      Write-ColorOutput "🔥 Hot reloading..." $Colors.Success
    }
    return
  }

  # Build the executable
  if (-not (Build-GameExe)) {
    exit 1
  }

  # Copy raylib.dll if needed
  if (-not (Copy-RaylibDll)) {
    exit 1
  }

  # Handle run/watch modes
  if ($Watch) {
    # Always start the game if it's not running when in watch mode
    Write-ColorOutput "Starting $EXE..." $Colors.Info
    Start-Process -FilePath ".\$EXE" -NoNewWindow
    Start-Sleep -Seconds 2  # Give the game time to start
    Start-FileWatcher
  }
  elseif ($Run) {
    Write-ColorOutput "Starting $EXE..." $Colors.Info
    Start-Process -FilePath ".\$EXE"
  }
  # If $BuildOnly is true, we just build and exit without starting anything

  Write-ColorOutput "🎉 Build complete!" $Colors.Success
}

# Run the main function
Main
