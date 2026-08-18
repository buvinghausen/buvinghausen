#!/usr/bin/env python3
"""WSL half of gsa-bridge.

Listens on a dedicated 127.0.0.x address per endpoint, on the endpoint's REAL port, and
forwards to the matching loopback port on Windows where gsa-bridge.ps1 dials the FQDN by
name so GSA intercepts it.

The per-endpoint address mapping lives here rather than on Windows because WSL's mirrored
networking bridges only 127.0.0.1 to the host; a Windows listener on 127.0.0.5 is not
reachable from WSL. See ../spec.md.

Binding 443 and 1433 needs CAP_NET_BIND_SERVICE (the systemd unit grants it) or root.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import os
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "endpoints.tsv"
WINDOWS_HOST = "127.0.0.1"  # mirrored networking bridges this, and only this, to Windows

log = logging.getLogger("gsa-bridge")


@dataclass(frozen=True)
class Endpoint:
    name: str
    fqdn: str
    port: int
    wsl_addr: str
    bridge_port: int


class ConfigError(Exception):
    """Raised for any malformed or internally inconsistent endpoints.tsv."""


def parse_config(text: str) -> list[Endpoint]:
    """Parse endpoints.tsv, rejecting anything that would silently misroute traffic."""
    endpoints: list[Endpoint] = []

    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        fields = line.split("\t")
        if len(fields) != 5:
            raise ConfigError(
                f"line {lineno}: expected 5 tab-separated fields, got {len(fields)}: {line!r}"
            )

        name, fqdn, port_s, wsl_addr, bridge_port_s = (f.strip() for f in fields)

        if wsl_addr == "-" or bridge_port_s == "-":
            raise ConfigError(
                f"line {lineno}: {name!r} has an unassigned wsl_addr/bridge_port - "
                "run sync_hosts.py --assign"
            )

        try:
            port = int(port_s)
            bridge_port = int(bridge_port_s)
        except ValueError as exc:
            raise ConfigError(f"line {lineno}: port must be an integer ({exc})") from exc

        for label, value in (("port", port), ("bridge_port", bridge_port)):
            if not 1 <= value <= 65535:
                raise ConfigError(f"line {lineno}: {label} {value} out of range 1-65535")

        if not wsl_addr.startswith("127."):
            raise ConfigError(
                f"line {lineno}: wsl_addr {wsl_addr!r} must be a 127.x loopback address"
            )

        endpoints.append(Endpoint(name, fqdn, port, wsl_addr, bridge_port))

    if not endpoints:
        raise ConfigError("no endpoints defined")

    _validate_uniqueness(endpoints)
    return endpoints


def _validate_uniqueness(endpoints: list[Endpoint]) -> None:
    seen_bridge: dict[int, str] = {}
    seen_bind: dict[tuple[str, int], str] = {}
    fqdn_addr: dict[str, str] = {}

    for ep in endpoints:
        # Two listeners cannot share a Windows loopback port.
        if ep.bridge_port in seen_bridge:
            raise ConfigError(
                f"duplicate bridge_port {ep.bridge_port}: {seen_bridge[ep.bridge_port]!r} and {ep.name!r}"
            )
        seen_bridge[ep.bridge_port] = ep.name

        # Nor the same address:port on the WSL side.
        bind = (ep.wsl_addr, ep.port)
        if bind in seen_bind:
            raise ConfigError(
                f"duplicate binding {ep.wsl_addr}:{ep.port}: {seen_bind[bind]!r} and {ep.name!r}"
            )
        seen_bind[bind] = ep.name

        # One FQDN must map to exactly one address, or /etc/hosts is ambiguous.
        # Sharing an address across ports (Service Bus 5671 + 443) is expected.
        if ep.fqdn in fqdn_addr and fqdn_addr[ep.fqdn] != ep.wsl_addr:
            raise ConfigError(
                f"fqdn {ep.fqdn!r} mapped to two addresses: "
                f"{fqdn_addr[ep.fqdn]} and {ep.wsl_addr}"
            )
        fqdn_addr[ep.fqdn] = ep.wsl_addr


def load_config(path: Path) -> list[Endpoint]:
    try:
        return parse_config(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"config not found: {path}") from exc


async def _pump(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while chunk := await reader.read(65536):
            writer.write(chunk)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError, OSError):
        pass
    finally:
        try:
            writer.close()
        except OSError:
            pass


def _make_handler(ep: Endpoint):
    async def handle(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
        peer = client_writer.get_extra_info("peername")
        try:
            up_reader, up_writer = await asyncio.wait_for(
                asyncio.open_connection(WINDOWS_HOST, ep.bridge_port), timeout=10
            )
        except (ConnectionRefusedError, asyncio.TimeoutError, OSError) as exc:
            # Almost always means the Windows relay is not running.
            log.error(
                "%s: cannot reach Windows relay at %s:%d (%s) - is gsa-bridge.ps1 running?",
                ep.name, WINDOWS_HOST, ep.bridge_port, exc,
            )
            client_writer.close()
            return

        log.info("%s: %s -> %s:%d", ep.name, peer, ep.fqdn, ep.port)
        await asyncio.gather(
            _pump(client_reader, up_writer),
            _pump(up_reader, client_writer),
        )
        log.debug("%s: closed", ep.name)

    return handle


async def serve(endpoints: list[Endpoint]) -> None:
    servers = []
    for ep in endpoints:
        try:
            server = await asyncio.start_server(
                _make_handler(ep), ep.wsl_addr, ep.port, reuse_address=True
            )
        except PermissionError:
            log.error(
                "%s: permission denied binding %s:%d - ports below 1024 need "
                "CAP_NET_BIND_SERVICE or root (skipped)",
                ep.name, ep.wsl_addr, ep.port,
            )
            continue
        except OSError as exc:
            # One bad bind must not take down the rest.
            log.error("%s: cannot bind %s:%d - %s (skipped)", ep.name, ep.wsl_addr, ep.port, exc)
            continue

        servers.append(server)
        log.info("listen %s:%-5d -> windows 127.0.0.1:%-5d  [%s]",
                 ep.wsl_addr, ep.port, ep.bridge_port, ep.name)

    if not servers:
        log.error("no listeners bound; nothing to do")
        raise SystemExit(1)

    log.info("ready: %d/%d listeners. Passive - nothing is attempted until a client connects.",
             len(servers), len(endpoints))
    await asyncio.gather(*(s.serve_forever() for s in servers))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="WSL half of gsa-bridge")
    parser.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--check", action="store_true",
                        help="validate the config and exit without binding anything")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s",
        datefmt="%H:%M:%S",
    )

    try:
        endpoints = load_config(args.config)
    except ConfigError as exc:
        log.error("%s", exc)
        return 2

    if args.check:
        print(f"OK: {len(endpoints)} endpoints, no conflicts")
        for ep in endpoints:
            print(f"  {ep.name:<13} {ep.wsl_addr}:{ep.port:<5} -> 127.0.0.1:{ep.bridge_port} ({ep.fqdn})")
        return 0

    try:
        asyncio.run(serve(endpoints))
    except KeyboardInterrupt:
        log.info("stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
