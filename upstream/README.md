# Upstream patch series — Tozed P11IDU

**Author: Nipun Methmal**

This directory holds a draft patch series that would add the Tozed P11IDU
to OpenWrt's `ramips/mt76x8` target as a first-class supported device.

It is a **draft**. Nothing here has been compiled: there is no Linux
toolchain in this environment, so `make` has never been run against these
files. Everything below is derived from the running device and from the
current `openwrt/openwrt` sources, not from a successful build.

Read [`docs/06-installing-openwrt.md`](../docs/06-installing-openwrt.md)
for the wider "can this go upstream?" picture; this directory is the
concrete output of artefact 3 from that list.

---

## Contents

| File here | Goes into an OpenWrt tree as | Status |
|---|---|---|
| `target/linux/ramips/dts/mt7628an_tozed_p11idu.dts` | same path — **new file, complete** | recovered from hardware, re-expressed against upstream `mt7628an.dtsi` |
| `target/linux/ramips/image/mt76x8.mk.add` | appended to `target/linux/ramips/image/mt76x8.mk` | **new** |
| `target/linux/ramips/mt76x8/base-files/etc/board.d/01_leds.add` | one `case` arm inside the existing `01_leds` | **proposal** — not present on the running unit |
| `target/linux/ramips/mt76x8/base-files/etc/board.d/02_network.add` | two `case` arms inside the existing `02_network` | **verbatim from the running unit** |

The three `.add` files are *insertions*, not whole files. Each one states
its destination, its indentation convention and its exact insertion point.
Keeping them separate means you can review a four-line change instead of
scrolling through 44 KB of `mt76x8.mk`.

---

## Where this came from

The original build tree was lost — no `toplevel.mk`, no `repositories.conf`,
no `mt7628_tozed_p11idu.dts`, no `openwrt*.bin` on any attached drive, WSL
never installed, recycle bin empty.

So the device tree was **taken back off the device itself**:

1. telnet to `192.168.8.1`
2. `hexdump -C /sys/firmware/fdt` — there is no `base64` applet on the
   image, so the DTB came out as hex
3. reassembled into a 9118-byte blob; magic `d00dfeed` confirms a live DTB
   - **sha256 `0bdb421b30da673b7bc8a4168860c2f79fa67dccc60e70e7897016b663ae8924`**
4. decompiled with a hand-written PowerShell FDT walker (no `dtc`, no
   Python on this box) into 497 lines / 78 nodes — that file is
   [`hardware/p11idu.dts`](../hardware/p11idu.dts)
5. re-expressed the device-specific nodes against the **current** upstream
   `mt7628an.dtsi`, replacing raw phandles with labels (`<0x14>` → `&gpio`,
   `<0x11>` → `&esw`, and so on)

`hardware/` holds the raw evidence; this directory holds the tidied result.

### Verified against the running unit

These are not guesses — each was read back from the device over telnet:

| Claim | How it was checked |
|---|---|
| LED sysfs names `green:wan`, `red:wan`, `red:wlan`, `voice` | `ls /sys/class/leds/` |
| `LED_COLOR_ID_RED = 1`, `LED_COLOR_ID_GREEN = 2` | `include/dt-bindings/leds/common.h` in `torvalds/linux` |
| LAN = ports 0, 1, 3 · WAN = ports 2, 4 · CPU = 6 tagged | `02_network` on the unit + `docs/01` |
| `lan_mac` from `factory 0x28`, `wan_mac = base + 1` | `02_network` on the unit |
| Erase size 65536 (→ `BLOCKSIZE := 64k`) | `/sys/class/mtd/mtd0/erasesize` |
| `IMAGE_SIZE = 16064k` | `reg = <0x50000 0xfb0000>` in the DTB; `0xfb0000 / 1024 = 16064` |
| WiFi AP netdev is `phy0-ap0` (there is no `wlan0`) | `ls /sys/class/net/` |
| `01_leds` has no `tozed` arm at all | `grep -rn "tozed" /etc/board.d/` |
| Flash erase/partition layout | `/proc/mtd` + the `partitions` node in the DTB |

### Assumed, and needing a build to confirm

- **Not compile-verified.** The DTS is written against upstream's
  `mt7628an.dtsi`, but the unit's own `.dtsi` is demonstrably *not* current
  upstream — the running tree names the console UART `uart0@c00` where
  upstream calls it `serial@c00` (label `uartlite`). So the recovered DTB is
  a merge of a device DTS *and* an older base `.dtsi`, and only a real build
  can prove the two are now correctly separated.
- **`chosen { bootargs = "console=ttyS0,57600"; }`** — this is what the
  device tree actually carries, but upstream mt7628 boards overwhelmingly
  use `115200`. Serial console has never been exercised on this unit, so
  nobody knows which is right. **Check against the bootloader before
  submitting.**
- **LED triggers in `01_leds`** are a proposal, not an observation. The
  running unit ships no LED config, so nothing in service supports them.

### Deliberate differences from the recovered DTB

The recovered DTB is a merge, so a few nodes cannot be cleanly attributed
between "device DTS" and "their base `.dtsi`". Where that ambiguity exists
the patch reproduces the **observed hardware state** rather than guessing at
attribution:

| Node | Running DTB | Upstream `mt7628an.dtsi` | Patch does |
|---|---|---|---|
| `spi0` | `okay` | `disabled` | sets `okay` — flash would not probe otherwise |
| `wmac` | `okay` | `disabled` | sets `okay` — no WiFi otherwise |
| `sdhci` | `disabled` | *(enabled by default)* | sets `disabled` — no SD slot on the board |
| `watchdog` | `disabled` | *(enabled by default)* | sets `disabled` — matches the running unit |
| `pcie` | `disabled` | `disabled` | no override needed, matches |
| `ehci` / `ohci` | *(no status)* | *(no status)* | no override needed, matches |
| `pcie0` | `okay` | `disabled` | **not reproduced** — inert, because the parent `pcie` is disabled either way |

The `pcie0` line is the one thing here a reviewer might ask about. It is
left out deliberately: enabling a child under a disabled parent has no
effect on the hardware, and including it would only invite the question
"why is this enabled?"

---

## Wiring it up

```sh
# from a clone of https://github.com/openwrt/openwrt
cp -v mt7628an_tozed_p11idu.dts   target/linux/ramips/dts/
cat  mt76x8.mk.add               >> target/linux/ramips/image/mt76x8.mk
# then open 01_leds / 02_network and paste the marked case arms
# at the insertion points each .add file names

./scripts/feeds update -a && ./scripts/feeds install -a
make defconfig
make menuconfig        # Target: MediaTek Ralink MIPS -> MT76x8
                       #      -> Tozed P11IDU
make -j$(nproc) V=s
```

Then confirm the produced DTB matches what the hardware carries:

```sh
dtc -I dtb -O dts build_dir/target-mipsel_24kc_musl/linux-ramips_mt76x8/linux-*/arch/mips/boot/dts/ralink/mt7628an_tozed_p11idu.dtb
sha256sum …   # compare against 0bdb421b30da673b7bc8a4168860c2f79fa67dccc60e70e7897016b663ae8924
```

A byte-identical DTB is the cleanest possible proof that the reconstruction
is right. They will not be byte-identical — dtc normalises phandles and the
base `.dtsi` differs — so compare **semantically**, property by property,
rather than by hash.

---

## Before any of this goes anywhere

This series is part of the same disclosure as
[`docs/04-rce-cmd-145.md`](../docs/04-rce-cmd-145.md). The plan agreed
so far is **disclose to Tozed / Dialog first**, and only then:

1. open the pull request against `openwrt/openwrt`
2. create the `openwrt.org/toh/tozed` wiki page linking to it

The wiki already has no `toh/tozed` page at all — `openwrt.org/toh/tozed`
returns *"This topic does not exist yet"* — so whoever writes it will be
creating the brand page from scratch. GitHub login works as a wiki
account.

See [`AUTHORS.md`](../AUTHORS.md) for authorship.
