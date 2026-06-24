# Elan `04f3:0c6c` (ELAN:ARM-M4) fingerprint reader fix for Linux

Get the **Elan Match-on-Chip** fingerprint reader with USB id `04f3:0c6c`
(`lsusb` shows it as `Elan Microelectronics Corp. ELAN:ARM-M4`) working under
`fprintd` / `libfprint` on Linux.

Upstream `libfprint` returns **`No driver found for USB device 04F3:0C6C`** and
`fprintd-enroll` fails with `No devices available`. This repo fixes that.

Tested on **Kali Linux rolling (amd64)** with the `elanmoc2` fork at libfprint
1.94.9. Should apply to Debian/Ubuntu/Mint and other Elan match-on-chip ids too.

---

## What the problem actually is

Two separate faults stack on top of each other:

1. **Unsupported USB id.** Mainline `libfprint` has no driver for `04f3:0c6c`.
   The community `elanmoc2` fork
   ([gitlab.freedesktop.org/geodic/libfprint](https://gitlab.freedesktop.org/geodic/libfprint))
   speaks the match-on-chip protocol, but its device table only lists
   `0c00 / 0c4c / 0c5e` — **not** `0c6c`. We add it (see the patch).

2. **Wrong-architecture daemon.** On the affected machine the whole fprint stack
   was installed as **i386** (`fprintd:i386`, `libfprint-2-2:i386`) on an amd64
   system. The i386 daemon loads the i386 stock `libfprint`, so even a perfect
   amd64 build is ignored. The fix swaps the stack back to **amd64**.

Diagnose your own machine:

```bash
lsusb | grep -i elan                       # confirm 04f3:0c6c
dpkg -l | grep -E 'fprintd|libfprint'      # check for stray :i386 packages
G_MESSAGES_DEBUG=all /usr/libexec/fprintd  # look for "No driver found ... 04F3:0C6C"
```

If your stack is already amd64, the script's step 5 is effectively a no-op —
harmless.

---

## Quick install

```bash
git clone https://github.com/<your-user>/elan-0c6c-fingerprint-fix.git
cd elan-0c6c-fingerprint-fix
sudo bash install.sh
```

Then, **as your normal user (not root)**:

```bash
fprintd-enroll          # scan the same finger ~10 times
fprintd-verify          # should print: verify-match
sudo pam-auth-update    # tick "Fingerprint authentication" for login/sudo
```

---

## What `install.sh` does

| Step | Action |
|------|--------|
| 1 | Install build deps (`meson`, `ninja`, `libglib2.0-dev`, `libgusb-dev`, …) |
| 2 | Clone the `geodic/libfprint` elanmoc2 fork |
| 3 | Apply `0001-elanmoc2-add-04f3-0c6c.patch` (adds the USB id) |
| 4 | Build with meson (drivers: `elanmoc2`, `elanmoc`, `virtual_image`) |
| 5 | Switch the `fprintd` stack from i386 → amd64; purge i386 leftovers |
| 6 | Install the patched `libfprint-2.so.2.0.0` into `/usr/lib/x86_64-linux-gnu`, run `ldconfig`, `apt-mark hold libfprint-2-2` |
| 7 | Re-probe and confirm `elanmoc2` claims `04F3:0C6C` |

> `apt-get update` is intentionally **skipped** in step 5 — broken third-party
> repos (e.g. a stale MongoDB repo with SHA1 signatures) can abort it and were
> blocking the install. Re-enable it if your apt sources are clean.

---

## The patch

`libfprint/drivers/elanmoc2/elanmoc2.c`, device table:

```c
  {.vid = ELANMOC2_VEND_ID, .pid = 0x0c5e, .driver_data = ELANMOC2_DEV_0C5E},
+ {.vid = ELANMOC2_VEND_ID, .pid = 0x0c6c, .driver_data = ELANMOC2_ALL_DEV},
  {.vid = 0, .pid = 0, .driver_data = 0}
```

`ELANMOC2_ALL_DEV` (= 0) is the default behavior; `0c5e` carries an extra quirk
flag we don't need. Adding a **different** Elan id? Append a line with your pid
and start with `ELANMOC2_ALL_DEV`.

---

## Maintenance / gotchas

- **apt upgrades can clobber the lib.** The package is `apt-mark hold`-ed, but a
  forced reinstall of `libfprint-2-2` overwrites `libfprint-2.so.2.0.0`. If the
  reader dies after an update, just re-run `sudo bash install.sh`.
- The build only includes the `elanmoc2`/`elanmoc`/`virtual_image` drivers. If
  you have a *second*, different fingerprint reader, add its driver to the
  `-Ddrivers=` list in step 4.
- Enroll quality: this is a swipe/press match-on-chip sensor. `enroll-stage-passed`
  repeated ~10× then completion is normal; `enroll-remove-and-retry` just means
  lift and press again.

---

## Credits

- [geodic/libfprint](https://gitlab.freedesktop.org/geodic/libfprint) — `elanmoc2` driver fork
- Upstream [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint) / `fprintd`

## License

`libfprint` is **LGPL-2.1+**. The patch in this repo is offered under the same
license. The scripts/docs are MIT.
