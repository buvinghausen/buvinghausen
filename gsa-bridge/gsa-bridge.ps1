<#
.SYNOPSIS
  Windows half of gsa-bridge. Listens on loopback and dials GSA-protected FQDNs BY NAME
  so the Global Secure Access client intercepts and tunnels the connection.

.DESCRIPTION
  GSA hooks sockets belonging to Windows processes. WSL sits below those hooks, so it can
  never reach a 6.6.0.0/16 synthetic address itself. This relay makes the outbound
  connection as a Windows process and hands the established socket to WSL.

  Resolution happens per connection, never at startup: the logon task usually starts
  before GSA has authenticated, and GSA assigns synthetic IPs dynamically.

.PARAMETER Status
  Resolve and TCP-test every endpoint, print a table, and exit.

.PARAMETER AllowNonIntercepted
  Relay even when an FQDN does not resolve into 6.6.0.0/16. Off by default so failures
  are loud and immediate instead of silently bypassing GSA.

.EXAMPLE
  .\gsa-bridge.ps1
  .\gsa-bridge.ps1 -Status
#>
[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'endpoints.tsv'),
  [switch]$Status,
  [switch]$AllowNonIntercepted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Endpoints {
  param([string]$Path)

  if (-not (Test-Path $Path)) { throw "config not found: $Path" }

  $rows = @()
  $lineNo = 0
  foreach ($line in Get-Content -LiteralPath $Path) {
    $lineNo++
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }

    $f = $line -split "`t"
    if ($f.Count -ne 5) {
      throw "line ${lineNo}: expected 5 tab-separated fields, got $($f.Count): $line"
    }
    if ($f[3] -eq '-' -or $f[4] -eq '-') {
      throw "line ${lineNo}: '$($f[0])' has unassigned wsl_addr/bridge_port - run wsl/sync_hosts.py --assign"
    }

    $rows += [pscustomobject]@{
      Name       = $f[0]
      Fqdn       = $f[1]
      Port       = [int]$f[2]
      WslAddr    = $f[3]
      BridgePort = [int]$f[4]
    }
  }

  # bridge_port must be globally unique - two listeners cannot share one loopback port
  $dupPort = $rows | Group-Object BridgePort | Where-Object Count -gt 1
  if ($dupPort) { throw "duplicate bridge_port: $($dupPort.Name -join ', ')" }

  # (wsl_addr, port) must be unique - that pair is what the WSL relay binds
  $dupBind = $rows | Group-Object { "$($_.WslAddr):$($_.Port)" } | Where-Object Count -gt 1
  if ($dupBind) { throw "duplicate wsl_addr:port binding: $($dupBind.Name -join ', ')" }

  # one fqdn must always map to one wsl_addr, or /etc/hosts becomes ambiguous
  # @() matters: a single unique value collapses to a scalar, which has no .Count under StrictMode
  $badMap = $rows | Group-Object Fqdn | Where-Object { @($_.Group.WslAddr | Sort-Object -Unique).Count -gt 1 }
  if ($badMap) { throw "fqdn mapped to more than one wsl_addr: $($badMap.Name -join ', ')" }

  return $rows
}

$engine = @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

public static class GsaBridge
{
    public static bool RequireIntercept = true;

    static void Log(string msg)
    {
        Console.WriteLine("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + msg);
    }

    public static void Listen(string name, string fqdn, int port, int bridgePort)
    {
        TcpListener l;
        try
        {
            l = new TcpListener(IPAddress.Loopback, bridgePort);
            l.Start();
        }
        catch (Exception ex)
        {
            // One bad port must not take down the other seventeen.
            Log("ERROR   " + name + " cannot bind 127.0.0.1:" + bridgePort + " - " + ex.Message + " (skipped)");
            return;
        }

        Log(String.Format("listen  127.0.0.1:{0,-6} -> {1}:{2}  [{3}]", bridgePort, fqdn, port, name));

        Task.Run(async () =>
        {
            while (true)
            {
                TcpClient c;
                try { c = await l.AcceptTcpClientAsync(); }
                catch (Exception ex) { Log("ERROR   " + name + " accept failed: " + ex.Message); return; }
                var ignored = Handle(name, fqdn, port, c);
            }
        });
    }

    static async Task Handle(string name, string fqdn, int port, TcpClient client)
    {
        using (client)
        {
            IPAddress[] addrs;
            try
            {
                // Per connection, never cached - see spec.md "Lazy, per-connection resolution".
                addrs = await Dns.GetHostAddressesAsync(fqdn);
            }
            catch (Exception ex)
            {
                Log("REFUSED " + name + " - cannot resolve " + fqdn + " (" + ex.Message + ") - is GSA up?");
                return;
            }

            IPAddress pick = null;
            foreach (var a in addrs)
            {
                if (a.AddressFamily == AddressFamily.InterNetwork) { pick = a; break; }
            }
            if (pick == null)
            {
                Log("REFUSED " + name + " - no IPv4 address for " + fqdn);
                return;
            }

            if (RequireIntercept && !pick.ToString().StartsWith("6.6."))
            {
                Log("REFUSED " + name + " - " + fqdn + " resolved to " + pick +
                    ", not a GSA synthetic 6.6.x.x address. Is the GSA client running and are you assigned to the app?");
                return;
            }

            var up = new TcpClient();
            try
            {
                var connect = up.ConnectAsync(pick, port);
                if (await Task.WhenAny(connect, Task.Delay(8000)) != connect)
                    throw new TimeoutException("connect timed out after 8s");
                await connect;
            }
            catch (Exception ex)
            {
                Log("REFUSED " + name + " - connect to " + pick + ":" + port + " failed: " + ex.Message);
                up.Close();
                return;
            }

            Log("open    " + name + " -> " + pick + ":" + port);
            using (up)
            {
                var cs = client.GetStream();
                var us = up.GetStream();
                try
                {
                    // Raw byte copy in both directions. No TLS termination: the payload is
                    // opaque here, so certificates and bearer tokens stay end to end.
                    await Task.WhenAny(cs.CopyToAsync(us), us.CopyToAsync(cs));
                }
                catch { }
            }
            Log("close   " + name);
        }
    }
}
'@

$endpoints = Read-Endpoints -Path $ConfigPath

if ($Status) {
  Write-Host ''
  Write-Host ('{0,-13} {1,-8} {2,-54} {3}' -f 'NAME', 'PORT', 'RESOLVES TO', 'TCP')
  Write-Host ('-' * 92)
  foreach ($e in $endpoints) {
    $ips = @()
    try {
      # Filter on Type, not on $_.IPAddress: most of these names resolve through a CNAME
      # chain, and CNAME record objects have no IPAddress property at all - touching it
      # under StrictMode throws and would silently look like a resolution failure.
      # @() keeps a single-address result an array so $ips[0] is an address, not a character.
      $ips = @(Resolve-DnsName $e.Fqdn -Type A -ErrorAction Stop |
               Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)
    } catch { }

    if (-not $ips)                                    { $state = 'NO-RESOLVE (GSA down?)' }
    elseif ($ips | Where-Object { $_ -like '6.6.*' }) { $state = "$($ips[0]) (intercepted)" }
    else                                              { $state = "$($ips[0]) (NOT intercepted)" }

    $tcp = 'skip'
    if ($ips) {
      $r = Test-NetConnection -ComputerName $e.Fqdn -Port $e.Port -WarningAction SilentlyContinue
      $tcp = if ($r.TcpTestSucceeded) { 'open' } else { 'CLOSED' }
    }
    Write-Host ('{0,-13} {1,-8} {2,-54} {3}' -f $e.Name, $e.Port, $state, $tcp)
  }
  Write-Host ''
  return
}

Add-Type -TypeDefinition $engine -Language CSharp
[GsaBridge]::RequireIntercept = -not $AllowNonIntercepted

Write-Host "gsa-bridge (Windows) - $($endpoints.Count) listeners from $ConfigPath"
if ($AllowNonIntercepted) { Write-Host 'WARNING: -AllowNonIntercepted is set; non-GSA traffic will be relayed.' }

foreach ($e in $endpoints) {
  [GsaBridge]::Listen($e.Name, $e.Fqdn, $e.Port, $e.BridgePort)
}

Write-Host 'Ready. Listeners are passive - nothing touches the network until WSL connects.'
while ($true) { Start-Sleep -Seconds 3600 }
