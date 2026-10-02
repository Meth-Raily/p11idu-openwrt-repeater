# 06 — Installing OpenWrt

> 👤 **Author:** Nipun Methmal · Part 6 of 9 · [← Index](../README.md) · [Next →](07-building-the-repeater.md)

> ⚠️ **Read this first: the P11IDU is not supported by OpenWrt upstream.**
> Verified 2 October 2026 — see [doc 01](01-hardware-and-attack-surface.md) for the evidence:
> zero matches for `p11idu` in the `openwrt/openwrt` tree, and none of the 134 `ramips/mt76x8`
> snapshot profiles are for this board. **There is nothing to download for this device from
> `downloads.openwrt.org`.**

The image running on the device in this write-up was therefore **built from OpenWrt source by the
author**, with a device tree written for this board — which is why it reports
`board_name: "tozed,p11idu"` and a locally-produced revision:

```
DISTRIB_RELEASE='24.10-SNAPSHOT'
DISTRIB_REVISION='r0-97f7026'      ← 'r0' = not an official snapshot build
```

## 1. Get the right image

You need a **sysupgrade** image for `ramips/mt76x8` that contains the `tozed,p11idu` device tree.
Two ways to get one:

**A. Build it (what we did)** — an OpenWrt source tree with three additions:

| File | Purpose |
|---|---|
| `target/linux/ramips/dts/mt7628_tozed_p11idu.dts` | Device tree: partitions, GPIOs, keys, LEDs, ethernet/switch |
| `target/linux/ramips/image/mt76x8.mk` | `Image/Device/tozed,p11idu` — image recipe, profile, `DEVICE_TITLE` |
| `target/linux/ramips/mt76x8/base-files/etc/board.d/01_leds`, `02_network` | LED names and per-board port/VLAN defaults |

```sh
make defconfig
make menuconfig        # Target: MediaTek Ralink MIPS → mt76x8; select Device → Tozed P11IDU
make -j$(nproc) DL_DIR=... IB=...   # then:
#   bin/targets/ramips/mt76x8/openwrt-...-ramips-mt76x8-tozed-p11idu-squashfs-sysupgrade.bin
```

> 💡 **The device tree from that build already exists — recovered.** It was pulled off the
> running device and committed to [`hardware/`](../hardware/README.md), so nothing hinges on
> finding an old build directory.
>
> The two things a lost build tree *would* have held — the **image recipe** and the
> **`board.d` files** — are now written too, as a draft series in
> [`upstream/`](../upstream/README.md). The image recipe and the `02_network` arms were read
> straight back off the running unit; the `01_leds` arm is a proposal. None of it is
> compile-verified yet. See [Can this go upstream?](#can-this-go-upstream).

**B. Source a known-good image** built for this board by someone who has one. Do **not** substitute
a generic `mt76x8` image or another device's image: the wrong DTS means wrong flash partitions,
which means a brick.

### What you are aiming for

| | |
|---|---|
| Target | `ramips/mt76x8` |
| Subtarget | `mt76x8` |
| Device | `tozed,p11idu` |
| Image type | `*-sysupgrade.bin` |
| Architecture | `mipsel_24kc` |

Running system at the end of this project:

```
OpenWrt 24.10-SNAPSHOT r0-97f7026
kernel 6.6.157 · ramips/mt76x8 · mipsel_24kc · squashfs rootfs
```

### Sanity-check before you trust a file

The wrong image on this board will not fail loudly — it will write the wrong partitions. Verify
before flashing:

```sh
# 1. the device tree must name your board
dumpimage -T dtbs -p 0 openwrt-*-sysupgrade.bin | strings | grep compatible
#   expect: tozed,p11idu

# 2. compare against whatever checksum the builder published
sha256sum openwrt-*-sysupgrade.bin
```

If step 1 doesn't say `tozed,p11idu`, **stop**.

## 2. Transfer it over the shell you already have

From the root shell in [doc 05](05-root-shell.md), the image just needs to land on the device's
filesystem. Either of these works — pick whichever your environment allows:

```sh
# A) wget from a temporary HTTP server on your PC
python3 -m http.server 8000          # on your PC, in the directory holding the image
cd /tmp && wget http://<your-pc-ip>:8000/openwrt-*-sysupgrade.bin

# B) scp directly (if the stock shell has scp, or dropbear is reachable)
scp openwrt-*-sysupgrade.bin root@192.168.8.1:/tmp/
```

Two constraints on this box:

- **64 MB of RAM** — the image must fit in `/tmp` (tmpfs), which it does comfortably.
- **16 MB of flash** — nothing else will.

Check both before proceeding:

```sh
df -h /tmp          # plenty of room?
free                # don't start sysupgrade at 90% RAM used
```

## 3. Flash it — plain `sysupgrade`

**Kept the existing configuration** (no `-n`):

```sh
sysupgrade -v /tmp/openwrt-*-sysupgrade.bin
```

What happens, in order:

1. `platform.sh` (stock OpenWrt's, present in the image we extracted) validates the image.
2. The kernel is written to its flash slot; the rootfs becomes `squashfs`.
3. `/etc/config/*` is **preserved** across the transition.
4. The device reboots.

### Why keeping config mattered (and came back to bite us)

Because the stock firmware *was* OpenWrt underneath, preserving `/etc/config` carried the vendor's
network configuration straight into the new install. That is why, immediately after flashing, the
device still had:

```uci
config interface 'wan'              # ← from stock, meant for the outdoor unit
        option device 'eth0.2'
        option proto 'static'
        option ipaddr '172.19.2.2'
        option gateway '172.19.2.254'
```

…plus the two-VLAN switch layout, and a DHCP range starting at `.100`.

Nothing was attached to that `wan`, so its default route pointed at a **dead gateway**. For a while
it sat at metric 10 as a fallback, and the resolver list carried a nameserver that never answered.
The fix — disabling `wan`/`wan6` entirely — is in [doc 08](08-verification.md).

> 💡 **If you are doing this yourself:** `sysupgrade -n` gives you a clean, known-good OpenWrt
> configuration and avoids inheriting the vendor's network plan. Keeping config is only worth it if
> you deliberately want the stock LAN addressing. **We kept it**, and that was the right call for
> this build (LAN stayed `192.168.8.0/24`, so nothing on the wired side had to be re-addressed).

## 4. First boot — verify before you touch anything

Give it a good 60–90 seconds, then:

```sh
# from your PC
ping 192.168.8.1 -n 4
```

On the device:

```sh
cat /etc/openwrt_release
ubus call system board
```

Expected:

```json
{
    "kernel": "6.6.157",
    "hostname": "P11IDU",
    "system": "MediaTek MT7628AN ver:1 eco:2",
    "model": "Tozed P11IDU",
    "board_name": "tozed,p11idu",
    "rootfs_type": "squashfs",
    "release": {
        "distribution": "OpenWrt",
        "version": "24.10-SNAPSHOT",
        "revision": "r0-97f7026",
        "target": "ramips/mt76x8",
        "description": "OpenWrt 24.10-SNAPSHOT r0-97f7026"
    }
}
```

Then confirm the three ways in:

| Access | Endpoint | Notes |
|---|---|---|
| Telnet | `192.168.8.1:23` | `root` + your password |
| SSH | `192.168.8.1:22` | dropbear |
| HTTP | `192.168.8.1:80` | LuCI at `/cgi-bin/luci/` |

**Immediately set a root password** if you have not already:

```sh
passwd
```

…and **disable the WAN-side services** you don't want reachable later. Stock carried nothing across
that listens on the LAN only by default, but it costs nothing to check:

```sh
nft list ruleset | head
netstat -tulpn 2>/dev/null || ss -tulpn
```

## 5. Back up before you build

Take copies of the three files you are about to edit:

```sh
cp /etc/config/wireless  /root/wireless.bak
cp /etc/config/network   /root/network.bak
cp /etc/config/firewall  /root/firewall.bak
```

Rollback is then a single line:

```sh
cp /root/network.bak /etc/config/network && service network reload
```

---

## Can this go upstream?

**Yes — and right now it genuinely isn't there.** That is not a figure of speech: `p11idu` returns
zero results in `openwrt/openwrt`, and none of the 134 `ramips/mt76x8` profiles published in the
current snapshot are for this board. Getting it into OpenWrt's device list means adding real code,
not just a wiki page.

### What a submission needs

| # | Artefact | State |
|---|---|---|
| 1 | `target/linux/ramips/dts/mt7628an_tozed_p11idu.dts` | ✅ **Written** — recovered off the running device, then re-expressed with `&gpio`-style labels against upstream `mt7628an.dtsi`. Draft in [`upstream/`](../upstream/README.md) |
| 2 | `target/linux/ramips/image/mt76x8.mk` → `Device/tozed_p11idu` | ✅ **Draft** — `IMAGE_SIZE := 16064k`, taken straight from the `firmware` partition's `reg = <0x50000 0xfb0000>` |
| 3 | `base-files/etc/board.d/01_leds` | 🟡 **Draft, and a proposal** — no `tozed` arm exists on the running unit, so the triggers are reasoned from the sysfs LED names rather than observed |
| 4 | `base-files/etc/board.d/02_network` | ✅ **Draft, verbatim** — the two `tozed,p11idu` arms read straight off the running unit's own `board.d` |
| 5 | Built image, flashed, **verified on hardware** | You have this: reboot persistence, NAT, channel-following all tested (doc 08) |
| 6 | `openwrt-devel` patch + `Tested-by:` | Not done — gated on disclosure to Tozed/Dialog |

The four code artefacts live in [`upstream/`](../upstream/README.md), laid
out along OpenWrt's own paths, with each file's destination, indentation
style and insertion point spelled out. **None of them have been compiled** —
there is no Linux toolchain here, so `make` has never run against them.

### What you already have that most contributors don't

- The board **works**, and is documented end-to-end — the strongest kind of `Tested-by:`
- Flash layout derived from a **16 MB raw dump** of stock firmware (doc 02), now confirmed
  against `/proc/mtd` on the running device
- **The device tree is recovered**, not theoretical: pulled from `/sys/firmware/fdt`, decompiled,
  and committed to [`hardware/`](../hardware/README.md) with its SHA-256
- Real-world verification: reboot persistence, upstream channel changes, throughput numbers
- LED and switch behaviour confirmed in LuCI, not guessed from a datasheet — and the GPIO
  assignments are now known exactly rather than inferred

### The process

1. **The DTS is already written.** It lives in [`upstream/`](../upstream/README.md) — there is no
   build tree left to lose. Raw phandles are now `&gpio`-style labels, and every `status` override
   has been cross-checked against upstream `mt7628an.dtsi` to work out which nodes genuinely need
   one. What remains is a *compile* pass: get it past `dtc` without warnings.
2. Rebase onto current `master` and produce three clean commits (DTS, image recipe, board.d).
   The `mt76x8.mk` and `board.d` drafts are also written — the image recipe and the
   `02_network` arms came from the running unit, so they are evidence rather than invention.
   `01_leds` is the one genuinely open question: nobody has watched those lamps under a
   normal config, because the device never shipped an LED config at all.
3. Post to **`openwrt-devel`** with the patch series and a `Tested-by:` line describing the exact
   hardware revision — but only after the disclosure in [doc 04](04-rce-cmd-145.md) has gone out.
4. Expect review questions: partition layout justification, why `HT40` vs `HT20`, GPIO polarity,
   and whether the LEDs are wired as the DTS claims.
5. Once merged: **official images** appear on `downloads.openwrt.org`, and
   [the wiki page](https://openwrt.org/toh/start) follows.

### Why bother

Right now every P11IDU owner has to obtain an unofficial build from somewhere — which is exactly
how people end up flashing the wrong DTS onto the wrong board. Upstreaming turns this write-up from
"here's how one person did it" into "here's the supported path."

It would also make the claim at the top of this repository rather more than *as far as I can find*.

---

> 📖 Next: **[07 — Building the repeater](07-building-the-repeater.md)** — the main event.

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
