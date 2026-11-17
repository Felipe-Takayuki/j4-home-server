#!/usr/bin/env python3
"""Sends one DNS query over TLS (DoT, port 853) and prints the answer. Handy to test the ad blocker
through the tailnet exactly like Android's Private DNS does.

    python3 tools/dot-query.py j4.<your-tailnet>.ts.net doubleclick.net
    python3 tools/dot-query.py j4.<your-tailnet>.ts.net example.com AAAA
"""
import socket, ssl, struct, sys

TYPES = {"A": 1, "AAAA": 28, "HTTPS": 65, "TXT": 16, "MX": 15}


def query(server, name, qtype=1, port=853):
    msg = b"\xab\xcd\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"
    msg += b"".join(bytes([len(p)]) + p.encode() for p in name.rstrip(".").split(".")) + b"\x00"
    msg += struct.pack("!HH", qtype, 1)
    ctx = ssl.create_default_context()
    with socket.create_connection((server, port), 10) as raw, ctx.wrap_socket(raw, server_hostname=server) as s:
        s.sendall(struct.pack("!H", len(msg)) + msg)
        n = struct.unpack("!H", s.recv(2))[0]
        data = b""
        while len(data) < n:
            data += s.recv(n - len(data))
    rcode, answers = data[3] & 15, struct.unpack("!H", data[6:8])[0]
    ips = []
    i = len(msg)
    for _ in range(answers):
        i += 2
        rtype, _cls, _ttl, ln = struct.unpack("!HHIH", data[i:i + 10]); i += 10
        raw_rd = data[i:i + ln]; i += ln
        if rtype in (1, 28):
            ips.append(socket.inet_ntop(socket.AF_INET if rtype == 1 else socket.AF_INET6, raw_rd))
    return rcode, ips


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    t = TYPES.get(sys.argv[3].upper(), 1) if len(sys.argv) > 3 else 1
    rc, ips = query(sys.argv[1], sys.argv[2], t)
    print("rcode=%d %s" % (rc, ips or "(no address records)"))
