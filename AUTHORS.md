# Authors

> **Nipun Methmal** — creator, researcher and author of this project.

## Nipun Methmal

Everything in this repository — the firmware analysis, the vulnerability research, the OpenWrt
conversion, the repeater design, the verification methodology, and this write-up — was done by
**Nipun Methmal**.

- 🔧 Hardware: Tozed P11IDU (owned by the author)
- 📡 Network: single-radio NAT repeater, `192.168.8.0/24` ↔ upstream `192.168.1.0/24`
- 🐧 Firmware: OpenWrt 24.10-SNAPSHOT **built by the author** for `ramips/mt76x8` → `tozed,p11idu`
  (not an official download — the board is unsupported upstream)
- 🔍 Research: authenticated RCE in the stock Tozed web UI (`/cgi-bin/lua.cgi`, `cmd=145`)

## Attribution

If you reuse this write-up, its configuration, or its scripts, please credit:

```
Nipun Methmal — p11idu-openwrt-repeater
```

All files in this repository carry the author's name as a watermark, either in the file header
(scripts, configs) or as a byline and footer (documentation).

## Licensing

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Nipun Methmal.

Vendor firmware images and the stock Tozed Lua sources quoted for analysis purposes remain the
property of their respective owners and are **not** included in this repository.

---

> ✍️ © 2026 **Nipun Methmal**
