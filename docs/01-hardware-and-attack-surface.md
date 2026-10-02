# 01 — Hardware & Attack Surface

> 👤 **Author:** Nipun Methmal · Part 1 of 9 · [← Index](../README.md) · [Next →](02-firmware-dump-and-extraction.md)

The Tozed **P11IDU** is the indoor unit of a Dialog (Sri Lanka) CPE bundle. On the shelf it looks
like an unremarkable 4G router; underneath it is a small OpenWrt machine that the vendor chose to
dress with their own Lua web interface. That single decision is what made this whole project
possible.

## Specifications

| | |
|---|---|
| **SoC** | MediaTek MT7628AN `ver:1 eco:2` (MIPS 24KEc, ~580 MHz) |
| **Wi‑Fi** | Single 2.4 GHz radio — `platform/10300000.wmac` |
| **Ethernet** | Integrated **rt305x-esw** switch, 7 ports, CPU @ 6 |
| **Flash** | 16 MB (`p11.bin` is a full 16 777 216-byte image) |
| **RAM** | 64 MB → 57.40 MiB presented to userspace |
| **Target** | `ramips/mt76x8` / `mipsel_24kc` |
| **Board name** | `tozed,p11idu` |

The board name matters — and **`tozed,p11idu` is not in OpenWrt upstream.** Verified 2 October 2026:

| Check | Result |
|---|---|
| `p11idu` anywhere in `openwrt/openwrt` | **0 matches** |
| `ramips/mt76x8` snapshot profiles | 134 total — **none** for Tozed/P11 |
| Anything under `downloads.openwrt.org/.../ramips/mt76x8/` | **no `tozed` or `p11` file** |
| The only Tozed device upstream | `tozed,zlt-s12-pro` — a **different** box, on **mt7621** |

So the image running on this unit carries a device tree that had to be written for this board by
somebody. Where that image came from, and what it takes to get it into OpenWrt properly, are
covered in [doc 06](06-installing-openwrt.md).

## The Ethernet switch

LuCI exposes it as `Switch "switch0" (rt305x-esw), ports: 7 (cpu @ 6)`, with VLAN functionality
enabled:

| VLAN | CPU | LAN 1 | LAN 2 | LAN 3 | WAN 1 | WAN 2 |
|------|-----|-------|-------|-------|-------|-------|
| **1** | tagged | untag | untag | untag | off | off |
| **2** | tagged | off | off | off | untag | untag |

Which becomes, in UCI:

```uci
config switch
        option name 'switch0'
        option reset '1'
        option enable_vlan '1'

config switch_vlan  '  VLAN 1 → br-lan (LAN side)
        option device 'switch0'
        option vlan '1'
        option ports '6t 0 1 3'

config switch_vlan  '  VLAN 2 → the old wired 'wan'
        option device 'switch0'
        option vlan '2'
        option ports '6t 2 4'
```

In the finished build **VLAN 2 is disabled** along with the `wan`/`wan6` interfaces — the outdoor
unit it was meant for isn't attached, and leaving it up installed a dead default route via
`172.19.2.254` that occasionally hijacked DNS. See [doc 08](08-verification.md).

> ✍️ Note — all ports are **10/100 Fast Ethernet**; only the CPU port is gigabit-capable. This
> matters when we later ask whether the device is an "L3 switch" in [doc 09](09-is-it-an-l3-switch.md).

## Listening services (stock firmware)

A TCP sweep of the stock device returned:

| Port | Service | Notes |
|------|---------|-------|
| **23** | Telnet | Login prompt — root shell, credentials unknown at this stage |
| **53** | DNS | Local resolver |
| **80** | HTTP | The Tozed web UI (`tz_www`), fronted by `/cgi-bin/lua.cgi` |
| **3002** | Proprietary text protocol | Answers every probe with `Can't Recognize this command! \| ERR CODE:-1` |
| **5060** | SIP | The firmware ships `siproxd.conf` and a full SIP stack |
| **9490** | Unknown | Open but not fingerprinted |

Port 3002 resisted everything tried: `HELP`, `help`, `?`, `version`, `status`, `shell`, raw HTTP,
JSON, and AT commands all returned the same error line. The web UI exposes `rpcapd_enable` /
`rpcapd_port` settings, so it is most likely the vendor's remote-packet-capture or cloud-management
channel. It was never a productive avenue — the web UI was.

## The web UI: an OpenWrt box in a vendor coat

Extracting the firmware (next document) revealed the architecture:

```
squashfs-root/
├── etc/
│   ├── preinit              ← stock OpenWrt
│   ├── config/              ← uci
│   └── uci-defaults/        ← uci-defaults.sh, procd.sh
├── lib/
│   ├── netifd/              ← stock OpenWrt netifd + hostapd.sh
│   ├── functions/procd.sh   ← stock OpenWrt
│   └── upgrade/platform.sh  ← stock OpenWrt sysupgrade hook
├── usr/lib/opkg/            ← stock OpenWrt package manager
├── usr/lib/lua/tz/          ← ★ vendor logic (cmd.lua, system.lua, wifi.lua, …)
└── tz_www/                  ← ★ vendor web root
    └── cgi-bin/lua.cgi      ← ★ 56 KB, the single HTTP entry point
```

So the vendor did not write a router from scratch — they took OpenWrt, disabled or ignored the
usual interfaces, and put a Lua CGI in front of it. Everything interesting lives in `tz_www/cgi-bin/lua.cgi`
and the `tz/*.lua` modules behind it.

That is the surface we go after in [doc 04](04-rce-cmd-145.md).

## Credentials visible without a shell

Two files, both from the firmware image itself:

**`/etc/shadow`** — the root password is **md5crypt** (`$1$`), a weak, salted MD5 scheme:

```
root:$1$<salt8>$<checksum22>:18127:0:99999:7:::
```

*(full hash withheld — it is the factory default from the distributed image, and publishing it
serves no purpose here. It is trivially recoverable from any copy of the firmware.)*

**`/etc/passwd`** — a second, unnamed-in-the-UI account with a 13-character DES-crypt hash:

```
test:<13-char DES crypt hash>:1000:1000:test:/tmp:/bin/ash
```

We built and validated an md5crypt cracker against the root hash
([`scripts/md5crypt-cracker.cs`](../scripts/md5crypt-cracker.cs), 3/3 known-answer vectors
passing). In the end **it was never needed** — the RCE in doc 04 handed us root directly, which made
cracking moot. The cracker is kept in the repository as a working, tested piece of code.

The web login, as it turned out, was considerably simpler than the hashes suggested: the **`admin`**
account with a single, non-default password — known to the owner, and deliberately **not** recorded
in this repository. (The username is the vendor's stock one; only the password was changed.) See
[doc 04 § authentication](04-rce-cmd-145.md#the-authentication-gate) for why that still didn't stop us.

---

> 📖 Next: [02 — Firmware dump & extraction](02-firmware-dump-and-extraction.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
