#!/usr/bin/env python3
"""Keep /etc/hosts in step with endpoints.tsv, and allocate addresses for new rows.

Two jobs:
  --assign   fill in wsl_addr/bridge_port for rows written as "-", in endpoints.tsv
  (default)  regenerate the managed block in /etc/hosts

The managed block is delimited by markers, so anything else in /etc/hosts is left alone.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gsa_bridge import ConfigError, Endpoint, load_config  # noqa: E402

HOSTS = Path("/etc/hosts")
DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "endpoints.tsv"
BEGIN = "# BEGIN gsa-bridge (managed by wsl/sync_hosts.py - do not edit by hand)"
END = "# END gsa-bridge"

ADDR_PREFIX = "127.0.0."
ADDR_FIRST = 11
BRIDGE_FIRST = 14001


def render_block(endpoints: list[Endpoint]) -> str:
    """One line per distinct FQDN; Service Bus shares an address across its two ports."""
    seen: dict[str, str] = {}
    for ep in endpoints:
        seen.setdefault(ep.fqdn, ep.wsl_addr)

    width = max((len(a) for a in seen.values()), default=10)
    lines = [BEGIN]
    lines += [f"{addr:<{width}}  {fqdn}" for fqdn, addr in seen.items()]
    lines.append(END)
    return "\n".join(lines) + "\n"


def splice(existing: str, block: str) -> str:
    """Replace the managed block, or append it if absent. Everything else is preserved."""
    lines = existing.splitlines(keepends=True)
    out, skipping, replaced = [], False, False

    for line in lines:
        if line.strip() == BEGIN:
            skipping = True
            out.append(block)
            replaced = True
            continue
        if skipping:
            if line.strip() == END:
                skipping = False
            continue
        out.append(line)

    if skipping:
        raise ConfigError("/etc/hosts has a BEGIN marker with no END marker; fix it by hand")

    if not replaced:
        if out and not out[-1].endswith("\n"):
            out.append("\n")
        out.append("\n" + block)

    return "".join(out)


def assign(config_path: Path) -> int:
    """Fill in '-' placeholders, reusing an FQDN's existing address when it has one."""
    text = config_path.read_text(encoding="utf-8")
    lines = text.splitlines()

    used_addrs: set[str] = set()
    used_ports: set[int] = set()
    fqdn_addr: dict[str, str] = {}

    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != 5:
            continue
        if f[3] != "-":
            used_addrs.add(f[3])
            fqdn_addr.setdefault(f[1], f[3])
        if f[4] != "-":
            try:
                used_ports.add(int(f[4]))
            except ValueError:
                pass

    def next_addr() -> str:
        n = ADDR_FIRST
        while f"{ADDR_PREFIX}{n}" in used_addrs:
            n += 1
            if n > 254:
                raise ConfigError("ran out of 127.0.0.x addresses")
        addr = f"{ADDR_PREFIX}{n}"
        used_addrs.add(addr)
        return addr

    def next_port() -> int:
        p = BRIDGE_FIRST
        while p in used_ports:
            p += 1
            if p > 65535:
                raise ConfigError("ran out of bridge ports")
        used_ports.add(p)
        return p

    changed = 0
    out = []
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            out.append(line)
            continue
        f = line.split("\t")
        if len(f) != 5:
            out.append(line)
            continue

        if f[3] == "-":
            # Same host on another port keeps the same address.
            f[3] = fqdn_addr.get(f[1]) or next_addr()
            fqdn_addr.setdefault(f[1], f[3])
            changed += 1
        if f[4] == "-":
            f[4] = str(next_port())
            changed += 1
        out.append("\t".join(f))

    if changed:
        config_path.write_text("\n".join(out) + "\n", encoding="utf-8")
        print(f"assigned {changed} value(s) in {config_path}")
    else:
        print("nothing to assign")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="sync /etc/hosts with endpoints.tsv")
    parser.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--assign", action="store_true",
                        help="allocate wsl_addr/bridge_port for rows marked '-'")
    parser.add_argument("-n", "--dry-run", action="store_true",
                        help="print the block and the resulting /etc/hosts diff, write nothing")
    args = parser.parse_args(argv)

    try:
        if args.assign:
            return assign(args.config)

        endpoints = load_config(args.config)
        block = render_block(endpoints)

        if args.dry_run:
            print(block, end="")
            return 0

        current = HOSTS.read_text(encoding="utf-8")
        updated = splice(current, block)

        if current == updated:
            print("/etc/hosts already up to date")
            return 0

        if os.geteuid() != 0:
            print("need root to write /etc/hosts - re-run with sudo", file=sys.stderr)
            return 1

        HOSTS.write_text(updated, encoding="utf-8")
        print(f"/etc/hosts updated ({len(block.splitlines()) - 2} entries)")
        return 0

    except ConfigError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
