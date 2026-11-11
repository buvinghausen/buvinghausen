# Point Windows DNS at NextDNS over DNS-over-HTTPS (built into Windows 11; nothing installed). Safe to re-run; run elevated.
#   -ConfigId : the 6-hex-char ID from my.nextdns.io (Setup tab, "Endpoints" -> ID).
#   -Device   : name shown in the NextDNS Logs/Analytics for this box.
# How it works: the four NextDNS anycast addresses are registered as DoH servers with a template that carries the
# config ID (so no linked-IP needed), fallback to plaintext UDP is OFF, and every physical adapter present gets
# those addresses as its DNS servers. Windows auto-upgrades any query to a registered DoH server to HTTPS.
# Virtual adapters (Hyper-V/WSL/Docker vEthernet) are left alone; WSL's DNS tunnelling goes through the host resolver.
# Undo: Set-DnsClientServerAddress -InterfaceAlias <name> -ResetServerAddresses; Remove-DnsClientDohServerAddress <ip>.
param(
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{6}$')][string]$ConfigId,
  [ValidatePattern('^[A-Za-z0-9-]{1,63}$')][string]$Device = 'surfacespark'
)
$ErrorActionPreference = 'Stop'
$out = (Join-Path $PSScriptRoot 'admin-nextdns.log')
Start-Transcript $out -Force | Out-Null

try {
  $template = "https://dns.nextdns.io/$ConfigId/$Device"
  $v4 = '45.90.28.0', '45.90.30.0'
  $v6 = '2a07:a8c0::', '2a07:a8c1::'

  'DoH servers:'
  foreach ($ip in $v4 + $v6) {
    $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
    $args2 = @{ ServerAddress = $ip; DohTemplate = $template; AllowFallbackToUdp = $false; AutoUpgrade = $true }
    if ($existing) { Set-DnsClientDohServerAddress @args2 | Out-Null } else { Add-DnsClientDohServerAddress @args2 | Out-Null }
    "  $ip -> $template (no UDP fallback)"
  }

  'Adapters:'
  # Every present physical adapter, connected or not (the USB 2.5GbE sits Disconnected until it's plugged in).
  $nics = @(Get-NetAdapter -Physical | Where-Object Status -ne 'Not Present')
  if (-not $nics) { '  no physical adapter present - nothing set' }
  foreach ($n in $nics) {
    Set-DnsClientServerAddress -InterfaceIndex $n.ifIndex -ServerAddresses ($v4 + $v6)
    "  $($n.Name) ($($n.InterfaceDescription)) -> $(($v4 + $v6) -join ', ')"
  }

  Clear-DnsClientCache
  'Done. Check https://test.nextdns.io in Brave: status "ok", protocol "DOH".'
} catch { "ERROR: $_" } finally { Stop-Transcript | Out-Null }
