# Hardware — the recovered device tree

> 👤 **Author:** Nipun Methmal · MIT License

The **single most valuable artefact for upstreaming** — and the answer to *"do you still have
your OpenWrt build tree?"*

You don't need it. The build tree that produced this board's image is gone: searching `C:`, `D:`
and `E:` found no `toplevel.mk`, no `repositories.conf`, no `tozed`/`p11idu` `.dts` and no
`openwrt*.bin` anywhere, WSL isn't installed, and the recycle bin was empty.

But a device tree is not stored only in the build tree — **the compiled blob is embedded in the
running kernel and readable at `/sys/firmware/fdt`.** So we pulled it straight off the box.

## Contents

| File | What |
|---|---|
| `p11idu.dtb` | The raw FDT blob — 9 118 bytes, exactly as the kernel loaded it |
| `p11idu.dts` | Decompiled back to source — 497 lines, 78 nodes |

```
sha256  p11idu.dtb
0bdb421b30da673b7bc8a4168860c2f79fa67dccc60e70e7897016b663ae8924
```

## How it was recovered

Three obstacles, all cleared without installing a single piece of software.

**1. No `base64` on the box.** Busybox in this build doesn't ship the applet, so the DTB can't
be base64'd straight out over the shell. Fall back to a hex dump instead:

```sh
telnet 192.168.8.1              # root / your password
ls -l /sys/firmware/fdt         # -r-------- 1 root root 9118 ... /sys/firmware/fdt
hexdump -C /sys/firmware/fdt    # 571 lines, 16 bytes each
```

**2. Reassemble it.** Parse the hex column, write the bytes back out, then prove it is a real
FDT: magic `d00dfeed` at offset 0, total size `9118` at offset 4, structure block at 56,
strings block at 8220.

**3. No `dtc`, no Python, no Node** — neither on the device nor on the PC (only the Windows
Store `python` alias stub was present). So the decompiler is a short PowerShell walker over the
FDT format: read the header, then follow `FDT_BEGIN_NODE` / `FDT_PROP` / `FDT_END_NODE` tokens
through the structure block, resolving property names out of the strings block. A value prints
as `"strings"` when its bytes are printable-ASCII-and-NUL-terminated, otherwise as `<0x...>`
cells.

> 💡 Gotcha worth recording: `return ,@($a, $p + 1)` does **not** do what it looks like.
> PowerShell's comma binds tighter than `+`, so it parses as `(@($a, $p)) + 1` — an array with
> `1` *appended*. It silently returned `$p` instead of `$p + 1`, the walk lost four bytes, and
> decoding stopped dead after the root node with `unknown token 0x00000000`. The fix is
> `,@($a, ($p + 1))`.

## What it says about the board

### Identity

```
compatible = "tozed,p11idu" "mediatek,mt7628an-soc";
model      = "Tozed P11IDU";
chosen { bootargs = "console=ttyS0,57600"; }
```

### Flash layout — 16 MiB SPI-NOR

| Partition | Offset | Size | Flags | Notes |
|---|---|---|---|---|
| `u-boot` | `0x000000` | 192 KiB | read-only | |
| `u-boot-env` | `0x030000` | 64 KiB | read-only | |
| `factory` | `0x040000` | 64 KiB | read-only | `nvmem-layout`: `eeprom@0` (1 KiB calibration), `macaddr@4`, `macaddr@28` |
| `firmware` | `0x050000` | 15.32 MiB | | `compatible = "denx,uimage"` |

`firmware` subdivides on the running system into `kernel` `0x1ca8f3` + `rootfs` `0xde570d`
(= `0xfb0000` exactly), with `rootfs_data` `0xa80000` on top — byte-for-byte what `/proc/mtd`
reports. Cross-checked and it matches.

### LEDs and the reset key

All on `gpio@600` (`mediatek,mt7621-gpio`), **all active-low**:

| Node | GPIO | Meaning |
|---|---|---|
| `wlan` | 44 (`0x2c`) | Wi-Fi / boot / failsafe / running / upgrade indicator (via `aliases`) |
| `lte_red` | 40 (`0x28`) | `function = "wan"`, `color = red` |
| `lte_green` | 43 (`0x2b`) | `function = "wan"`, `color = green` |
| `voice` | 46 (`0x2e`) | legacy `label = "voice"` — see the to-do below |
| `reset` *(key)* | 38 (`0x26`) | `linux,code = <0x198>` = `KEY_RESTART` |

### Networking

| Node | Compatible | Detail |
|---|---|---|
| `ethernet@10100000` | `ralink,rt5350-eth` | `mediatek,switch = <0x11>`; MAC from `nvmem-cell` `macaddr@28` |
| `esw@10110000` | `ralink,rt3050-esw` | the 7-port switch LuCI shows as `rt305x-esw`, CPU @ 6 |
| `wmac@10300000` | `mediatek,mt7628-wmac` | calibration from `eeprom@0` in `factory` |

Pinmux groups claimed: `gpio i2s uart1 wled_an p0led_an p3led_an wdt`, plus `spi`, `spi cs1`,
`i2c`, `uart0`, `uart1`, `uart2`, `sdxc`, `pwm0`, `pwm1`, `pcm`, `refclk`.

## Before this can be upstreamed

The `.dts` in this folder is **machine-decompiled and is not submission-ready.** Still to do:

1. **Raw phandles → symbolic labels.** `<0x00000014 0x0000002c 0x00000001>` must become
   `<&gpio0 44 GPIO_ACTIVE_LOW>`. Same for every `interrupt-parent`, `pinctrl-0` and
   `nvmem-cells` reference. This is a mechanical but careful edit — one wrong reference and the
   board silently loses its LEDs or its MAC.
2. **`voice` LED still uses legacy `label =`** while the others use `function` + `color`.
   Modern upstream convention wants `function`/`color` throughout, which means deciding what
   `voice` actually indicates.
3. **LED node names** (`wlan`, `lte_red`, `lte_green`) should be reviewed against OpenWrt's
   LED naming so `01_leds` can reference them predictably.
4. **Compile check.** Run `dtc -I dts -O dtb` — not installed here, but it should build with
   zero warnings before anything is mailed.
5. **Confirm the console baud.** The DTS says `console=ttyS0,57600`; upstream `mt7628` boards
   normally use `115200`. Check what the bootloader actually passes rather than assuming.
6. **The image recipe and `board.d` files were *not* recovered** — they are build-system files,
   not device-tree content, so they are not in the DTB and still have to be written from
   scratch. See [doc 06](../docs/06-installing-openwrt.md).

## Security note

This DTB contains **no MAC addresses, no keys and no credentials.** `macaddr@4`, `macaddr@28`
and `eeprom@0` are *offsets into the read-only `factory` partition*, not values — the real MACs
and the radio calibration data never leave the device. That is also why this file is safe to
publish: upstreaming requires publishing the device tree anyway.

---

> © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
