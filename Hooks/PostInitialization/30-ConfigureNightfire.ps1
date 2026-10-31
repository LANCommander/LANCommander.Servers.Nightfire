#Requires -Modules Logging

# Write the NF_* settings into bond/<NF_CONFIG>, the server config nf-server passes as
# servercfgfile (run on every map load, like server.cfg). It execs bond/server.cfg first when one
# exists, so settings without a non-empty NF_* value can be kept there. The map rotation goes in
# bond/<name>_mapcycle.txt. Both files are written through the merged view, so they land in
# Overlay/bond/.

$name = if ($Env:NF_CONFIG) { $Env:NF_CONFIG } else { 'lancommander.cfg' }
$dir  = Join-Path $Env:SERVER_ROOT 'bond'
$file = Join-Path $dir $name

if (-not (Test-Path -Path (Join-Path $Env:SERVER_ROOT 'Bond2.exe'))) {
    Write-Log -Level Error "Bond2.exe not found in $Env:SERVER_ROOT; skipping server configuration"
    return
}

# Maps that ship with the 5.9x patch, by game type. The map prefix picks the game type.
$defaultMaps = @{
    'ctf' = 'ctf_austria,ctf_island,ctf_japan,ctf_jungle,ctf_knox,ctf_office,ctf_romania,ctf_tower'
    'dm'  = 'dm_austria,dm_casino,dm_caviar,dm_island,dm_japan,dm_jungle,dm_knox,dm_maint,dm_office,dm_power'
}

function ConvertTo-Flag([string] $Value) {
    if ($Value -match '^(1|true|yes|on)$') { '1' } else { '0' }
}

function ConvertTo-Quoted([string] $Value) {
    '"' + $Value.Replace('"', '') + '"'
}

$lines = @(
    "// Generated from the NF_* settings on every container start; edit bond/server.cfg instead"
)

if (Test-Path -Path (Join-Path $dir 'server.cfg')) {
    $lines += 'exec server.cfg'
}

if ($Env:NF_SERVER_NAME)   { $lines += "host_name $(ConvertTo-Quoted $Env:NF_SERVER_NAME)" }
if ($Env:NF_LAN)           { $lines += "sv_lan $(ConvertTo-Flag $Env:NF_LAN)" }
if ($Env:NF_RCON_PASSWORD) { $lines += "rcon_password $(ConvertTo-Quoted $Env:NF_RCON_PASSWORD)" }
if ($Env:NF_PASSWORD)      { $lines += "sv_password $(ConvertTo-Quoted $Env:NF_PASSWORD)" }
if ($Env:NF_TIME_LIMIT)    { $lines += "mp_timelimit $Env:NF_TIME_LIMIT" }
if ($Env:NF_FRAG_LIMIT)    { $lines += "mp_fraglimit $Env:NF_FRAG_LIMIT" }
if ($Env:NF_CAPTURE_LIMIT) { $lines += "ctf_capture $Env:NF_CAPTURE_LIMIT" }
if ($Env:NF_FRIENDLY_FIRE) { $lines += "mp_friendlyfire $(ConvertTo-Flag $Env:NF_FRIENDLY_FIRE)" }
if ($Env:NF_WEAPON_STAY)   { $lines += "mp_weaponstay $(ConvertTo-Flag $Env:NF_WEAPON_STAY)" }

# Map rotation. Empty uses every stock map of the starting map's type; "config" leaves mapcyclefile
# alone (bond/mapcycle.txt unless server.cfg sets it).
$map  = if ($Env:NF_MAP) { $Env:NF_MAP } else { 'ctf_romania' }
$type = if ($map -match '^ctf_') { 'ctf' } else { 'dm' }
$maps = if ($Env:NF_MAPCYCLE) { $Env:NF_MAPCYCLE } else { $defaultMaps[$type] }

if ($maps -ine 'config') {
    $cycleName = [System.IO.Path]::GetFileNameWithoutExtension($name) + '_mapcycle.txt'
    $cycle     = Join-Path $dir $cycleName
    $list      = @($maps -split '[,\s]+' | Where-Object { $_ })

    [System.IO.File]::WriteAllText($cycle, (($list -join "`r`n") + "`r`n"))
    chown "$($Env:UID):$($Env:GID)" $cycle

    $lines += "mapcyclefile $cycleName"
    Write-Log "Map rotation: $($list -join ', ')"
}

[System.IO.File]::WriteAllText($file, (($lines -join "`r`n") + "`r`n"))
chown "$($Env:UID):$($Env:GID)" $file

Write-Log "Applied NF_* settings to bond/$name"
