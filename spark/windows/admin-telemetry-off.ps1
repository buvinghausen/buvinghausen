# Rip out telemetry, diagnostic uploads, activity history, ads and "suggestions". Safe to re-run; run elevated
# FROM THE buvy ACCOUNT (HKCU values land in whichever user elevates). Reboot afterwards.
# Edition support checked against Microsoft Learn 2026-11-11 (Policy CSP System / Privacy / Experience):
#   - AllowTelemetry: Pro's floor is 1 (Required). 0 (off) is Enterprise/Education/Server only, so on Pro the real
#     kill is disabling the DiagTrack service + the uploader tasks below; the policy only pins the level at minimum.
#   - DisableWindowsConsumerFeatures is Enterprise/Education only -> the per-user ContentDeliveryManager values do the work.
# Deliberately KEPT (local, not uploaders): PcaSvc, DPS/WdiSystemHost, compat-shim tasks (PcaPatchDbTask,
# SdbinstMergeDbTask), StartupAppTask, Flighting\FeatureConfig\Reconcile*/Safeguards* (feature + update safeguards).
# Not touched: Defender cloud protection / sample submission (security trade-off; Tamper Protection guards it anyway).
# Undo: set the policy values back / delete them, `Set-Service DiagTrack -StartupType Automatic`, `Enable-ScheduledTask`.
$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-telemetry-off.log')
Start-Transcript $out -Force | Out-Null

function Set-Dword([string]$key, [string]$name, [int]$value) {
  try {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name $name -Value $value -PropertyType DWord -Force | Out-Null
    "  $key\$name = $value"
  } catch { "  BLOCKED $key\$name = $value : $($_.Exception.Message)" }
}

try {
  # 1. Diagnostic data policies (machine).
  'Diagnostic data policies (HKLM):'
  $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
  Set-Dword $dc 'AllowTelemetry'                          0   # Pro clamps to 1 (Required)
  Set-Dword $dc 'LimitDiagnosticLogCollection'            1
  Set-Dword $dc 'LimitDumpCollection'                     1
  Set-Dword $dc 'AllowDeviceNameInTelemetry'              0
  Set-Dword $dc 'DoNotShowFeedbackNotifications'          1
  Set-Dword $dc 'DisableTelemetryOptInChangeNotification' 1
  Set-Dword $dc 'DisableTelemetryOptInSettingsUx'         1
  Set-Dword $dc 'DisableOneSettingsDownloads'             1   # MS warns some features may lean on OneSettings config
  Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
  $wer = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
  Set-Dword $wer 'Disabled'               1
  Set-Dword $wer 'DontSendAdditionalData' 1
  $ac = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
  Set-Dword $ac 'AITEnable'        0   # Application Impact Telemetry
  Set-Dword $ac 'DisableInventory' 1   # Inventory Collector
  Set-Dword $ac 'DisableUAR'       1   # Steps Recorder

  # 2. Privacy policies (machine).
  'Privacy policies (HKLM):'
  Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
  $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
  Set-Dword $sys 'PublishUserActivities'     0
  Set-Dword $sys 'UploadUserActivities'      0
  Set-Dword $sys 'EnableActivityFeed'        0
  Set-Dword $sys 'AllowCrossDeviceClipboard' 0
  Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'   'AllowInputPersonalization'     0
  Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TextInput'      'AllowLinguisticDataCollection' 0
  Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice'           'AllowFindMyDevice'             0
  $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
  Set-Dword $cc 'DisableWindowsConsumerFeatures'     1   # Enterprise/Education only; backstop
  Set-Dword $cc 'DisableSoftLanding'                 1
  Set-Dword $cc 'DisableCloudOptimizedContent'       1
  Set-Dword $cc 'DisableConsumerAccountStateContent' 1

  # 3. Per-user: tailored experiences, advertising ID, and every ads/suggestions/silent-install switch.
  'Per-user privacy and content (HKCU):'
  $ucc = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
  Set-Dword $ucc 'DisableTailoredExperiencesWithDiagnosticData' 1
  Set-Dword $ucc 'DisableThirdPartySuggestions'                 1
  Set-Dword $ucc 'DisableWindowsSpotlightFeatures'              1   # Enterprise/Education only; backstop
  Set-Dword 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
  Set-Dword 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
  Set-Dword 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
  Set-Dword 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
  $cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
  foreach ($v in 'SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SoftLandingEnabled','PreInstalledAppsEnabled',
                 'PreInstalledAppsEverEnabled','OemPreInstalledAppsEnabled','ContentDeliveryAllowed','FeatureManagementEnabled',
                 'SubscribedContent-310093Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled',
                 'SubscribedContent-338393Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled',
                 'SubscribedContent-353698Enabled') { Set-Dword $cdm $v 0 }

  # 4. Services: the uploaders.
  'Services:'
  foreach ($s in 'DiagTrack', 'dmwappushservice') {
    try {
      $svc = Get-Service $s -ErrorAction Stop
      if ($svc.Status -ne 'Stopped') { Stop-Service $s -Force -ErrorAction Stop }
      Set-Service $s -StartupType Disabled -ErrorAction Stop
      $svc = Get-Service $s; "  $s -> $($svc.Status) / $($svc.StartType)"
    } catch { "  BLOCKED service $s : $($_.Exception.Message)" }
  }

  # 5. Scheduled tasks that collect or upload. Some are owned by SYSTEM/TrustedInstaller and may refuse.
  'Scheduled tasks:'
  $tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
    '\Microsoft\Windows\Application Experience\MareBackup',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Autochk\Proxy',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
    '\Microsoft\Windows\Flighting\FeatureConfig\BootstrapUsageDataReporting',   # already Disabled out of the box here
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver',
    '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
    '\Microsoft\Windows\Flighting\OneSettings\RefreshCache'
  )
  foreach ($t in $tasks) {
    $path = $t.Substring(0, $t.LastIndexOf('\') + 1); $name = $t.Substring($t.LastIndexOf('\') + 1)
    try {
      $st = Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop
      if ($st.State -ne 'Disabled') { $st | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
      "  disabled $t"
    } catch { "  BLOCKED task $t : $($_.Exception.Message)" }
  }

  'Done. Reboot so the services, policies and Start/Settings pick everything up.'
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
