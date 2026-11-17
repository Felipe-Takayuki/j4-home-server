#!/data/data/com.termux/files/usr/bin/python3
"""Bloqueador de anúncios por DNS para o J4 (Termux, sem root).

Escuta em 127.0.0.1:5353 (UDP e TCP). O Tailscale expõe o TCP como DNS sobre TLS
na porta 853 (tailscale serve --tls-terminated-tcp), para o "DNS privado" do Android.
Domínios da lista (e seus subdomínios) recebem 0.0.0.0 / ::; o resto vai para o upstream.
Arquivos em ~/.dnsblock: blocklist.txt (hosts ou um domínio por linha), allow.txt, custom.txt.
SIGHUP recarrega as listas. Não registra consultas (privacidade); só contadores em stats.json.
"""
import json, os, signal, socket, socketserver, struct, subprocess, sys, threading, time
from collections import Counter

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, ".dnsblock")
LISTEN = ("127.0.0.1", int(os.environ.get("DNSBLOCK_PORT", "5353")))
UPSTREAMS = ["1.1.1.1", "9.9.9.9", "8.8.8.8"]
LIST_URL = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
MAX_AGE = 7 * 86400
TS_CMD = os.environ.get("TS_CMD", "ts")
LOCK = threading.Lock()
tailnet = {}   # nome do aparelho no tailnet -> {"A": [ipv4], "AAAA": [ipv6]}
state = {"block": frozenset(), "allow": frozenset()}
stats = {"day": time.strftime("%F"), "total": 0, "blocked": 0}
top = Counter()


def log(msg):
    sys.stderr.write("%s %s\n" % (time.strftime("%F %T"), msg)); sys.stderr.flush()


def read_domains(path):
    out = set()
    try:
        with open(path, errors="ignore") as f:
            for line in f:
                line = line.split("#", 1)[0].strip().lower()
                if not line:
                    continue
                parts = line.split()
                d = parts[1] if len(parts) >= 2 and parts[0] in ("0.0.0.0", "127.0.0.1") else parts[0]
                if d in ("localhost", "localhost.localdomain", "local", "broadcasthost", "0.0.0.0") or "." not in d:
                    continue
                out.add(d.rstrip("."))
    except FileNotFoundError:
        pass
    return out


def reload_lists(*_):
    b = read_domains(os.path.join(DIR, "blocklist.txt")) | read_domains(os.path.join(DIR, "custom.txt"))
    a = read_domains(os.path.join(DIR, "allow.txt"))
    b.add("saude.dnsblock.invalid")   # nome usado pelo bot para testar se o bloqueador responde
    state["block"], state["allow"] = frozenset(b), frozenset(a)
    log("listas carregadas: %d bloqueados, %d liberados" % (len(b), len(a)))


def update_list():
    tmp = os.path.join(DIR, "blocklist.new")
    try:
        subprocess.run(["curl", "-fsS", "-m", "120", "-o", tmp, LIST_URL], check=True, timeout=150)
        if len(read_domains(tmp)) < 10000:
            raise ValueError("lista nova pequena demais")
        os.replace(tmp, os.path.join(DIR, "blocklist.txt"))
        reload_lists()
        log("lista atualizada")
    except Exception as e:
        log("falha ao atualizar a lista: %s" % e)
        try: os.remove(tmp)
        except OSError: pass


def refresh_tailnet():
    """Nomes do tailnet (MagicDNS) não existem no DNS público; com o DNS privado do Android ligado,
    o Tailscale do celular não os resolve mais, então respondemos aqui a partir do `status --json`."""
    try:
        out = subprocess.run([TS_CMD, "status", "--json"], capture_output=True, timeout=15, check=True).stdout
        st = json.loads(out)
        nodes = [st.get("Self") or {}] + list((st.get("Peer") or {}).values())
        new = {}
        for n in nodes:
            name = (n.get("DNSName") or "").lower().rstrip(".")
            ips = n.get("TailscaleIPs") or []
            if name and ips:
                new[name] = {"A": [i for i in ips if ":" not in i], "AAAA": [i for i in ips if ":" in i]}
        if new:
            tailnet.clear(); tailnet.update(new)
            return len(new)
    except Exception as e:
        log("tailnet: %s" % e)
    return 0


def tailnet_loop():
    first = True
    while True:
        n = refresh_tailnet()
        if first: log("tailnet: %d aparelhos" % n); first = False
        time.sleep(60)


def maintenance():
    while True:
        try:
            p = os.path.join(DIR, "blocklist.txt")
            if not os.path.exists(p) or time.time() - os.path.getmtime(p) > MAX_AGE:
                update_list()
            with LOCK:
                snap = dict(stats, top=top.most_common(10))
            tmp = os.path.join(DIR, "stats.json.tmp")
            with open(tmp, "w") as f: json.dump(snap, f)
            os.replace(tmp, os.path.join(DIR, "stats.json"))
        except Exception as e:
            log("manutenção: %s" % e)
        time.sleep(60)


def parse_question(m):
    """Devolve (nome, tipo, fim_da_pergunta) ou None se a mensagem não for uma consulta simples."""
    if len(m) < 17 or (m[2] & 0x80) or struct.unpack("!H", m[4:6])[0] < 1:
        return None
    i, labels = 12, []
    while True:
        if i >= len(m): return None
        n = m[i]
        if n == 0: i += 1; break
        if n & 0xC0 or i + 1 + n > len(m): return None
        labels.append(m[i + 1:i + 1 + n].decode("ascii", "ignore").lower()); i += 1 + n
    if i + 4 > len(m): return None
    return ".".join(labels), struct.unpack("!H", m[i:i + 2])[0], i + 4


def is_blocked(name):
    if not name: return False
    parts = name.split(".")
    for k in range(len(parts) - 1):          # nunca testa só o TLD
        d = ".".join(parts[k:])
        if d in state["allow"]: return False
        if d in state["block"]: return True
    return False


def blocked_reply(m, qtype, qend):
    flags = 0x8180   # QR, RD, RA, sem erro
    hdr = m[:2] + struct.pack("!H", flags) + b"\x00\x01"
    q = m[12:qend]
    if qtype == 1:      # A -> 0.0.0.0
        return hdr + b"\x00\x01\x00\x00\x00\x00" + q + b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x01\x2c\x00\x04\x00\x00\x00\x00"
    if qtype == 28:     # AAAA -> ::
        return hdr + b"\x00\x01\x00\x00\x00\x00" + q + b"\xc0\x0c\x00\x1c\x00\x01\x00\x00\x01\x2c\x00\x10" + b"\x00" * 16
    return hdr + b"\x00\x00\x00\x00\x00\x00" + q   # outros tipos: NOERROR vazio


def tailnet_reply(m, name, qtype, qend):
    """Resposta para um nome do tailnet, ou None se não for um (ou o tipo não for A/AAAA)."""
    rec = tailnet.get(name)
    if rec is None: return None
    ips = rec["A"] if qtype == 1 else rec["AAAA"] if qtype == 28 else []
    fam = socket.AF_INET if qtype == 1 else socket.AF_INET6
    body = b""
    for ip in ips:
        raw = socket.inet_pton(fam, ip)
        body += b"\xc0\x0c" + struct.pack("!HHIH", qtype, 1, 60, len(raw)) + raw
    hdr = m[:2] + b"\x81\x80" + b"\x00\x01" + struct.pack("!H", len(ips)) + b"\x00\x00\x00\x00"
    return hdr + m[12:qend] + body


def forward(m):
    for up in UPSTREAMS:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2.5)
            s.sendto(m, (up, 53)); r, _ = s.recvfrom(4096); s.close()
            if len(r) >= 12 and r[:2] == m[:2]:
                if r[2] & 0x02:      # truncado: repete por TCP
                    t = socket.create_connection((up, 53), timeout=4)
                    t.sendall(struct.pack("!H", len(m)) + m)
                    n = struct.unpack("!H", t.recv(2))[0]; buf = b""
                    while len(buf) < n:
                        c = t.recv(n - len(buf))
                        if not c: break
                        buf += c
                    t.close()
                    if len(buf) == n: return buf
                return r
        except Exception:
            continue
    return m[:2] + b"\x81\x82" + m[4:12]          # SERVFAIL


def answer(m):
    q = parse_question(m)
    if not q: return forward(m)
    name, qtype, qend = q
    t = tailnet_reply(m, name, qtype, qend)
    if t is not None: return t
    day = time.strftime("%F")
    blk = is_blocked(name)
    with LOCK:
        if stats["day"] != day: stats.update(day=day, total=0, blocked=0); top.clear()
        stats["total"] += 1
        if blk: stats["blocked"] += 1; top[name] += 1
    return blocked_reply(m, qtype, qend) if blk else forward(m)


class UDP(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        if len(data) >= 12:
            sock.sendto(answer(data), self.client_address)


class TCP(socketserver.BaseRequestHandler):
    def handle(self):
        c = self.request; c.settimeout(30)
        try:
            while True:
                h = c.recv(2)
                if len(h) < 2: return
                n = struct.unpack("!H", h)[0]; buf = b""
                while len(buf) < n:
                    chunk = c.recv(n - len(buf))
                    if not chunk: return
                    buf += chunk
                r = answer(buf)
                c.sendall(struct.pack("!H", len(r)) + r)
        except (socket.timeout, OSError):
            return


class TUDP(socketserver.ThreadingMixIn, socketserver.UDPServer): daemon_threads = True
class TTCP(socketserver.ThreadingMixIn, socketserver.TCPServer): daemon_threads = True; allow_reuse_address = True; request_queue_size = 64


if __name__ == "__main__":
    os.makedirs(DIR, exist_ok=True)
    reload_lists()
    signal.signal(signal.SIGHUP, reload_lists)
    threading.Thread(target=tailnet_loop, daemon=True).start()
    threading.Thread(target=maintenance, daemon=True).start()
    threading.Thread(target=TUDP(LISTEN, UDP).serve_forever, daemon=True).start()
    log("dnsblock ouvindo em %s:%d" % LISTEN)
    TTCP(LISTEN, TCP).serve_forever()
