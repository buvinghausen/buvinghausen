#!/usr/bin/env python3
"""Tests for gsa-bridge.

    python3 test_gsa_bridge.py                    # config tests only
    GSA_BRIDGE_INTEGRATION=1 python3 test_gsa_bridge.py   # + live end-to-end tests

Integration tests need both relays running and GSA up.
"""
from __future__ import annotations

import os
import socket
import ssl
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gsa_bridge import ConfigError, load_config, parse_config  # noqa: E402
from sync_hosts import render_block, splice  # noqa: E402

CONFIG = Path(__file__).resolve().parent.parent / "endpoints.tsv"
INTEGRATION = os.environ.get("GSA_BRIDGE_INTEGRATION") == "1"

HEADER = "# name\tfqdn\tport\twsl_addr\tbridge_port\n"


def row(name, fqdn, port, addr, bport):
    return f"{name}\t{fqdn}\t{port}\t{addr}\t{bport}\n"


class TestParseConfig(unittest.TestCase):
    def test_parses_a_valid_row(self):
        eps = parse_config(HEADER + row("sql-dev", "sql.example.net", 1433, "127.0.0.11", 14001))
        self.assertEqual(len(eps), 1)
        self.assertEqual(eps[0].name, "sql-dev")
        self.assertEqual(eps[0].port, 1433)
        self.assertEqual(eps[0].bridge_port, 14001)

    def test_ignores_comments_and_blank_lines(self):
        text = "# a comment\n\n   \n" + row("a", "a.example.net", 443, "127.0.0.11", 14001)
        self.assertEqual(len(parse_config(text)), 1)

    def test_rejects_wrong_field_count(self):
        with self.assertRaisesRegex(ConfigError, "expected 5 tab-separated"):
            parse_config("a\tb\tc\n")

    def test_rejects_unassigned_placeholder(self):
        with self.assertRaisesRegex(ConfigError, "unassigned"):
            parse_config(row("a", "a.example.net", 443, "-", "-"))

    def test_rejects_non_loopback_address(self):
        with self.assertRaisesRegex(ConfigError, "must be a 127"):
            parse_config(row("a", "a.example.net", 443, "192.168.1.5", 14001))

    def test_rejects_out_of_range_port(self):
        with self.assertRaisesRegex(ConfigError, "out of range"):
            parse_config(row("a", "a.example.net", 70000, "127.0.0.11", 14001))

    def test_rejects_non_integer_port(self):
        with self.assertRaisesRegex(ConfigError, "must be an integer"):
            parse_config(row("a", "a.example.net", "https", "127.0.0.11", 14001))

    def test_rejects_empty_config(self):
        with self.assertRaisesRegex(ConfigError, "no endpoints"):
            parse_config("# only comments\n")

    def test_rejects_duplicate_bridge_port(self):
        text = (row("a", "a.example.net", 443, "127.0.0.11", 14001) +
                row("b", "b.example.net", 443, "127.0.0.12", 14001))
        with self.assertRaisesRegex(ConfigError, "duplicate bridge_port"):
            parse_config(text)

    def test_rejects_duplicate_addr_port_binding(self):
        text = (row("a", "a.example.net", 443, "127.0.0.11", 14001) +
                row("b", "b.example.net", 443, "127.0.0.11", 14002))
        with self.assertRaisesRegex(ConfigError, "duplicate binding"):
            parse_config(text)

    def test_rejects_one_fqdn_on_two_addresses(self):
        text = (row("a1", "a.example.net", 443, "127.0.0.11", 14001) +
                row("a2", "a.example.net", 5671, "127.0.0.12", 14002))
        with self.assertRaisesRegex(ConfigError, "mapped to two addresses"):
            parse_config(text)

    def test_allows_one_address_across_two_ports(self):
        """Service Bus needs AMQP 5671 and WebSockets 443 on the same host."""
        text = (row("sb-amqp", "sb.example.net", 5671, "127.0.0.23", 14013) +
                row("sb-ws", "sb.example.net", 443, "127.0.0.23", 14016))
        self.assertEqual(len(parse_config(text)), 2)


class TestRealConfig(unittest.TestCase):
    def test_shipped_config_is_valid(self):
        eps = load_config(CONFIG)
        self.assertEqual(len(eps), 18, "expected 18 listeners across 15 hosts")
        self.assertEqual(len({e.fqdn for e in eps}), 15)

    def test_sql_uses_privatelink_fqdn(self):
        """The customer-facing database.windows.net names do not resolve on this host."""
        for ep in load_config(CONFIG):
            if ep.port == 1433:
                self.assertIn(".privatelink.", ep.fqdn)


class TestHostsBlock(unittest.TestCase):
    def setUp(self):
        self.eps = parse_config(
            row("sb-amqp", "sb.example.net", 5671, "127.0.0.23", 14013) +
            row("sb-ws", "sb.example.net", 443, "127.0.0.23", 14016) +
            row("kv", "kv.example.net", 443, "127.0.0.20", 14010)
        )

    def test_one_line_per_distinct_fqdn(self):
        body = [l for l in render_block(self.eps).splitlines() if not l.startswith("#")]
        self.assertEqual(len(body), 2)

    def test_appends_when_no_block_present(self):
        result = splice("127.0.0.1 localhost\n", render_block(self.eps))
        self.assertIn("127.0.0.1 localhost", result)
        self.assertIn("sb.example.net", result)

    def test_replaces_existing_block_without_duplicating(self):
        once = splice("127.0.0.1 localhost\n", render_block(self.eps))
        twice = splice(once, render_block(self.eps))
        self.assertEqual(once, twice, "re-running must be idempotent")
        self.assertEqual(twice.count("sb.example.net"), 1)

    def test_preserves_unrelated_entries(self):
        original = "127.0.0.1 localhost\n10.0.0.5 my-other-host\n"
        result = splice(original, render_block(self.eps))
        self.assertIn("10.0.0.5 my-other-host", result)

    def test_rejects_unterminated_block(self):
        broken = "127.0.0.1 localhost\n" + render_block(self.eps).replace("# END gsa-bridge\n", "")
        with self.assertRaisesRegex(ConfigError, "no END marker"):
            splice(broken, render_block(self.eps))


def _endpoint(name: str):
    for ep in load_config(CONFIG):
        if ep.name == name:
            return ep
    raise AssertionError(f"no endpoint named {name}")


@unittest.skipUnless(INTEGRATION, "set GSA_BRIDGE_INTEGRATION=1 with both relays running")
class TestEndToEnd(unittest.TestCase):
    def test_sql_prelogin_returns_tds_response(self):
        """Drive a real TDS PRELOGIN through the full bridge and expect a 0x04 reply."""
        ep = _endpoint("sql-dev")
        body = (
            bytes([0x00]) + (11).to_bytes(2, "big") + (6).to_bytes(2, "big") +
            bytes([0x01]) + (17).to_bytes(2, "big") + (1).to_bytes(2, "big") +
            bytes([0xFF]) + b"\x09\x00\x00\x00\x00\x00" + b"\x00"
        )
        pkt = (bytes([0x12, 0x01]) + (8 + len(body)).to_bytes(2, "big") +
               b"\x00\x00" + bytes([0x01, 0x00]) + body)

        with socket.create_connection((ep.wsl_addr, ep.port), timeout=15) as s:
            s.settimeout(15)
            s.sendall(pkt)
            data = s.recv(4096)

        self.assertTrue(data, "no bytes returned through the bridge")
        self.assertEqual(data[0], 0x04, f"expected TDS response 0x04, got 0x{data[0]:02x}")

    def test_https_endpoint_completes_tls_with_valid_cert(self):
        """Proves the real hostname survives end to end: cert validation must succeed."""
        ep = _endpoint("kv-dev")
        ctx = ssl.create_default_context()
        with socket.create_connection((ep.wsl_addr, ep.port), timeout=15) as raw:
            with ctx.wrap_socket(raw, server_hostname=ep.fqdn) as tls:
                self.assertTrue(tls.getpeercert(), "no peer certificate")
                tls.sendall(
                    f"GET / HTTP/1.1\r\nHost: {ep.fqdn}\r\nConnection: close\r\n\r\n".encode()
                )
                self.assertTrue(tls.recv(64).startswith(b"HTTP/"), "no HTTP response")

    def test_refuses_fast_when_windows_relay_is_absent(self):
        """A dead bridge port must refuse immediately, not hang."""
        with self.assertRaises((ConnectionRefusedError, OSError)):
            socket.create_connection(("127.0.0.1", 14999), timeout=5).close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
