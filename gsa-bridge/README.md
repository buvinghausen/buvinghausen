# gsa-bridge

Reach GSA-protected Azure resources from WSL2, using the same hostnames and ports you use on Windows.

The Global Secure Access client never tunnels WSL traffic, but its DNS hook still hands WSL synthetic `6.6.0.0/16` addresses that route nowhere. This bridges the gap: a Windows relay makes the outbound connection (so GSA intercepts it) and hands the socket to WSL.

Design and rationale: [`spec.md`](spec.md). DNS background: [`../WSL-GSA-DNS-fix.md`](../WSL-GSA-DNS-fix.md).

## Install

**Windows** — register the logon task, then start it:

```powershell
cd C:\Users\buvy\gsa-bridge\install
.\Install-WindowsTask.ps1
Start-ScheduledTask -TaskName gsa-bridge
```

**WSL** — update `/etc/hosts`, install the service:

```bash
cd /mnt/c/Users/buvy/gsa-bridge/wsl
sudo python3 sync_hosts.py
sudo cp ../install/gsa-bridge.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gsa-bridge
```

## Use

Nothing changes. Use the identical connection string you use on Windows:

```bash
# Azure SQL, Entra auth
sqlcmd -S sql-dev.privatelink.database.windows.net -G

# Key Vault / App Config / Blob
az keyvault secret list --vault-name vault-dev
curl https://file-dev.blob.core.windows.net/
```

`az login` works without the bridge — Entra endpoints are public and reach the internet directly. The bridge carries only the data plane.

## Check it

```powershell
.\gsa-bridge.ps1 -Status          # resolve + TCP-test all 18, from Windows
```

```bash
python3 wsl/gsa_bridge.py --check                 # validate config, bind nothing
systemctl status gsa-bridge                       # WSL relay
journalctl -u gsa-bridge -f                       # live log
GSA_BRIDGE_INTEGRATION=1 python3 wsl/test_gsa_bridge.py   # full end-to-end
```

Healthy `-Status` shows every row `6.6.x.x (intercepted)` and `open`.

## Verifying after a reboot

Everything is registered to come back on its own, and **this was confirmed on 2026-08-17** after a full
Windows power-down with GSA up: logon task `Running`, 18/18 Windows ports and 18/18 WSL listeners bound,
both systemd units `active`, the `/etc/hosts` block re-applied, and 22/22 tests passing including the live
TDS and TLS checks. Nothing needed a manual step.

Note that GSA handed out an entirely different set of synthetic IPs on that boot. That is expected and is
exactly why the Windows relay resolves per connection instead of caching — see `spec.md`, "Lazy,
per-connection resolution".

To re-confirm after any later reboot:

```powershell
& "C:\Users\buvy\gsa-bridge\gsa-bridge.ps1" -Status
(Get-ScheduledTask -TaskName gsa-bridge).State                    # Running
@(Get-NetTCPConnection -State Listen -LocalPort (14001..14018)).Count   # 18
```

```bash
systemctl status gsa-bridge gsa-bridge-hosts
getent hosts vault-dev.vault.azure.net   # want 127.0.0.20, NOT a public IP
GSA_BRIDGE_INTEGRATION=1 python3 /mnt/c/Users/buvy/gsa-bridge/wsl/test_gsa_bridge.py
```

The one to watch is `getent`. WSL regenerates `/etc/hosts` on every boot, and
`gsa-bridge-hosts.service` re-applies the managed block afterwards. If ordering ever fails,
the symptom is a public IP there and nothing connecting. Fix:

```bash
sudo python3 /mnt/c/Users/buvy/gsa-bridge/wsl/sync_hosts.py
sudo systemctl restart gsa-bridge
```

## Adding an endpoint

Append a row to `endpoints.tsv` with `-` for the last two columns, then:

```bash
python3 wsl/sync_hosts.py --assign   # allocates wsl_addr + bridge_port
sudo python3 wsl/sync_hosts.py       # updates /etc/hosts
sudo systemctl restart gsa-bridge    # WSL side
```

```powershell
Stop-ScheduledTask -TaskName gsa-bridge; Start-ScheduledTask -TaskName gsa-bridge
```

Existing rows are never renumbered — `--assign` only fills in `-` placeholders. A host that already has an address reuses it when you add another port.

## Troubleshooting

| Symptom | Meaning |
|---|---|
| `REFUSED ... not a GSA synthetic 6.6.x.x address` | GSA is down, still starting, or you're off-network. Check `-Status`. |
| `cannot reach Windows relay ... is gsa-bridge.ps1 running?` | Windows half isn't up. `Start-ScheduledTask -TaskName gsa-bridge`. |
| `permission denied binding ...:443` | The unit's `CAP_NET_BIND_SERVICE` didn't apply. Check `systemctl cat gsa-bridge`. |
| Name resolves to a public IP in WSL | `/etc/hosts` block missing or stale. Re-run `sudo python3 wsl/sync_hosts.py`. |
| Certificate errors | Confirm you're using the same hostname as on Windows. The bridge doesn't terminate TLS, so cert behavior is identical to Windows. |

Both relays are passive: they bind loopback sockets at startup and touch nothing until a client connects. Starting before GSA has authenticated is expected and fine — resolution happens per connection, so the bridge starts working the moment GSA is ready, with no restart.

## Layout

```
endpoints.tsv              the only file you maintain
gsa-bridge.ps1             Windows relay + -Status health check
install/
  Install-WindowsTask.ps1  logon Scheduled Task
  gsa-bridge.service       systemd unit
wsl/
  gsa_bridge.py            WSL relay
  sync_hosts.py            /etc/hosts block + address assignment
  test_gsa_bridge.py       tests
```
