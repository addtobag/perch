<p align="center">
  <img src="Resources/icon-1024.png" width="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">A clean, fast macOS app for the cameras on your NVR.<br>Works with Reolink NVRs and cameras, entirely on your home network.</p>

---

## What it does

- **Menu bar panel** – every camera at a glance, plus recent activity (people, vehicles).
- **Live view** – smooth live video, edge to edge, with controls that get out of the way.
- **All cameras** – automatic, grid, one-large, side-by-side or stacked layouts; choose which cameras show and in what order.
- **Alerts** – a card with a snapshot when someone or something is detected, and one click to watch live.
- **Mini player** – a small floating player that stays above your other apps.
- **Today strip** – see when people and vehicles were detected today and jump to the snapshot.
- **Zoom, rotate, pin on top, snapshots**, and keyboard shortcuts for everything.
- **Private by design** – Perch talks straight to your NVR. No cloud, no account, no tracking. Your password is kept in the macOS Keychain.

## Requirements

- macOS 13 Ventura or later (Apple silicon or Intel)
- A Reolink NVR (or a single Reolink camera) on the same network as your Mac
- [Homebrew](https://brew.sh) and ffmpeg for live video (see step 2)

## Install

### 1. Download Perch

Download **Perch.dmg** from the [latest release](../../releases/latest), open it and drag **Perch** into **Applications**.

The first time you open it, macOS may say it can't verify the developer. If so:

1. Open **System Settings → Privacy & Security**.
2. Scroll down and click **Open Anyway** next to the message about Perch.
3. Confirm with **Open**. You only need to do this once.

### 2. Install ffmpeg (for live video)

Perch uses ffmpeg to play your cameras' live streams smoothly. In Terminal:

```bash
brew install ffmpeg
```

Without it Perch still works, but shows frequently refreshed snapshots instead of live video.

### 3. Prepare your NVR (once)

In the Reolink app or the NVR's web page:

- **Network → Advanced → Port settings**: switch on **HTTP** (port 80) and **RTSP** (port 554).
- **User management**: create a **view-only user** for Perch, so your admin password never sits on your Mac.

### 4. Connect

Click the camera icon in the menu bar, then the **gear** icon:

1. Enter your NVR's IP address (e.g. `192.168.1.20`), the username and password.
2. Click **Test connection**, then **Save**.

Perch reads your camera list and names from the NVR automatically. If macOS asks to allow access to devices on your local network, click **Allow**.

## Using Perch

| Key | Action |
| --- | --- |
| `1`–`9` | Switch camera |
| `G` | All cameras |
| `M` | Mini player |
| `F` | Fit whole picture / crop to fill |
| `R` | Rotate the current camera 90° |
| `S` | Save a snapshot (to Pictures › Perch) |
| `P` | Keep the window on top |
| `0` | Reset zoom |
| `Esc` | Back to live / close |

Scroll or pinch to zoom, drag to move around, double-click to reset.

## Away from home

Perch connects directly to your NVR, so it works on your home network. To use it elsewhere, connect your Mac to home with a private VPN such as [Tailscale](https://tailscale.com) or WireGuard. Don't expose your NVR's ports to the internet.

## Troubleshooting

- **Stuck on "CONNECTING"** – check RTSP is switched on in the NVR's port settings. ffmpeg's messages are logged to `~/Library/Logs/Perch/ffmpeg.log`.
- **"NVR refused the login"** – check the username and password, and that the user is allowed to view live video.
- **No detections** – person and vehicle alerts need cameras with Reolink's smart detection. For other cameras, turn on **Any motion** in Settings › Alerts.
- **Date/time overlay won't change** – that setting changes the cameras themselves, so it needs a login that's allowed to change settings.

## Build from source

You'll need Apple's Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/addtobag/perch.git
cd perch
bash build.sh          # builds build/Perch.app
bash make-dmg.sh       # builds build/Perch.dmg (Apple silicon + Intel)
```

`make-dmg.sh` can also sign and notarise the app with an Apple Developer ID – see the comments at the top of the script.

## Privacy

Perch only ever connects to the NVR address you enter. Settings are stored on your Mac, the password in the Keychain, and detection snapshots in `~/Library/Application Support/Perch` (kept for 7 days).

## Disclaimer

Perch is an independent project and is not affiliated with, endorsed by or sponsored by Reolink. Reolink is a trademark of its respective owner.
