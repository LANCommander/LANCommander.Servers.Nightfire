#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# James Bond 007: Nightfire is retail software with no public download. Use an existing install of
# the 5.9x community patch in /config/Server, or set NF_ARCHIVE_URL to a zip of the game folder (at
# the zip root or in a single top-level folder), e.g. a LANCommander archive. The dedicated server
# is Bond2.exe -dedicated, so the client install is all it needs.

Invoke-Hook "PreInstallNightfire"

$exe = Join-Path $Env:SERVER_DIR 'Bond2.exe'

if (Test-Path -Path $exe) {
    Write-Log "Nightfire found in $Env:SERVER_DIR"
} elseif ($Env:NF_ARCHIVE_URL) {
    Write-Log "Downloading Nightfire from $Env:NF_ARCHIVE_URL"

    $zip     = '/tmp/nightfire.zip'
    $extract = '/tmp/nightfire'

    curl -fL --retry 3 --output $zip "$Env:NF_ARCHIVE_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:NF_ARCHIVE_URL" }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue

    # The intro movies (about 600 MB) are client-only
    unzip -q -o $zip -d $extract -x 'bond/movies/*' '*/bond/movies/*'
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $zip" }

    # Accept the game at the zip root or inside one top-level folder
    $root = Get-ChildItem -Path $extract -Filter 'Bond2.exe' -Recurse -File -Depth 1 |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) { throw "Bond2.exe not found in $Env:NF_ARCHIVE_URL" }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Move-Item -Force -Path (Join-Path $root.FullName '*') -Destination $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $zip, $extract

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "Nightfire installed"
} else {
    Write-Log -Level Error "Bond2.exe not found in $Env:SERVER_DIR. Copy a Nightfire 5.9x install there or set NF_ARCHIVE_URL."
}

Invoke-Hook "PostInstallNightfire"

Set-Location $Env:SERVER_ROOT
