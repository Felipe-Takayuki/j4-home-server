"""Offline tests for dnsblock/dnsblock.py (no phone, no internet needed).  Run: python3 -m unittest -v tests/test_dnsblock.py"""
import importlib.util, json, os, socket, stat, struct, sys, tempfile, threading, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_home = tempfile.mkdtemp()
os.environ["HOME"] = _home                       # the module keeps its files under ~/.dnsblock
spec = importlib.util.spec_from_file_location("dnsblock", os.path.join(ROOT, "dnsblock", "dnsblock.py"))
db = importlib.util.module_from_spec(spec); spec.loader.exec_module(db)


def make_query(name, qtype=1, ident=b"\x12\x34"):
    q = ident + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    q += b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\x00"
    return q + struct.pack("!HH", qtype, 1)


def records(resp, qlen):
    """(rcode, [ip strings]) from a response to a query of length qlen."""
    an, i, out = struct.unpack("!H", resp[6:8])[0], qlen, []
    for _ in range(an):
        i += 2
        t, _c, _ttl, ln = struct.unpack("!HHIH", resp[i:i + 10]); i += 10
        out.append(socket.inet_ntop(socket.AF_INET if t == 1 else socket.AF_INET6, resp[i:i + ln])); i += ln
    return resp[3] & 15, out


class Lists(unittest.TestCase):
    def setUp(self):
        d = os.path.join(_home, ".dnsblock"); os.makedirs(d, exist_ok=True)
        def put(name, text):
            with open(os.path.join(d, name), "w") as f: f.write(text)
        put("blocklist.txt", "# comment\n127.0.0.1 localhost\n0.0.0.0 0.0.0.0\n0.0.0.0 ads.example.com  # trailing\n"
                             "0.0.0.0 doubleclick.net\nplain-domain.org\n")
        put("allow.txt", "ok.doubleclick.net\n")
        put("custom.txt", "mine.test\n")
        db.reload_lists()

    def test_hosts_and_plain_formats_are_parsed(self):
        self.assertTrue(db.is_blocked("ads.example.com"))
        self.assertTrue(db.is_blocked("plain-domain.org"))
        self.assertTrue(db.is_blocked("mine.test"))          # custom.txt
        self.assertNotIn("localhost", db.state["block"])

    def test_subdomains_are_blocked_but_not_siblings_or_tld(self):
        self.assertTrue(db.is_blocked("a.b.doubleclick.net"))
        self.assertFalse(db.is_blocked("example.com"))        # parent of a blocked name
        self.assertFalse(db.is_blocked("net"))
        self.assertFalse(db.is_blocked(""))

    def test_allowlist_wins(self):
        self.assertFalse(db.is_blocked("ok.doubleclick.net"))
        self.assertFalse(db.is_blocked("x.ok.doubleclick.net"))

    def test_health_probe_name_is_always_blocked(self):
        self.assertTrue(db.is_blocked("saude.dnsblock.invalid"))


class Packets(unittest.TestCase):
    def test_parse_question(self):
        q = make_query("Ads.Example.com", 28)
        name, qtype, qend = db.parse_question(q)
        self.assertEqual((name, qtype, qend), ("ads.example.com", 28, len(q)))

    def test_parse_rejects_garbage_and_responses(self):
        self.assertIsNone(db.parse_question(b"\x00" * 5))
        resp = bytearray(make_query("a.com")); resp[2] |= 0x80
        self.assertIsNone(db.parse_question(bytes(resp)))
        self.assertIsNone(db.parse_question(make_query("a.com")[:-3]))

    def test_blocked_replies(self):
        for qtype, expect in ((1, ["0.0.0.0"]), (28, ["::"]), (65, [])):
            q = make_query("ads.example.com", qtype)
            _n, t, qend = db.parse_question(q)
            r = db.blocked_reply(q, t, qend)
            self.assertEqual(r[:2], q[:2])                    # same transaction id
            self.assertEqual(records(r, len(q)), (0, expect))
            self.assertTrue(r[2] & 0x80)                      # QR bit: it is a response


class Tailnet(unittest.TestCase):
    def setUp(self):
        db.tailnet.clear()
        db.tailnet["j4.example.ts.net"] = {"A": ["100.64.0.1"], "AAAA": ["fd7a::1"]}

    def test_answers_from_tailnet(self):
        for name, qtype, expect in (("j4.example.ts.net", 1, ["100.64.0.1"]), ("j4.example.ts.net", 28, ["fd7a::1"]),
                                    ("j4.example.ts.net", 65, [])):
            q = make_query(name, qtype); _n, t, qend = db.parse_question(q)
            self.assertEqual(records(db.tailnet_reply(q, name, t, qend), len(q)), (0, expect))

    def test_unknown_name_falls_through(self):
        q = make_query("other.example.ts.net"); _n, t, qend = db.parse_question(q)
        self.assertIsNone(db.tailnet_reply(q, "other.example.ts.net", t, qend))

    def test_refresh_reads_tailscale_status_json(self):
        status = {"Self": {"DNSName": "J4.example.ts.net.", "TailscaleIPs": ["100.64.0.1", "fd7a::1"]},
                  "Peer": {"k": {"DNSName": "phone.example.ts.net.", "TailscaleIPs": ["100.64.0.2"]}}}
        fake = os.path.join(_home, "fake-ts")
        with open(fake, "w") as f: f.write("#!/bin/sh\ncat <<'EOF'\n%s\nEOF\n" % json.dumps(status))
        os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)
        old, db.TS_CMD = db.TS_CMD, fake
        try:
            self.assertEqual(db.refresh_tailnet(), 2)
        finally:
            db.TS_CMD = old
        self.assertEqual(db.tailnet["j4.example.ts.net"]["A"], ["100.64.0.1"])
        self.assertEqual(db.tailnet["phone.example.ts.net"]["AAAA"], [])


class EndToEnd(unittest.TestCase):
    """Real UDP and TCP servers on random loopback ports, using only locally-answered names."""
    @classmethod
    def setUpClass(cls):
        Lists.setUp(Lists)
        db.tailnet.clear(); db.tailnet["j4.example.ts.net"] = {"A": ["100.64.0.1"], "AAAA": []}
        cls.udp = db.TUDP(("127.0.0.1", 0), db.UDP); cls.tcp = db.TTCP(("127.0.0.1", 0), db.TCP)
        for s in (cls.udp, cls.tcp):
            threading.Thread(target=s.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        for s in (cls.udp, cls.tcp): s.shutdown(); s.server_close()

    def test_udp(self):
        q = make_query("ads.example.com")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(3); s.sendto(q, self.udp.server_address); r, _ = s.recvfrom(512)
        self.assertEqual(records(r, len(q)), (0, ["0.0.0.0"]))

    def test_tcp_with_two_queries_on_one_connection(self):
        c = socket.create_connection(self.tcp.server_address, 3)
        for name, expect in (("ads.example.com", ["0.0.0.0"]), ("j4.example.ts.net", ["100.64.0.1"])):
            q = make_query(name); c.sendall(struct.pack("!H", len(q)) + q)
            n = struct.unpack("!H", c.recv(2))[0]; r = b""
            while len(r) < n: r += c.recv(n - len(r))
            self.assertEqual(records(r, len(q)), (0, expect))
        c.close()


if __name__ == "__main__":
    unittest.main()
