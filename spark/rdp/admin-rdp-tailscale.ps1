# Scope every built-in Remote Desktop firewall rule to the tailnet (Tailscale CGNAT IPv4 range + Tailscale IPv6 ULA). Run elevated.
# Scope applies to disabled rules too, so turning RDP off and on later keeps it.
$tailnet = '100.64.0.0/10', 'fd7a:115c:a1e0::/48'
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Set-NetFirewallRule -RemoteAddress $tailnet
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | ForEach-Object {
  [pscustomobject]@{
    Rule    = $_.DisplayName
    Enabled = $_.Enabled
    Remote  = (($_ | Get-NetFirewallAddressFilter).RemoteAddress -join ', ')
  }
} | Format-Table -AutoSize
Read-Host 'Done. Press Enter to close'
