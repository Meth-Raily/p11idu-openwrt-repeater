# 02 — Firmware Dump & Extraction

> 👤 **Author:** Nipun Methmal · Part 2 of 9 · [← Index](../README.md) · [Next →](03-reconnaissance.md)

You cannot reason about a black box. Step one of this project was getting the stock firmware off the
device and turning it into readable Lua source.

## The image

| | |
|---|---|
| **File** | `p11.bin` |
| **Size** | 16 777 216 bytes (exactly 16 MB — a raw flash read) |
| **Acquired** | 28 September 2026 |
| **Extraction result** | 2 627 entries |

A 16 MB raw dump means the whole SPI NOR contents were read — bootloader, factory data, and both
filesystems. This image is **not committed to this repository** (it is vendor-copyrighted and 16 MB
of binary); `.gitignore` blocks `*.bin` and the extracted tree so it cannot be added by accident.

## What was inside

```
_p11.bin.extracted/
├── 6C0000.jffs2              9 699 328 B   ← writable JFFS2 overlay
├── 167A47.squashfs           5 541 194 B   ← read-only rootfs
├── 50040                     3 401 756 B   ← carved blob
├── 50040.7z                 16 449 472 B   ← 7z archive found at offset 0x50040
├── _50040.extracted/
│   ├── 2C84C4.xz               484 184 B
│   ├── 33E618.cpio                 516 B
│   └── cpio-root/
├── squashfs-root/                             ← ★ the root filesystem we care about
└── squashfs-root-0/                           ← duplicate carve of the same tree
```

Two filesystems, as expected for OpenWrt: a **squashfs** base you can't write, plus a **JFFS2**
overlay holding `/etc/config` and anything else modified at runtime. That layout is precisely why
the stock `sysupgrade` machinery worked later.

### Reproducing it

The same tree can be rebuilt from a 16 MB dump with standard tooling:

```sh
binwalk -e p11.bin                 # carve the squashfs / jffs2 / 7z members
7z x 50040.7z                      # the inner archive
unsquashfs -d squashfs-root 167A47.squashfs
```

Exact member offsets will vary if Tozed revise the image.

## The files that mattered

| Path in image | Size | Why it mattered |
|---|---|---|
| `tz_www/cgi-bin/lua.cgi` | 56 091 B | **The entire HTTP API.** Request dispatcher, session gate, `switch[cmd]` table |
| `usr/lib/lua/tz/cmd.lua` | 49 909 B | CLI/LED helpers, module loading |
| `usr/lib/lua/tz/system.lua` | 35 009 B | ★ contains `system_network_tool()` — the vulnerable function |
| `usr/lib/lua/tz/wifi.lua` | 59 397 B | Wi‑Fi config handlers |
| `usr/lib/lua/tz/firewall.lua` | 44 748 B | Firewall/ACL handlers |
| `usr/lib/lua/tz/network.lua` | 7 197 B | Network handlers |
| `usr/lib/opkg/info/*.control` | — | Proved the base system is stock OpenWrt |
| `lib/upgrade/platform.sh` | 3 022 B | The sysupgrade hook that later accepted OpenWrt |
| `etc/shadow`, `etc/passwd` | 153 / 238 B | Account hashes (see [doc 01](01-hardware-and-attack-surface.md)) |
| `lib/wifi/rt2860v2.sh` | 22 652 B | Vendor Wi‑Fi driver glue (Ralink/MediaTek) |

Everything in that table except the two account files is quoted selectively in this write-up rather
than redistributed — the full sources stay on the analyst's disk.

## Why extraction changed everything

Before extraction we were guessing. `lua.cgi` dispatches on a numeric `cmd` field, and we had no way
to know what any of them did. The recon in [doc 03](03-reconnaissance.md) was therefore a blind
sweep — probing every command ID and watching what came back.

After extraction, guessing became reading:

```lua
-- lua.cgi, the dispatcher
local switch = {
     [29] = acl_filter,
     [80] = iniPage,
     [99] = logout,
    [100] = login,
    [145] = network_tool,      ← we knew exactly where this went
    ...
}
```

`network_tool` in turn calls `system.system_network_tool(tz_req)` in `system.lua` — a function whose
entire job is to shell out to `ping`, `traceroute`, `logread` and `tcpdump` using values from the
request.

That is where [the RCE](04-rce-cmd-145.md) lives.

---

> 📖 Next: [03 — Reconnaissance](03-reconnaissance.md)

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
