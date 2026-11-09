# Dock-aware desk automation for the Surface (per-user scheduled task "KbmAutoSwitch", runs at sign-in).
#
#   state        how it is detected                              keyboard swap   display timeout (AC)
#   desk         U5226KW display present                         Win<->Ctrl ON   never (UltraSharp must not sleep)
#   desk-dark    U5226KW display gone, its TB hub still present  Win<->Ctrl ON   never; OLED shows the black Blank screensaver at once, 1 min idle backstop
#   road         no U5226KW display, no hub                      OFF             never (unchanged from before)
#   + remote     the session is RDP (Chromebook -> Spark -> work): swap forced OFF whatever the state; display handling unchanged.
#                The Chromebook already sends Windows keys; the swap would turn Ctrl into Win and mstsc forwards that on to the work machine.
#
# Keyboard: PowerToys Keyboard Manager reloads default.json on change; the swap undoes the Mac's Ctrl<->Cmd swap that DDPM forwards.
# "desk-dark" keeps the lid open (cooling while serving the LLM) without the OLED taking over / burning in.
# NOTE: never power the display off here (SC_MONITORPOWER / display timeout): on this Modern Standby machine display-off = Modern Standby,
# which pauses the GPU and the llama-server (seen 2026-11-08 23:33). A black screensaver keeps the panel dark (OLED black = pixels off) without standby.
$cfg = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Keyboard Manager\default.json'
$log = Join-Path $PSScriptRoot 'kbm-autoswitch.log'
$swap = @'
{
  "remapKeys": { "inProcess": [
    { "originalKeys": "91",  "newRemapKeys": "162" },
    { "originalKeys": "162", "newRemapKeys": "91" }
  ] },
  "remapKeysToText": { "inProcess": [] },
  "remapShortcuts": { "global": [], "appSpecific": [] },
  "remapShortcutsToText": { "global": [], "appSpecific": [] }
}
'@
$none = @'
{
  "remapKeys": { "inProcess": [] },
  "remapKeysToText": { "inProcess": [] },
  "remapShortcuts": { "global": [], "appSpecific": [] },
  "remapShortcutsToText": { "global": [], "appSpecific": [] }
}
'@
Add-Type -Namespace KbmAuto -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint b, IntPtr c, uint d); [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);'
function Note($m) { "$(Get-Date -Format s) $m" | Add-Content $log }
function Get-State {
  $display = $false
  try {
    foreach ($m in Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop) {
      if ((($m.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ }) -join '') -match 'U5226KW') { $display = $true }
    }
  } catch { }
  if ($display) { return 'desk' }
  $hub = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_413C&PID_5821' -or $_.FriendlyName -match 'USB4 Router.*U5226KW' }
  if ($hub) { return 'desk-dark' }
  return 'road'
}
function Set-Swap($on) {
  $want = if ($on) { $swap } else { $none }
  $cur  = if (Test-Path $cfg) { Get-Content $cfg -Raw } else { '' }
  if ($cur.Trim() -ne $want.Trim()) { [IO.File]::WriteAllText($cfg, $want, (New-Object Text.UTF8Encoding $false)) }   # no BOM
}
function Set-DisplayTimeout($minutes) {
  $o = & powercfg.exe /change monitor-timeout-ac $minutes 2>&1
  if ($LASTEXITCODE) { Note "powercfg failed ($LASTEXITCODE): $o" }
}
function Set-BlankSaver($on) {
  $k = 'HKCU:\Control Panel\Desktop'
  if ($on) {
    Set-ItemProperty $k SCRNSAVE.EXE 'C:\Windows\System32\scrnsave.scr'; Set-ItemProperty $k ScreenSaverIsSecure '0'; Set-ItemProperty $k ScreenSaveTimeOut '60'
    [void][KbmAuto.Native]::SystemParametersInfo(0x000F, 60, [IntPtr]::Zero, 3)   # SPI_SETSCREENSAVETIMEOUT
    [void][KbmAuto.Native]::SystemParametersInfo(0x0011, 1, [IntPtr]::Zero, 3)    # SPI_SETSCREENSAVEACTIVE
    Start-Process C:\Windows\System32\scrnsave.scr -ArgumentList '/s'           # go dark now
  } else {
    Remove-ItemProperty $k SCRNSAVE.EXE -ErrorAction SilentlyContinue
    [void][KbmAuto.Native]::SystemParametersInfo(0x0011, 0, [IntPtr]::Zero, 3)
    Get-Process scrnsave.scr -ErrorAction SilentlyContinue | Stop-Process -Force
  }
}

function Test-Remote { [KbmAuto.Native]::GetSystemMetrics(0x1000) -ne 0 }   # SM_REMOTESESSION

$last = $null; $lastRemote = $null
while ($true) {
  $s = Get-State
  $remote = Test-Remote
  if ($s -ne $last -or $remote -ne $lastRemote) {
    switch ($s) {
      'desk'      { Set-Swap $true;  Set-DisplayTimeout 0; Set-BlankSaver $false }
      'desk-dark' { Set-Swap $true;  Set-DisplayTimeout 0; Start-Sleep 3; Set-BlankSaver $true }   # let Windows finish moving to the OLED first
      'road'      { Set-Swap $false; Set-DisplayTimeout 0; Set-BlankSaver $false }
    }
    if ($remote) { Set-Swap $false }
    Note "state=$s remote=$remote"
    $last = $s; $lastRemote = $remote
  }
  Start-Sleep 5
}
