# gsa-bridge — reach GSA-protected Azure resources from WSL2

Status: implemented · 2026-08-17 · host `PW0E88QY`

## Problem

The Global Secure Access client never tunnels WSL traffic — Microsoft states plainly that "WSL doesn't acquire traffic from a client installed on the host machine." Yet GSA's DNS hook still rewrites answers to synthetic `6.6.0.0/16` addresses that only its own filter driver can route. From WSL those addresses blackhole, so GSA-protected private endpoints are unreachable.

Separately, WSL DNS is configured to bypass GSA entirely (see `../WSL-GSA-DNS-fix.md`). That fixes public name resolution but does nothing for private resources, which have no public DNS at all — `sql-dev.database.windows.net` does not resolve.

## Key insight (measured, not assumed)

GSA's hooks are **per-socket on Windows processes**, and they do not care why the process is connecting. A Windows relay that dials upstream **by hostname** receives full Private Access treatment and can hand that established connection to WSL.

Verified during design with a real TDS PRELOGIN through a throwaway relay:

```
got 26 bytes, first byte = 0x04
hex: 04 01 00 1a ... ff 0c 00 00 83 00 00 03
```

A genuine Azure SQL reply — version `12.0.0x8300`, trailing `03` = `ENCRYPT_REQ`.

## Constraint discovered during design

WSL's mirrored networking bridges **only `127.0.0.1`** to Windows. A Windows listener on `127.0.0.5` is *not* reachable from WSL (measured: `ECONNREFUSED`, i.e. WSL's own loopback answered).

Consequence: the per-endpoint address mapping cannot live on the Windows side. It must live in WSL, where `127.0.0.x` addresses are unambiguously local.

## Architecture

```
WSL client                              Windows                        GSA
  |                                        |                            |
  | sql-dev...:1433                |                            |
  |   /etc/hosts -> 127.0.0.11             |                            |
  v                                        |                            |
[gsa_bridge.py 127.0.0.11:1433] -----> [gsa-bridge.ps1 127.0.0.1:14001]
                                            |  Dns.GetHostAddresses(fqdn)
                                            |  -> must be 6.6.0.0/16
                                            v
                                      6.6.1.220:1433 -> private endpoint
```

Three cooperating parts, one shared config:

| Part | Runs on | Responsibility |
|---|---|---|
| `gsa-bridge.ps1` | Windows | one listener per endpoint on `127.0.0.1:<bridge_port>`; resolves and dials the real FQDN **by name** so GSA intercepts |
| `wsl/gsa_bridge.py` | WSL | one listener per endpoint on `127.0.0.<n>:<real port>`; forwards to the matching Windows bridge port |
| `wsl/sync_hosts.py` | WSL | regenerates a marked block in `/etc/hosts` mapping FQDN → `127.0.0.<n>` |

Why a WSL-side process is unavoidable: `/etc/hosts` maps names to addresses only, never ports. With three endpoints on 1433 and nine on 443, preserving the real port requires a distinct local address per endpoint, and only WSL can provide those.

## Design properties

**Raw TCP pass-through — no TLS termination.** The relays copy bytes. TLS is end-to-end from the WSL client to the Azure service; the bridge never sees plaintext, never substitutes a certificate, and never observes a bearer token. This is what makes it safe to carry Entra-authenticated traffic.

**Transparent to clients.** The real hostname and the real port are preserved end to end, so certificate validation, SNI, and Azure SQL gateway routing behave exactly as they do on Windows. Use the identical connection string you use on Windows.

**Passive start.** Binding loopback sockets requires nothing from GSA or the network. Both relays come up at logon/boot regardless of GSA state. No background polling.

**Lazy, per-connection resolution.** The Windows relay resolves the FQDN on *every* inbound connection, never at startup. This is required for two reasons:
1. The Scheduled Task fires at logon, typically before the GSA client has authenticated. Caching that first result would poison the bridge permanently with no obvious symptom.
2. GSA assigns synthetic IPs dynamically per resolution, so a cached `6.6.1.220` can go stale within a healthy session.

   Confirmed across the 2026-08-17 reboot: every endpoint came back on a **different** synthetic address (`sql-dev` moved to `6.6.0.34`). A startup-time cache would have failed on the first cold boot.

**Fail fast with a named error.** If a resolution does not land in `6.6.0.0/16`, the relay closes immediately and logs which endpoint and why, rather than letting the client hang for its own timeout.

| Situation | Behavior |
|---|---|
| Boot, GSA not up yet | Bridge running; connect fails fast, "not intercepted — is GSA up?" |
| GSA finishes starting | Next connection works, no restart |
| GSA drops mid-session | Next connection fails fast; existing connections drop with the tunnel |
| Off corporate network | Same fast failure, same message |
| Bridge port already in use | That endpoint logs an error and is skipped; the others still bind |

## Auth plane vs data plane

All 15 resources authenticate with Entra SSO; there are no stored credentials. The two planes take different paths:

- **Auth** — `login.microsoftonline.com`, `login.windows.net`, `management.azure.com` resolve to real public IPs from WSL (verified HTTP 200) and egress directly, bypassing GSA. `az` 2.89.1 is installed in WSL.
- **Data** — the 15 private endpoints go through this bridge.

This mirrors how it already works on Windows.

## Security posture

- Windows listeners bind `127.0.0.1` only; WSL listeners bind `127.0.0.x` only. Neither is reachable from the LAN.
- The bridge grants **network reachability, not access**. With Entra SSO and no secrets, a process that reaches port 1433 still cannot authenticate without a token. The control point is the token cache, which this work does not change.
- Any process inside WSL can use the bridge without authentication. Accepted: single-user development machine, and reachability alone is not access.
- Production endpoints (`*-prd-*`) are bridged alongside dev and staging. Accepted deliberately.

## Endpoint table

15 FQDNs, 18 listeners (Service Bus carries both AMQP 5671 and AMQP-over-WebSockets 443).

| # | FQDN | Port | WSL addr | Bridge port |
|---|---|---|---|---|
| 1 | sql-dev.privatelink.database.windows.net | 1433 | 127.0.0.11 | 14001 |
| 2 | sql-stg.privatelink.database.windows.net | 1433 | 127.0.0.12 | 14002 |
| 3 | sql-prd.privatelink.database.windows.net | 1433 | 127.0.0.13 | 14003 |
| 4 | config-dev.azconfig.io | 443 | 127.0.0.14 | 14004 |
| 5 | config-stg.azconfig.io | 443 | 127.0.0.15 | 14005 |
| 6 | config-prd.azconfig.io | 443 | 127.0.0.16 | 14006 |
| 7 | file-dev.blob.core.windows.net | 443 | 127.0.0.17 | 14007 |
| 8 | file-stg.blob.core.windows.net | 443 | 127.0.0.18 | 14008 |
| 9 | file-prd.blob.core.windows.net | 443 | 127.0.0.19 | 14009 |
| 10 | vault-dev.vault.azure.net | 443 | 127.0.0.20 | 14010 |
| 11 | vault-stg.vault.azure.net | 443 | 127.0.0.21 | 14011 |
| 12 | vault-prd.vault.azure.net | 443 | 127.0.0.22 | 14012 |
| 13 | bus-dev.servicebus.windows.net | 5671 | 127.0.0.23 | 14013 |
| 14 | bus-stg.servicebus.windows.net | 5671 | 127.0.0.24 | 14014 |
| 15 | bus-prd.servicebus.windows.net | 5671 | 127.0.0.25 | 14015 |
| 16 | bus-dev.servicebus.windows.net | 443 | 127.0.0.23 | 14016 |
| 17 | bus-stg.servicebus.windows.net | 443 | 127.0.0.24 | 14017 |
| 18 | bus-prd.servicebus.windows.net | 443 | 127.0.0.25 | 14018 |

**SQL uses the privatelink FQDN.** The customer-facing `sql-{dev,stg,prd}.database.windows.net` names do not resolve on this host; only the `...privatelink...` form does. Verified for all three environments.

`wsl_addr` and `bridge_port` are written once and left alone, so `/etc/hosts` does not churn when rows are added. `sync_hosts.py --assign` allocates them for new rows and validates uniqueness.

## Files

```
gsa-bridge/
  spec.md                        this document
  README.md                      usage
  endpoints.tsv                  the only file you maintain
  gsa-bridge.ps1                 Windows relay + `-Status` health check
  install/
    Install-WindowsTask.ps1      registers the logon Scheduled Task
    gsa-bridge.service           systemd unit for WSL
  wsl/
    gsa_bridge.py                WSL relay
    sync_hosts.py                /etc/hosts block generator
    test_gsa_bridge.py           config + integration tests
```

## Testing

- **Config parsing** — duplicate `wsl_addr`/`bridge_port`, malformed rows, bad ports, comment/blank handling.
- **Integration, SQL** — the TDS PRELOGIN probe from the design spike, promoted to a real assertion: expects a `0x04` response through the full path.
- **Integration, HTTPS** — TLS handshake and HTTP response against a bridged 443 endpoint, confirming certificate validation succeeds against the real hostname.
- **Health check** — `gsa-bridge.ps1 -Status` resolves all 18 and reports intercepted/public/no-resolve per endpoint.

## Gotchas that cost real time

Each of these was hit during the build and is easy to hit again.

- **Assume everything in `/etc` has a second writer.** WSL regenerates `/etc/hosts` on every boot and
  systemd-resolved reclaims `/etc/resolv.conf` as a symlink. Hand-edits to either silently disappear at the
  worst moment. That is why the hosts block is re-applied by `gsa-bridge-hosts.service` rather than written
  once, and why DNS lives in `resolved.conf.d`.
- **Under `Set-StrictMode`, never touch `$_.IPAddress` on a `Resolve-DnsName` result.** Most of these names
  resolve through two or three CNAMEs, and CNAME record objects have no `IPAddress` property at all —
  reading it throws, and inside a `try`/`catch` that reads as "name did not resolve". It presented as 12 of
  18 endpoints falsely reporting `NO-RESOLVE` while SQL, which has a direct A record, looked fine. Filter on
  `$_.Type -eq 'A'` instead.
- **Azure SQL must use the `...privatelink.database.windows.net` FQDN.** The customer-facing
  `...database.windows.net` names do not resolve on this host at all. Asserted by `test_gsa_bridge.py`.
- **`ping <literal IP>` proves nothing about DNS.** It succeeded in every failure mode encountered here.
  Diagnose with `getent`/`dig`, by what resolution *returns*.

## Out of scope

- Bridging anything GSA does not intercept.
- Auth, token handling, credential storage — Entra SSO handles all of it.
- Restoring GSA coverage for WSL traffic; Microsoft does not support it.
