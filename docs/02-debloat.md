# 02 — Debloat (optional, aggressive)

Goal: free RAM by removing apps nobody uses on a headless server. On the author's J4 this brought used RAM down to about
**910 MB of 1.84 GB** with every service of this project running (system_server alone is ~200 MB, SystemUI ~75 MB, the phone stack ~50 MB).

> ⚠️ **The default list is opinionated and aimed at a phone that will never be a phone again.** It removes, among ~180 packages:
> Chrome and every Google app, **Google Play Services and the Play Store**, the Samsung launcher, dialer, contacts, messaging,
> gallery, camera app, the Samsung keyboard, Bluetooth, backup and sync helpers, Bixby, Knox analytics and many carrier/partner apps.
> After it, the phone **has no browser, cannot make calls or send SMS, and has no store**. Read the list. Delete lines you want to keep.

## What "remove" means here

`pm uninstall --user 0 <package>` hides a **system** app for the primary user. The APK stays in `/system`, so it is
**reversible** (`cmd package install-existing --user 0 <package>`), and a factory reset brings everything back. Nothing
is deleted from the system partition, so the bootloader and warranty state are untouched. You do not need root.

## Use it

```sh
debloat/debloat.sh --dry-run        # prints what it would do, changes nothing
$EDITOR debloat/packages-to-remove.txt
debloat/debloat.sh                  # runs it, writes debloat/debloat.log (git-ignored)
```

Each line prints the result of `pm uninstall`: `Success`, or a `Failure …` message when the package is already gone or does not exist on your model (harmless).
**Wait ~30 seconds after it finishes before rebooting**: rebooting right away lost the change on the author's phone.

To undo: `debloat/restore.sh` (same list), or just the packages you pick.

## Package families in the list

| Family | Examples | Why it goes |
|---|---|---|
| Google apps | `com.android.chrome`, `…youtube`, `…maps`, `…gm` | RAM, and the phone has no browser need |
| Play Services / Store | `com.google.android.gms`, `com.android.vending`, `…gsf` | the biggest RAM consumers; also removes Play Protect |
| Samsung services | Bixby, Knox analytics, `scloud`, game launcher/optimizer, themes store, `mobileservice` | background services you do not use |
| Telephony apps | `…dialer`, `…messaging`, `…contacts`, `com.samsung.rcs`, `com.sec.ims*` | not needed; **do not remove if you want calls/SMS** |
| Launcher and keyboard | `com.sec.android.app.launcher`, `com.sec.android.inputmethod` | replaced by a light launcher/keyboard (author uses Olauncher and Simple Keyboard, both from F-Droid) — **install the replacements first** |
| Carrier / partner | `br.org.sidi.appsbrasil`, `com.hiya.star`, `com.facebook.*`, `com.microsoft.office.*` | preinstalled bloat (some are Brazil-specific) |
| Hardware test apps | `…wlantest`, `…bluetoothtest`, `…hwmoduletest` | factory tools |

## Known quirks

- **Some packages come back**: Samsung re-enables `com.samsung.android.game.gos` at every boot (uninstall *and* disable both
  revert). It is harmless: it does not run.
- `com.samsung.android.kgclient` (Knox guard client) was additionally disabled with `pm disable-user --user 0` on the author's phone.
- Removing the **launcher or keyboard before installing a replacement** leaves you with a phone you cannot type on, except through
  `adb shell input text`. Install the replacements, set them as default, *then* debloat.
- Screen size/density can be overridden to make a small screen usable: `adb shell wm size 360x640; adb shell wm density 140`
  (undo: `wm size reset; wm density reset`).

## Making your own list

```sh
adb shell pm list packages -s --user 0 | sed 's/package://' | sort > installed.txt   # system apps visible to user 0
```

Remove in small batches, reboot, and keep what breaks. Do **not** share your own `installed.txt` publicly — it lists your apps.
