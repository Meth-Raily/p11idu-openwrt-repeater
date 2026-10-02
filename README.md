# P11IDU OpenWrt NAT Repeater

> 👤 **Author:** Nipun Methmal · 📅 October 2026 · 🪪 MIT License
> **Tozed P11IDU → stock firmware root → OpenWrt → single-radio Wi‑Fi repeater**

**By Nipun Methmal** — as far as I can find, the first published, fully documented conversion of the
Tozed P11IDU into a wireless repeater, including the firmware dump, the stock-firmware code review,
the remote-code-execution path that produced a root shell, the OpenWrt flash, and the complete
verified configuration.

---

## What this repository is

A complete, reproducible write-up of a real project, not a summary. Every claim below is backed by a
document in [`docs/`](docs/) and, where applicable, by the actual source file that was extracted from
the stock firmware image.

| # | Document | What it covers |
|---|----------|----------------|
| 01 | [Hardware & attack surface](docs/01-hardware-and-attack-surface.md) | MT7628AN SoC, the 7-port switch, every listening service |
| 02 | [Firmware dump & extraction](docs/02-firmware-dump-and-extraction.md) | Pulling the 16 MB image and unpacking all 2 627 entries |
| 03 | [Reconnaissance](docs/03-reconnaissance.md) | The JSON API, what we tried, and what did **not** work |
| 04 | **[The `cmd=145` RCE](docs/04-rce-cmd-145.md)** | The authenticated command injection, straight from vendor source |
| 05 | [Getting a root shell](docs/05-root-shell.md) | Login → inject → read output back → persistent telnet |
| 06 | [Installing OpenWrt](docs/06-installing-openwrt.md) | **No official image exists** — building one, plus the sysupgrade flash and first boot |
| 07 | [Building the repeater](docs/07-building-the-repeater.md) | STA+AP on one radio, `wwan`, firewall, NAT |
| 08 | [Verification](docs/08-verification.md) | Routing, conntrack, reboot persistence, throughput |
| 09 | [Is it an L3 switch?](docs/09-is-it-an-l3-switch.md) | What it is, what it isn't, how to make it one |

---

## The end result

```
        ┌─────────────────────────────┐
        │  Home 4G router (upstream)  │  SSID: <UPSTREAM_SSID>
        │  192.168.1.1                │  WPA2, channel varies
        └──────────────┬──────────────┘
                       │ Wi‑Fi STA   (phy0-sta0, single radio)
        ┌──────────────▼──────────────┐
        │      Tozed P11IDU           │
        │  OpenWrt 24.10-SNAPSHOT     │
        │                             │
        │  wwan  192.168.1.102  ── DHCP client
        │        └─ NAT / masquerade  │  ← the single L3 boundary
        │  lan   192.168.8.1    ── br-lan
        │        ├ eth0.1   (VLAN 1: ports 0,1,3)
        │        └ phy0-ap0 (SSID "<AP_SSID>")   ← Wi‑Fi AP
        └──────────────┬──────────────┘
                       │ 802.11, same channel as the uplink
              ┌────────┴────────┐
              │  phones  /  PC  │   192.168.8.100+
              └─────────────────┘
```

A **single-radio NAT repeater**: the one 2.4 GHz radio is simultaneously a client of the home router
and an access point for your own devices, on the same channel. Traffic is masqueraded at `wwan`.

---

## Snapshot of the running system

```
Hostname      P11IDU
Model         Tozed P11IDU
Architecture  MediaTek MT7628AN ver:1 eco:2
Target        ramips/mt76x8  (mipsel_24kc)
Firmware      OpenWrt 24.10-SNAPSHOT r0-97f7026
Kernel        6.6.157
LuCI          openwrt-24.10 branch 26.271.22159-7dbe263
RAM           57.40 MiB available
Overlay       10.50 MiB
```

The exported configuration lives in [`configs/`](configs/) — ready to apply to a fresh device.

---

## Quick start (repeaters in a hurry)

If you already have an OpenWrt P11IDU, skip to
[doc 07](docs/07-building-the-repeater.md). The short version:

```sh
# 1. A second wireless interface on the same radio, as a client
uci set wireless.sta0=wifi-iface
uci set wireless.sta0.device='radio0'
uci set wireless.sta0.mode='sta'
uci set wireless.sta0.network='wwan'
uci set wireless.sta0.ssid='<UPSTREAM_SSID>'
uci set wireless.sta0.encryption='psk2'
uci set wireless.sta0.key='<UPSTREAM_PSK>'

# 2. Uplink interface
uci set network.wwan=interface
uci set network.wwan.device='phy0-sta0'
uci set network.wwan.proto='dhcp'

# 3. Put it in the wan zone so it gets masqueraded
uci add_list firewall.@zone[1].network='wwan'

# 4. Commit and apply (reload last — it can drop an open telnet session)
uci commit && service network reload
```

Verify with the script in [`scripts/verify-repeater.ps1`](scripts/verify-repeater.ps1), or see
[doc 08](docs/08-verification.md).

---

## Repository layout

```
docs/      The nine-part write-up (start at 01)
hardware/  The recovered device tree — .dts plus the raw .dtb, with provenance
upstream/  Draft OpenWrt patch series: DTS, image recipe, board.d arms
configs/   Sanitized UCI exports from the live device
scripts/   PowerShell + shell helpers actually used during the project
media/     Screenshots of the finished system
```

### A draft patch series, not a claim of support

[`upstream/`](upstream/README.md) contains a four-file draft series that would add this
board to OpenWrt's `ramips/mt76x8` target: the device tree with symbolic labels, the
`mt76x8.mk` image recipe, and the two `board.d` additions. The device tree and the
`02_network` arms were taken back off the running unit; the `01_leds` arm is a proposal.

**None of it has been compiled** — there is no Linux toolchain in this environment, so
`make` has never been run against these files. Treat it as a well-evidenced draft that
still owes you a `dtc` run, a real build, and a `Tested-by:` from hardware. It is also
gated on the disclosure in [doc 04](docs/04-rce-cmd-145.md): sending this upstream, or
putting it on the OpenWrt wiki, comes after Tozed and Dialog have been told.

**Deliberately excluded:** the dumped stock firmware image, the extracted rootfs archive, and any
screenshot showing your ISP's equipment identifiers (IMSI/IMEI/WAN MAC). See
[`.gitignore`](.gitignore).

---

## Responsible use

Everything here was done on **hardware I own**, for the purpose of repurposing it.

The vulnerability in [doc 04](docs/04-rce-cmd-145.md) is a real defect in stock Tozed firmware that
other people's devices may still be running. If you find it in the wild, please report it to the
vendor or your ISP rather than using it. The contents of this repository are provided for
education and for people working on their own equipment — see [`LICENSE`](LICENSE).

---

> ✍️ **Written, tested and documented by Nipun Methmal.**
> If this saved you an evening, star the repo or tell me about it.
>
> © 2026 Nipun Methmal — released under the MIT License.
