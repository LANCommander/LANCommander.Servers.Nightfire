#Requires -Modules Logging

# The 5.9x community patch adds code to engine.dll (its "Extra1MB" section) that precaches the
# player death sounds with hard-coded pointers to strings inside bond/cl_dlls/client.dll:
#
#   push 0x4107DDFE  ; "player/pl_die2.wav" in client.dll
#   call [g_engfuncs.pfnPrecacheSound]
#
# client.dll is only loaded by a game client, so on a dedicated server those addresses are unmapped
# and every map load dies with "page fault on read access to 0x4107DDFE" in PF_precache_sound_I.
# The female death sound picker does the same at runtime (player/fe_die1.wav).
#
# This patches a copy of engine.dll: the four strings are copied into unused space at the end of
# Extra1MB and the push operands are pointed at the copies. The copy is written through the merged
# view, so it lands in Overlay/ and Server/ keeps the original. Only the known engine.dll (5.9.9.0)
# is patched; anything else is left alone.

$dll = Join-Path $Env:SERVER_ROOT 'engine.dll'

$originalHash = 'FB9A989666E31ED123FEF0981F9F9F4BA3C7912D7B69A9B0856582B2C97F4797'
$patchedHash  = '079F4FC70CF6AD91789C87F41B750AB57DB8CFB4977A46611B8FB4FC7BF48922'

if ($Env:NF_PATCH_ENGINE -in @('false', '0', 'no')) {
    Write-Log "NF_PATCH_ENGINE is off; not patching engine.dll"
    return
}

if (-not (Test-Path -Path $dll)) {
    Write-Log -Level Error "$dll not found; skipping engine.dll patch"
    return
}

$hash = (Get-FileHash -Path $dll -Algorithm SHA256).Hash

if ($hash -eq $patchedHash) {
    Write-Log "engine.dll is already patched for dedicated servers"
    return
}

if ($hash -ne $originalHash) {
    Write-Log -Level Warning "Unknown engine.dll (sha256 $hash); not patching it. The server may crash on map load."
    return
}

$bytes = [System.IO.File]::ReadAllBytes($dll)

# Extra1MB: VirtualAddress 0x1BAA000 (VA 0x44BAA000), PointerToRawData 0x137000
function Get-Offset([uint32] $Va) { [int]($Va - 0x44BAA000 + 0x137000) }

$strings = @(
    @{ Push = 0x44BEE8AA; Old = 0x4107DDFE; Text = 'player/pl_die2.wav' }
    @{ Push = 0x44BEE8B5; Old = 0x4107DDEB; Text = 'player/pl_die3.wav' }
    @{ Push = 0x44BEE8C0; Old = 0x4107DDD8; Text = 'player/pl_die4.wav' }
    @{ Push = 0x44CA9DF2; Old = 0x41089528; Text = 'player/fe_die1.wav' }
)

# Zero padding after the patch's last code/data, referenced by nothing
$cave = 0x44CA9400

for ($i = 0; $i -lt $strings.Count; $i++) {
    $s    = $strings[$i]
    $push = Get-Offset $s.Push
    $new  = [uint32]($cave + 0x20 * $i)
    $at   = Get-Offset $new

    if ($bytes[$push] -ne 0x68 -or [BitConverter]::ToUInt32($bytes, $push + 1) -ne $s.Old) {
        throw ("Unexpected bytes at engine.dll VA 0x{0:X8}" -f $s.Push)
    }

    for ($j = 0; $j -lt 0x20; $j++) {
        if ($bytes[$at + $j] -ne 0) { throw ("engine.dll space at VA 0x{0:X8} is not empty" -f $new) }
    }

    $text = [System.Text.Encoding]::ASCII.GetBytes($s.Text)
    [Array]::Copy($text, 0, $bytes, $at, $text.Length)
    [Array]::Copy([BitConverter]::GetBytes($new), 0, $bytes, $push + 1, 4)
}

[System.IO.File]::WriteAllBytes($dll, $bytes)
chown "$($Env:UID):$($Env:GID)" $dll

if ((Get-FileHash -Path $dll -Algorithm SHA256).Hash -ne $patchedHash) {
    Write-Log -Level Warning "Patched engine.dll doesn't have the expected hash"
}

Write-Log "Patched engine.dll so the death sound precache doesn't read client.dll memory"
