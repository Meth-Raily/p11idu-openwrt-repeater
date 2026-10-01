# 06 — Installing OpenWrt

> 👤 **Author:** Nipun Methmal · Part 6 of 9 · [← Index](../README.md) · [Next →](07-building-the-repeater.md)

The device is officially supported by OpenWrt — `tozed,p11idu` exists as an upstream profile on the
`ramips/mt76x8` target. That means **no custom image, no device-tree porting, no rebuild**: a stock
image from `downloads.openwrt.org` is the correct answer.

## 1. Get the right image

```
https://downloads.openwrt.org/   →   targets / ramips / mt76x8
```

You want the **sysupgrade** image for `tozed,p11IDU` (not *factory* — there is no vendor bootloader
recovery story here, and we already have a shell).

| | |
|---|---|
| Target | `ramips/mt76x8` |
| Subtarget | `mt76x8` |
| Device | `tozed,p11idu` |
| Image type | `*-sysupgrade.bin` |
| Architecture | `mipsel_24kc` |

What we ended up running:

```
OpenWrt 24.10-SNAPSHOT r0-97f7026
kernel 6.6.157 · ramips/mt76x8 · mipsel_24kc · squashfs rootfs
```

Sanity-check before you trust a file:

```sh
sha256sum openwrt-*.img.gz        # compare against sha256sums on the download page
```

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

> 📖 Next: **[07 — Building the repeater](07-building-the-repeater.md)** — the main event.

---
> ✍️ © 2026 **Nipun Methmal** · MIT License · *p11idu-openwrt-repeater*
