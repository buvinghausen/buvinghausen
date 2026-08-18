# WSL2 DNS vs. Global Secure Access — diagnosis and fix

Host: `PW0E88QY` (Windows 11 Enterprise) · Distro: FedoraLinux-44 · WSL 2.7.11.0
Fixed: 2026-08-17 · Confirmed to survive a full power-down: 2026-08-17

Companion doc: [`gsa-bridge/spec.md`](gsa-bridge/spec.md) — reaching GSA-*protected* endpoints from WSL, which is the opposite problem and needs a different mechanism.

## Symptom

`dnf upgrade` inside WSL fails every repo with:

```
Curl error (6): Could not resolve hostname for https://mirrors.fedoraproject.org/...
[Could not resolve host: mirrors.fedoraproject.org]
```

Later, after partial fixes, the symptom shifts to either of these — all three are the *same underlying problem* wearing different masks:

- `ping: www.utexas.edu: Temporary failure in name resolution`
- Names resolve, but to `6.6.1.x`, and every connection hangs with 100% packet loss

## The trap

**`ping 8.8.8.8` succeeds in every one of these failure modes.** It's a literal IP, so it never touches DNS. It tells you routing is fine and nothing else. Diagnose by *what resolution returns*, never by whether raw IP connectivity works.

## Root cause

Three independent problems stacked. Each fix exposed the next.

### 1. GSA poisons DNS with synthetic IPs

The Global Secure Access client intercepts DNS and rewrites answers to synthetic addresses in `6.6.0.0/16`. Its filter driver is supposed to catch traffic to those addresses and tunnel it. But per Microsoft:

> a Windows Subsystem for Linux (WSL) doesn't acquire traffic from a client installed on the host machine.
> — [GSA known limitations](https://learn.microsoft.com/entra/global-secure-access/reference-current-known-limitations)

So WSL gets the synthetic IP but never the interception. `6.6.0.0/16` routes nowhere → blackhole.

Windows works fine because it *does* get the interception:

```
C:\> ping www.utexas.edu
Pinging www.utexas.edu [6.6.1.115] with 32 bytes of data:
Reply from 23.185.0.4: bytes=32 time=25ms TTL=51     <- real address, tunneled
```

WSL, same name, same moment:

```
$ ping www.utexas.edu
PING www.utexas.edu (6.6.1.115) 56(84) bytes of data.
19 packets transmitted, 0 received, 100% packet loss
```

### 2. `dnsTunneling=false` alone is NOT sufficient in mirrored mode

Microsoft's documented fix is `dnsTunneling=false`:

> When the Global Secure Access client for Windows is enabled on the host machine, outgoing connections from the WSL 2 environment might be blocked. To fix this issue, create a `.wslconfig` file that sets dnsTunneling to **false**.

And the mechanism, from [WSL troubleshooting](https://learn.microsoft.com/windows/wsl/troubleshooting#common-issues):

> The Global Secure Access Client ... has a feature to return a temporary address when resolving a name. Then the address is swapped to the actual address when a network connection is made. This can break WSL as **the WSL traffic is forwarded below much of the GSA client hooks**. We recommend disabling DNS Tunneling (`dnsTunneling=false`) or disabling Mirrored Mode (`networkingMode=nat`).

That guidance assumes WSL's DNS leaves outside the host stack. **`networkingMode=mirrored` puts it back on the host stack**, where GSA still catches UDP/53 — so with mirrored mode you need more than the documented fix.

Proof — same nameserver, two transports:

```
$ dig +short +notcp @45.90.28.0 www.utexas.edu A
6.6.1.115        <- synthetic; GSA hooks UDP/53

$ dig +short +tcp   @45.90.28.0 www.utexas.edu A
23.185.0.4       <- real; GSA does NOT hook TCP/53
```

GSA's own limitations doc confirms the asymmetry: it doesn't support DNS over TCP/53, DoH, DoT, or DNSSEC.

Also worth knowing: **data traffic was never affected, only DNS.** With GSA up and mirrored mode on, forcing a real IP worked perfectly:

```
$ curl -4 --resolve mirrors.fedoraproject.org:443:152.2.23.103 https://mirrors.fedoraproject.org/...
HTTP 200 in 0.19s
```

### 3. systemd-resolved is a second writer of `/etc/resolv.conf`

`/etc/wsl.conf` has `systemd=true`. Setting `generateResolvConf=false` stops *WSL* from writing `/etc/resolv.conf`, but **systemd-resolved reclaims it on every boot** as a symlink to `stub-resolv.conf` (`nameserver 127.0.0.53`).

Worse: with `generateResolvConf=false`, WSL feeds resolved no DNS servers at all, so the stub has zero upstreams:

```
$ resolvectl status
Global
    resolv.conf mode: stub
    (no DNS Servers line)
Link 2 (eth0)
    Current Scopes: LLMNR/IPv4      <- LLMNR only, no DNS
    Default Route: no
```

That is exactly what "Temporary failure in name resolution" means here. **A hand-written static `/etc/resolv.conf` will not survive.** DNS must be pinned in `resolved.conf.d`.

### Footnote: the `fec0::` red herring

Before any of this, `/etc/resolv.conf` contained only:

```
nameserver fec0:0:0:ffff::1
nameserver fec0:0:0:ffff::2
nameserver fec0:0:0:ffff::3
```

These are **Windows' default placeholder IPv6 DNS addresses**, present on any adapter with no explicit IPv6 DNS — not GSA's doing and not a sign of anything exotic. WSL has no route to `fec0::/10`, so all three are dead. They appear whenever mirrored mode copies the host DNS list and finds nothing real.

Chasing these wastes time: they are a *consequence* of having no real resolver, not a cause. Fix the resolver and they stop appearing.

## Working configuration

### 1. `%USERPROFILE%\.wslconfig`

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=false

[experimental]
hostAddressLoopback=true
```

### 2. `/etc/wsl.conf`

```ini
[boot]
systemd=true

[network]
generateResolvConf = false
```

### 3. `/etc/systemd/resolved.conf.d/10-gsa-bypass.conf`

```ini
[Resolve]
DNS=45.90.28.0#dns.nextdns.io 45.90.30.0#dns.nextdns.io
FallbackDNS=1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com
DNSOverTLS=yes
Domains=~.
```

DoT runs over TCP/853, which GSA cannot intercept. `Domains=~.` makes these the default route for all queries.

### Applying changes

| Changed | Required action |
|---|---|
| `.wslconfig` | `wsl --shutdown`, then reopen |
| `/etc/wsl.conf` | `wsl --shutdown`, then reopen |
| `resolved.conf.d/*` | `sudo systemctl restart systemd-resolved` |

`.wslconfig` and `wsl.conf` are read **only at boot** — testing before the restart gives misleading results, because all DNS is still hijacked regardless of which nameserver you query.

## Verification

```bash
# 1. resolved has upstreams and DoT is on
resolvectl status | head -8         # expect DNS Servers + "+DNSOverTLS"

# 2. real IPs, NOT 6.6.1.x  <- the test that actually matters
getent ahostsv4 www.utexas.edu      # expect 23.185.0.4
getent ahostsv4 mirrors.fedoraproject.org

# 3. end to end
ping -c 3 www.utexas.edu
sudo dnf makecache --refresh
```

Confirmed working with GSA running: ping 0% loss, all four repos refresh, Chromium under WSLg loads external sites.

### After a full power-down (2026-08-17)

The whole configuration is on-disk state, so nothing needs re-applying. Re-checked on a cold boot with GSA up:

```
resolvectl status
  Current DNS Server: 45.90.28.0#dns.nextdns.io
  Protocols: ... +DNSOverTLS
  DNS Domain: ~.

getent hosts www.utexas.edu     -> 2620:12a:8001::4   (real, not 6.6.1.x)
sudo dnf repoquery --refresh    -> succeeds
```

The one failure mode that would *not* survive a reboot is a hand-written `/etc/resolv.conf`; that is precisely why the config lives in `resolved.conf.d` instead. See root cause 3.

## Troubleshooting decision table

| Observation | Cause | Fix |
|---|---|---|
| Names resolve to `6.6.1.x` | GSA intercepting UDP/53 | DoT is off, or resolved fell back to UDP — check for `+DNSOverTLS` in `resolvectl status` |
| "Temporary failure in name resolution", resolv.conf → `stub-resolv.conf` | resolved has no upstreams | Restore the `resolved.conf.d` drop-in, restart resolved |
| resolv.conf shows `fec0:0:0:ffff::` | `generateResolvConf` back on, copying dead host placeholders | Re-add `generateResolvConf = false`, `wsl --shutdown` |
| DNS dead on hotel/airline wifi | Network blocks TCP/853; `DNSOverTLS=yes` is strict | See below |
| `ping 8.8.8.8` works so "networking is fine" | Meaningless — never touches DNS | Test with `getent`/`dig`, not `ping <ip>` |

### Networks that block TCP/853

`DNSOverTLS=yes` is strict: if 853 is blocked, DNS stops entirely rather than degrading. Captive portals hit this too.

```bash
sudo sed -i 's/^DNSOverTLS=yes/DNSOverTLS=opportunistic/' /etc/systemd/resolved.conf.d/10-gsa-bypass.conf
sudo systemctl restart systemd-resolved
```

GSA resumes poisoning answers while in `opportunistic` mode, so switch back to `yes` once on a normal network.

## Tradeoffs accepted

- **WSL DNS bypasses GSA entirely** — outside org filtering and visibility. This is Microsoft's own sanctioned workaround, and GSA was never inspecting WSL traffic anyway; it was only corrupting its DNS. Relevant if the machine is audited.
- **Any name that only resolves through the corporate resolver stops resolving in WSL.** Private/split-horizon zones now answer only on the Windows side. `gsa-bridge` exists to cover the ones that matter.
- **Rejected alternative: `networkingMode=nat`.** Microsoft's other suggestion, and it would work — at the cost of mirrored mode and `hostAddressLoopback`, which `gsa-bridge` depends on.

## Reverting

```bash
sudo rm /etc/systemd/resolved.conf.d/10-gsa-bypass.conf
# remove the [network] / generateResolvConf lines from /etc/wsl.conf
sudoedit /etc/wsl.conf
# then set dnsTunneling=true in %USERPROFILE%\.wslconfig and run: wsl --shutdown
```

## References

- [Known limitations for Global Secure Access](https://learn.microsoft.com/entra/global-secure-access/reference-current-known-limitations) — WSL 2 connectivity, virtualization support, secure DNS, DNS over TCP
- [Troubleshooting WSL](https://learn.microsoft.com/windows/wsl/troubleshooting#common-issues) — GSA client issues with WSL
- [Advanced settings configuration in WSL](https://learn.microsoft.com/windows/wsl/wsl-config)
