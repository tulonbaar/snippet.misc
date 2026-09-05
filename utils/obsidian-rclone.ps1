#Requires -Version 5.1
<#
.SYNOPSIS
    Obsidian Vault Synchronization via rclone bisync with git-like workflow.

.DESCRIPTION
    Synchronizes a local Obsidian vault with Google Drive using rclone.
    Cloud (Google Drive) is the source of truth for conflict resolution.

    Workflow mirrors git: pull changes from cloud, work locally, push back.
    Local snapshots (compressed archives) are created before destructive
    operations, providing rollback capability similar to git commits.

    Designed for multi-device Obsidian usage without the Google Drive
    desktop app - controlled, on-demand sync via rclone.

.PARAMETER Action
    sync     - Bidirectional sync via rclone bisync (default)
    pull     - One-way cloud -> local (cloud overwrites local)
    push     - One-way local -> cloud (local overwrites cloud)
    status   - Show last sync info and connection status
    history  - List available local snapshots
    restore  - Restore local vault from a snapshot

.PARAMETER Resync
    Force bisync resync (rebuilds tracking state). Required on first run
    or when bisync state is corrupted. Cloud wins during resync.

.PARAMETER SnapshotId
    Snapshot timestamp for restore action (format: yyyyMMdd_HHmmss).

.PARAMETER DryRun
    Preview what would happen without making changes.

.PARAMETER NoSnapshot
    Skip snapshot creation before sync operations.

.EXAMPLE
    .\obsidian-rclone.ps1
    # Default bisync - syncs both directions, cloud wins conflicts

.EXAMPLE
    .\obsidian-rclone.ps1 -Action pull
    # Pull from cloud to local (like git pull)

.EXAMPLE
    .\obsidian-rclone.ps1 -Action push
    # Push local to cloud (like git push)

.EXAMPLE
    .\obsidian-rclone.ps1 -Action sync -Resync
    # Force resync (first run or state recovery)

.EXAMPLE
    .\obsidian-rclone.ps1 -Action restore -SnapshotId "20260822_143000"
    # Restore vault from a specific snapshot
#>

[CmdletBinding()]
param(
    [ValidateSet("sync", "pull", "push", "status", "history", "restore")]
    [string]$Action = "sync",

    [switch]$Resync,

    [string]$SnapshotId,

    [switch]$DryRun,

    [switch]$NoSnapshot
)

# ============================================================================
# Configuration
# ============================================================================

$Script:Config = @{
    LocalPath       = "C:\Users\lukasz.bartos\.obsidian"
    RemotePath      = "gdrive:00 - Central Workspace/obsidian"
    RemoteName      = "gdrive"
    LogDir          = "C:\ProgramData\log"
    RemoteLogPath   = "gdrive:00 - Central Workspace/log"
    SnapshotDir     = "C:\Users\lukasz.bartos\.obsidian-snapshots"
    MaxSnapshots    = 10
}

$Script:Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Script:LogFile   = Join-Path $Config.LogDir "obsidian-sync_$($Script:Timestamp).log"
$Script:ExitCode  = 0
$Script:SyncStats = @{
    StartTime    = Get-Date
    Action       = $Action
    FilesCount   = 0
    SnapshotPath = $null
    Success      = $false
}

# ============================================================================
# Logging
# ============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "OK", "STEP")]
        [string]$Level = "INFO"
    )

    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $tag   = "[$Level]".PadRight(7)
    $entry = "[$ts] $tag $Message"

    Add-Content -Path $Script:LogFile -Value $entry -ErrorAction SilentlyContinue

    $color = switch ($Level) {
        "INFO"  { "Cyan" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "OK"    { "Green" }
        "STEP"  { "Magenta" }
    }
    Write-Host $entry -ForegroundColor $color
}

function Write-Banner {
    param([string]$Title, [string]$Subtitle)

    $width = 62
    $line  = "=" * $width
    Write-Host ""
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "   $Title" -ForegroundColor White
    if ($Subtitle) {
        Write-Host "   $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host ""
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

function Test-RcloneAvailable {
    Write-Log "Checking rclone availability..." -Level STEP

    $rclone = Get-Command rclone -ErrorAction SilentlyContinue
    if (-not $rclone) {
        Write-Log "rclone is not installed or not in PATH. Aborting." -Level ERROR
        return $false
    }

    $version = (rclone version 2>&1 | Select-Object -First 1) -replace 'rclone ', ''
    Write-Log "rclone found: $version" -Level OK
    return $true
}

function Test-RemoteConnection {
    Write-Log "Verifying Google Drive connection..." -Level STEP

    # Check if remote is configured
    $remotes = rclone listremotes 2>&1
    if ($remotes -notcontains "$($Config.RemoteName):") {
        Write-Log "Remote '$($Config.RemoteName)' is not configured in rclone." -Level ERROR
        Write-Log "Run 'rclone config' to set up the remote." -Level INFO
        return $false
    }

    # Test actual connectivity by listing the root
    $testResult = rclone lsd "$($Config.RemoteName):" --max-depth 1 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Cannot connect to Google Drive. Check network and auth." -Level ERROR
        Write-Log "Error: $testResult" -Level ERROR
        return $false
    }

    Write-Log "Google Drive connection verified" -Level OK
    return $true
}

function Test-LocalPath {
    Write-Log "Checking local vault path..." -Level STEP

    if (-not (Test-Path $Config.LocalPath)) {
        if ($Action -eq "pull") {
            Write-Log "Local path does not exist. Will be created during pull." -Level WARN
            New-Item -ItemType Directory -Path $Config.LocalPath -Force | Out-Null
            Write-Log "Created: $($Config.LocalPath)" -Level OK
            return $true
        }
        Write-Log "Local vault not found: $($Config.LocalPath)" -Level ERROR
        Write-Log "Use '-Action pull' to download the vault from cloud first." -Level INFO
        return $false
    }

    $itemCount = (Get-ChildItem -Path $Config.LocalPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Log "Local vault found: $($Config.LocalPath) ($itemCount files)" -Level OK
    return $true
}

function Invoke-PreflightChecks {
    Write-Log "Running pre-flight checks..." -Level STEP
    Write-Log ("=" * 50) -Level INFO

    if (-not (Test-RcloneAvailable)) { return $false }
    if (-not (Test-RemoteConnection)) { return $false }
    if (-not (Test-LocalPath)) { return $false }

    Write-Log ("=" * 50) -Level INFO
    Write-Log "All pre-flight checks passed" -Level OK
    return $true
}

# ============================================================================
# Snapshots (local rollback points - like git commits)
# ============================================================================

function New-Snapshot {
    if ($NoSnapshot) {
        Write-Log "Snapshot creation skipped (-NoSnapshot)" -Level INFO
        return $null
    }

    Write-Log "Creating local snapshot (rollback point)..." -Level STEP

    # Ensure snapshot directory exists
    if (-not (Test-Path $Config.SnapshotDir)) {
        New-Item -ItemType Directory -Path $Config.SnapshotDir -Force | Out-Null
    }

    $snapshotName = "obsidian_$($Script:Timestamp).zip"
    $snapshotPath = Join-Path $Config.SnapshotDir $snapshotName

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Compress-Archive -Path "$($Config.LocalPath)\*" -DestinationPath $snapshotPath -CompressionLevel Fastest -Force
        $stopwatch.Stop()

        $sizeMB = [math]::Round((Get-Item $snapshotPath).Length / 1MB, 1)
        Write-Log "Snapshot created: $snapshotName ($($sizeMB) MB, $($stopwatch.Elapsed.TotalSeconds.ToString('F1'))s)" -Level OK

        $Script:SyncStats.SnapshotPath = $snapshotPath

        # Rotate old snapshots
        Remove-OldSnapshots
        return $snapshotPath
    }
    catch {
        Write-Log "Failed to create snapshot: $_" -Level ERROR
        Write-Log "Continuing without snapshot..." -Level WARN
        return $null
    }
}

function Remove-OldSnapshots {
    $snapshots = Get-ChildItem -Path $Config.SnapshotDir -Filter "obsidian_*.zip" |
        Sort-Object CreationTime -Descending

    if ($snapshots.Count -gt $Config.MaxSnapshots) {
        $toRemove = $snapshots | Select-Object -Skip $Config.MaxSnapshots
        foreach ($snap in $toRemove) {
            Remove-Item $snap.FullName -Force
            Write-Log "Rotated old snapshot: $($snap.Name)" -Level INFO
        }
    }
}

function Get-SnapshotHistory {
    if (-not (Test-Path $Config.SnapshotDir)) {
        Write-Log "No snapshots found. Snapshot directory does not exist." -Level WARN
        return
    }

    $snapshots = Get-ChildItem -Path $Config.SnapshotDir -Filter "obsidian_*.zip" |
        Sort-Object CreationTime -Descending

    if ($snapshots.Count -eq 0) {
        Write-Log "No snapshots found." -Level WARN
        return
    }

    Write-Banner "Snapshot History" "Local rollback points (newest first)"

    $index = 0
    foreach ($snap in $snapshots) {
        $index++
        $sizeMB = [math]::Round($snap.Length / 1MB, 1)
        $ts = $snap.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
        $id = ($snap.BaseName -replace 'obsidian_', '')

        $marker = if ($index -eq 1) { " (latest)" } else { "" }
        $fmt = '  [{0}] {1}  |  {2,7} MB  |  ID: {3}{4}'
        $line = $fmt -f $index, $ts, $sizeMB, $id, $marker
        $color = if ($index -eq 1) { "Green" } else { "Gray" }
        Write-Host $line -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Restore with: obsidian-rclone -Action restore -SnapshotId <ID>" -ForegroundColor DarkGray
    Write-Host "  Snapshots retained: $($snapshots.Count) / $($Config.MaxSnapshots)" -ForegroundColor DarkGray
    Write-Host ""
}

function Restore-Snapshot {
    if (-not $SnapshotId) {
        Write-Log "SnapshotId is required for restore. Use '-Action history' to list available snapshots." -Level ERROR
        $Script:ExitCode = 1
        return
    }

    $snapshotPath = Join-Path $Config.SnapshotDir "obsidian_$SnapshotId.zip"

    if (-not (Test-Path $snapshotPath)) {
        Write-Log "Snapshot not found: $snapshotPath" -Level ERROR
        Write-Log "Use '-Action history' to list available snapshots." -Level INFO
        $Script:ExitCode = 1
        return
    }

    Write-Log "Restoring from snapshot: $SnapshotId" -Level STEP

    if ($DryRun) {
        Write-Log "[DRY RUN] Would restore from: $snapshotPath" -Level INFO
        Write-Log "[DRY RUN] Target: $($Config.LocalPath)" -Level INFO
        return
    }

    # Create a safety snapshot of current state before restoring
    Write-Log "Creating safety snapshot of current state before restore..." -Level INFO
    $safetySnapshot = "obsidian_$($Script:Timestamp)_pre-restore.zip"
    $safetyPath = Join-Path $Config.SnapshotDir $safetySnapshot
    try {
        Compress-Archive -Path "$($Config.LocalPath)\*" -DestinationPath $safetyPath -CompressionLevel Fastest -Force
        Write-Log "Safety snapshot created: $safetySnapshot" -Level OK
    }
    catch {
        Write-Log "Failed to create safety snapshot: $_" -Level ERROR
        Write-Log "Aborting restore to prevent data loss." -Level ERROR
        $Script:ExitCode = 1
        return
    }

    # Clear local vault and extract snapshot
    try {
        Get-ChildItem -Path $Config.LocalPath -Recurse | Remove-Item -Recurse -Force
        Expand-Archive -Path $snapshotPath -DestinationPath $Config.LocalPath -Force
        Write-Log "Vault restored from snapshot: $SnapshotId" -Level OK
        Write-Log "Safety snapshot available: $safetySnapshot" -Level INFO
    }
    catch {
        Write-Log "Restore failed: $_" -Level ERROR
        Write-Log "Your pre-restore state is saved at: $safetyPath" -Level WARN
        $Script:ExitCode = 1
    }
}

# ============================================================================
# Sync Operations
# ============================================================================

function Invoke-Bisync {
    Write-Log "Starting bidirectional sync (bisync)..." -Level STEP
    Write-Log "  Local:  $($Config.LocalPath)" -Level INFO
    Write-Log "  Remote: $($Config.RemotePath)" -Level INFO
    Write-Log "  Conflict resolution: cloud wins (path2)" -Level INFO

    $rcloneArgs = @(
        "bisync"
        $Config.LocalPath
        $Config.RemotePath
        "--conflict-resolve", "path2"
        "--conflict-loser", "num"
        "--conflict-suffix", "conflict"
        "--resilient"
        "--recover"
        "--verbose"
        "--log-file", $Script:LogFile
    )

    if ($Resync) {
        $rcloneArgs += "--resync"
        $rcloneArgs += "--resync-mode", "path2"
        Write-Log "Resync mode enabled - cloud is authoritative" -Level WARN
    }

    if ($DryRun) {
        $rcloneArgs += "--dry-run"
        Write-Log "[DRY RUN] No changes will be made" -Level WARN
    }

    Write-Log "Executing: rclone $($rcloneArgs -join ' ')" -Level INFO

    & rclone @rcloneArgs 2>&1 | ForEach-Object {
        if ($_ -match "ERROR|error") {
            Write-Log $_ -Level ERROR
        }
        elseif ($_ -match "WARN|warn") {
            Write-Log $_ -Level WARN
        }
    }

    return $LASTEXITCODE
}

function Invoke-Pull {
    Write-Log "Starting pull (cloud -> local)..." -Level STEP
    Write-Log "  Source:      $($Config.RemotePath) (cloud)" -Level INFO
    Write-Log "  Destination: $($Config.LocalPath) (local)" -Level INFO
    Write-Log "  Mode: cloud overwrites local (one-way)" -Level INFO

    $rcloneArgs = @(
        "sync"
        $Config.RemotePath
        $Config.LocalPath
        "--verbose"
        "--log-file", $Script:LogFile
    )

    if ($DryRun) {
        $rcloneArgs += "--dry-run"
        Write-Log "[DRY RUN] No changes will be made" -Level WARN
    }

    Write-Log "Executing: rclone $($rcloneArgs -join ' ')" -Level INFO

    & rclone @rcloneArgs 2>&1 | ForEach-Object {
        if ($_ -match "ERROR|error") {
            Write-Log $_ -Level ERROR
        }
        elseif ($_ -match "WARN|warn") {
            Write-Log $_ -Level WARN
        }
    }

    return $LASTEXITCODE
}

function Invoke-Push {
    Write-Log "Starting push (local -> cloud)..." -Level STEP
    Write-Log "  Source:      $($Config.LocalPath) (local)" -Level INFO
    Write-Log "  Destination: $($Config.RemotePath) (cloud)" -Level INFO
    Write-Log "  Mode: local overwrites cloud (one-way)" -Level INFO

    $rcloneArgs = @(
        "sync"
        $Config.LocalPath
        $Config.RemotePath
        "--verbose"
        "--log-file", $Script:LogFile
    )

    if ($DryRun) {
        $rcloneArgs += "--dry-run"
        Write-Log "[DRY RUN] No changes will be made" -Level WARN
    }

    Write-Log "Executing: rclone $($rcloneArgs -join ' ')" -Level INFO

    & rclone @rcloneArgs 2>&1 | ForEach-Object {
        if ($_ -match "ERROR|error") {
            Write-Log $_ -Level ERROR
        }
        elseif ($_ -match "WARN|warn") {
            Write-Log $_ -Level WARN
        }
    }

    return $LASTEXITCODE
}

# ============================================================================
# Status
# ============================================================================

function Show-Status {
    Write-Banner "Obsidian Sync Status" "Current state overview"

    # Connection status
    Write-Host "  Connection" -ForegroundColor White
    $connected = Test-RemoteConnection
    Write-Host ""

    # Local vault info
    Write-Host "  Local Vault" -ForegroundColor White
    if (Test-Path $Config.LocalPath) {
        $files = (Get-ChildItem -Path $Config.LocalPath -Recurse -File -ErrorAction SilentlyContinue)
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($totalSize / 1MB, 1)
        Write-Log "Path:  $($Config.LocalPath)" -Level INFO
        Write-Log "Files: $($files.Count)  |  Size: $sizeMB MB" -Level INFO
    }
    else {
        Write-Log "Local vault not found" -Level WARN
    }
    Write-Host ""

    # Recent logs
    Write-Host "  Recent Sync Logs" -ForegroundColor White
    if (Test-Path $Config.LogDir) {
        $recentLogs = Get-ChildItem -Path $Config.LogDir -Filter "obsidian-sync_*.log" |
            Sort-Object CreationTime -Descending |
            Select-Object -First 5

        if ($recentLogs.Count -gt 0) {
            foreach ($log in $recentLogs) {
                $ts = $log.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                $sizeVal = [math]::Round($log.Length / 1KB, 1)
                $fmt = '    {0}  |  {1,7} kB  |  {2}'
                $logLine = $fmt -f $ts, $sizeVal, $log.Name
                Write-Host $logLine -ForegroundColor Gray
            }
        }
        else {
            Write-Log "No sync logs found." -Level INFO
        }
    }
    Write-Host ""

    # Snapshots
    Write-Host "  Snapshots" -ForegroundColor White
    if (Test-Path $Config.SnapshotDir) {
        $snapCount = (Get-ChildItem -Path $Config.SnapshotDir -Filter "obsidian_*.zip").Count
        Write-Log "Available: $snapCount / $($Config.MaxSnapshots) max" -Level INFO
    }
    else {
        Write-Log "No snapshots directory" -Level INFO
    }

    # Bisync state
    Write-Host ""
    Write-Host "  Bisync State" -ForegroundColor White
    $bisyncDir = Join-Path $env:LOCALAPPDATA "rclone\bisync"
    if (Test-Path $bisyncDir) {
        $stateFiles = Get-ChildItem -Path $bisyncDir -Filter "*obsidian*" -ErrorAction SilentlyContinue
        if ($stateFiles.Count -gt 0) {
            Write-Log "Bisync tracking state: initialized" -Level OK
            $lastModified = ($stateFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
            Write-Log "Last state update: $($lastModified.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
        }
        else {
            Write-Log "Bisync tracking state: not initialized" -Level WARN
            Write-Log "Run with -Resync to initialize bisync state" -Level INFO
        }
    }
    else {
        Write-Log "Bisync tracking state: not initialized" -Level WARN
    }
    Write-Host ""
}

# ============================================================================
# Log Management
# ============================================================================

function Send-LogToCloud {
    Write-Log "Uploading sync log to Google Drive..." -Level STEP

    $logFileName = Split-Path $Script:LogFile -Leaf

    $rcloneArgs = @(
        "copyto"
        $Script:LogFile
        "$($Config.RemoteLogPath)/$logFileName"
        "--verbose"
    )

    & rclone @rcloneArgs 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Log "Log uploaded: $($Config.RemoteLogPath)/$logFileName" -Level OK
    }
    else {
        Write-Log "Failed to upload log to cloud. Log saved locally: $($Script:LogFile)" -Level WARN
    }
}

# ============================================================================
# Summary
# ============================================================================

function Show-Summary {
    $duration = (Get-Date) - $Script:SyncStats.StartTime
    $durationStr = "{0:mm\:ss}" -f $duration

    Write-Host ""
    $separator = "  " + ("-" * 56)
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host "  Summary" -ForegroundColor White
    Write-Host $separator -ForegroundColor DarkGray

    $statusColor = if ($Script:ExitCode -eq 0) { "Green" } else { "Red" }
    $statusText  = if ($Script:ExitCode -eq 0) { "SUCCESS" } else { "FAILED" }

    Write-Host "    Status:   $statusText" -ForegroundColor $statusColor
    Write-Host "    Action:   $($Script:SyncStats.Action)" -ForegroundColor Gray
    Write-Host "    Duration: $durationStr" -ForegroundColor Gray
    Write-Host "    Log:      $($Script:LogFile)" -ForegroundColor Gray

    if ($Script:SyncStats.SnapshotPath) {
        Write-Host "    Snapshot: $(Split-Path $Script:SyncStats.SnapshotPath -Leaf)" -ForegroundColor Gray
    }

    if ($DryRun) {
        Write-Host "    Mode:     DRY RUN (no changes made)" -ForegroundColor Yellow
    }

    Write-Host $separator -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================================
# Main
# ============================================================================

function Main {
    # Ensure log directory exists
    if (-not (Test-Path $Config.LogDir)) {
        New-Item -ItemType Directory -Path $Config.LogDir -Force | Out-Null
    }

    # Action-specific titles
    $actionTitle = switch ($Action) {
        "sync"    { "Bidirectional Sync (bisync)" }
        "pull"    { "Pull: Cloud -> Local" }
        "push"    { "Push: Local -> Cloud" }
        "status"  { "Status" }
        "history" { "Snapshot History" }
        "restore" { "Restore from Snapshot" }
    }

    Write-Banner "Obsidian Vault Sync" $actionTitle

    # Handle non-sync actions early
    if ($Action -eq "history") {
        Get-SnapshotHistory
        return
    }

    if ($Action -eq "status") {
        Show-Status
        return
    }

    # Log session start
    Write-Log "Session started: $($Script:Timestamp)" -Level INFO
    Write-Log "Action: $Action" -Level INFO

    # Pre-flight checks
    if (-not (Invoke-PreflightChecks)) {
        Write-Log "Pre-flight checks failed. Aborting." -Level ERROR
        $Script:ExitCode = 1
        Show-Summary
        exit $Script:ExitCode
    }

    # Handle restore
    if ($Action -eq "restore") {
        Restore-Snapshot
        Show-Summary
        Send-LogToCloud
        exit $Script:ExitCode
    }

    # Create snapshot before sync/pull (safety net)
    if ($Action -in @("sync", "pull")) {
        $localFiles = Get-ChildItem -Path $Config.LocalPath -Recurse -File -ErrorAction SilentlyContinue
        if ($localFiles.Count -gt 0) {
            New-Snapshot
        }
        else {
            Write-Log "Local vault is empty - skipping snapshot" -Level INFO
        }
    }

    # Execute sync operation
    Write-Host ""
    $syncExitCode = switch ($Action) {
        "sync" { Invoke-Bisync }
        "pull" { Invoke-Pull }
        "push" { Invoke-Push }
    }

    if ($syncExitCode -ne 0) {
        Write-Log "rclone exited with code $syncExitCode" -Level ERROR

        # Check for common bisync issues
        if ($Action -eq "sync" -and -not $Resync) {
            Write-Log "If this is the first run, try: obsidian-rclone -Action sync -Resync" -Level WARN
            Write-Log "If bisync state is corrupted, -Resync will rebuild it." -Level WARN
        }

        $Script:ExitCode = $syncExitCode
    }
    else {
        Write-Log "Sync completed successfully" -Level OK
        $Script:SyncStats.Success = $true
    }

    # Upload log to cloud
    Send-LogToCloud

    # Summary
    Show-Summary

    exit $Script:ExitCode
}

# Run
Main
