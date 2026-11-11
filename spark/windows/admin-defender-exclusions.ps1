# Defender exclusions for build and dev paths. Safe to re-run; run elevated.
# D: is a Dev Drive, so Defender already scans it in performance mode (asynchronously). These exclusions
# go further and skip scanning entirely for trusted dev content, so builds stop paying for scans of
# freshly written, unsigned .exe/.dll output.
$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-defender-exclusions.log')
Start-Transcript $out -Force | Out-Null
try {
  $paths = @(
    'D:\src',                          # repos
    'D:\packages',                     # NuGet (NUGET_PACKAGES etc.), rustup, cargo
    "$env:ProgramFiles\dotnet"         # SDK, runtimes, workloads
  )
  $procs = @('dotnet.exe', 'MSBuild.exe', 'devenv.exe', 'VBCSCompiler.exe')

  # Wrong guess from the first pass (2026-11-10): NuGet on this box lives under D:\packages, not the profile.
  $stale = @("$env:USERPROFILE\.nuget\packages")

  $pref = Get-MpPreference
  $havePaths = @($pref.ExclusionPath | Where-Object { $_ })
  $haveProcs = @($pref.ExclusionProcess | Where-Object { $_ })

  $rmPaths = @($stale | Where-Object { $havePaths -contains $_ })
  if ($rmPaths) { Remove-MpPreference -ExclusionPath $rmPaths; "removed stale path(s): $($rmPaths -join ', ')" }

  $addPaths = @($paths | Where-Object { $havePaths -notcontains $_ })
  if ($addPaths) { Add-MpPreference -ExclusionPath $addPaths; "added path(s): $($addPaths -join ', ')" }

  $addProcs = @($procs | Where-Object { $haveProcs -notcontains $_ })
  if ($addProcs) { Add-MpPreference -ExclusionProcess $addProcs; "added process(es): $($addProcs -join ', ')" }

  $pref = Get-MpPreference
  'exclusion paths:';     $pref.ExclusionPath    | ForEach-Object { "  $_" }
  'exclusion processes:'; $pref.ExclusionProcess | ForEach-Object { "  $_" }
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
