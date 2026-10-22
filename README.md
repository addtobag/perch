<p align="center">
  <img src="Resources/icon-1024.png" width="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">A clean, fast macOS app for the cameras on your NVR.<br>Works with Reolink NVRs and cameras, entirely on your home network.</p>

<p align="center">
  <img src="docs/screenshots/live.png" alt="Perch live view">
</p>

<table>
  <tr>
    <td><img src="docs/screenshots/grid.png" alt="All cameras"></td>
    <td><img src="docs/screenshots/panel.png" alt="Menu bar panel with activity"></td>
  </tr>
  <tr>
    <td align="center">All cameras, with the latest detection on each</td>
    <td align="center">The menu bar panel: cameras at a glance and recent activity</td>
  </tr>
  <tr>
    <td colspan="2"><img src="docs/screenshots/alert.png" alt="Alert card and floating mini player"></td>
  </tr>
  <tr>
    <td colspan="2" align="center">An alert when someone's detected, and the floating mini player</td>
  </tr>
</table>

<sub>Camera pictures are shown as grey placeholders in these screenshots.</sub>

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

## Quick start

About 10 minutes, most of it waiting for downloads.

1. **[Download Perch.dmg](../../releases/latest)** and drag Perch into Applications. → [details](#1-download-perch)
2. **Install ffmpeg** for live video: `brew install ffmpeg`. → [no Homebrew yet?](#2-install-ffmpeg-for-live-video)
3. **Switch on HTTP and RTSP** on your NVR and create a view-only user. → [NVR guide](docs/NVR-SETUP.md)
4. **Open Perch**, enter the NVR's IP address and login, and you're done. → [details](#4-connect)

## Requirements

- macOS 13 Ventura or later (Apple silicon or Intel)
- A Reolink NVR on the same network as your Mac. Wired Reolink cameras and doorbells used on their own should also work.
- [Homebrew](https://brew.sh) and ffmpeg for live video (see step 2)

Not supported: battery-powered Reolink cameras on their own (they sleep to save power and don't offer live streams), and cloud-only setups.

## Install

### 1. Download Perch

Download **Perch.dmg** from the [latest release](../../releases/latest), open it and drag **Perch** into **Applications**.

The first time you open it, macOS will say *"Apple could not verify 'Perch.app' is free of malware"*. That's because Perch isn't signed with a paid Apple developer certificate yet, not because anything is wrong. Click **Done** (not *Move to Bin*), then:

1. Open **System Settings → Privacy & Security**.
2. Scroll down to the **Security** section and click **Open Anyway** next to the message about Perch. (The button appears for about an hour after you first try to open the app. If it's not there, try opening Perch again.)
3. Enter your Mac password and click **Open**. You only need to do this once.

Prefer Terminal? This does the same thing:

```bash
xattr -dr com.apple.quarantine /Applications/Perch.app
```

(Right-click → Open no longer skips this check on recent versions of macOS.)

### 2. Install ffmpeg (for live video)

Perch uses [ffmpeg](https://ffmpeg.org), a free video tool, to play your cameras' live streams smoothly. The easiest way to install it is with [Homebrew](https://brew.sh). Open **Terminal** (Applications › Utilities › Terminal) and follow the steps below.

**Already have Homebrew?** (Type `brew --version`. If it prints a version number, you do.) Just run:

```bash
brew install ffmpeg
```

**Don't have Homebrew yet?**

1. Install it (it may ask for your Mac password, and to install Apple's Command Line Tools: say yes):

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   Press **Return** when asked to continue. When you type your password nothing appears on screen; that's normal. The first install can take 5–15 minutes.

2. When it finishes, it shows **Next steps**. On Apple silicon Macs (M1 and later) that's usually these two commands, which let Terminal find `brew`. Intel Macs can skip this.

   ```bash
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

3. Check it worked with `brew --version`, then install ffmpeg:

   ```bash
   brew install ffmpeg
   ```

Perch finds ffmpeg automatically; there's nothing else to set up. Without ffmpeg Perch still works, but shows frequently refreshed snapshots instead of live video.

### 3. Prepare your NVR (once)

Perch needs a few NVR settings switched on. **Full step-by-step guide: [docs/NVR-SETUP.md](docs/NVR-SETUP.md).** In short:

1. **Find the NVR's IP address**, and ideally reserve it in your router so it doesn't change.
2. **Switch on HTTP (port 80) and RTSP (port 554)** under Network › Advanced › Server Settings / Port Settings.
3. **Create a view-only user** for Perch (permission level *User* or *Guest*, not Administrator).
4. **Check smart detection is on** for your cameras (Person / Vehicle), for alerts.
5. *Optional:* set each camera's **I-frame interval to 1x** for faster switching to full quality.

### 4. Connect

Open Perch. Its icon (a small circle with a line under it) appears in the **menu bar** at the top right of your screen. Click it, then the **gear** icon:

1. Enter your NVR's IP address (e.g. `192.168.1.20`), the username and password. If you changed the NVR's HTTP port, add it after a colon, e.g. `192.168.1.20:8080`.
2. Click **Test connection**, then **Save**.

Perch reads your camera list and names from the NVR automatically.

When macOS asks **"Allow Perch to find devices on local networks?"**, click **Allow**. Perch can't reach your NVR without it.

**Can't see the menu bar icon?** On MacBooks with a notch, icons can get hidden when the menu bar is full. Click **Perch** in Applications or the Dock instead: that opens the camera window, and **Settings** is in the menu bar panel. A menu bar organiser such as [Ice](https://github.com/jordanbaird/Ice) also helps.

**Tip:** turn on **Settings → General → Launch at login** so Perch is always there, ready to alert you.

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

## Updating

Download the new **Perch.dmg** from [Releases](../../releases/latest), quit Perch (menu bar icon → **Quit**), and drag the new version into Applications, choosing **Replace**. Your settings and cameras are kept.

After an update you may need to click **Open Anyway** again (step 1), and macOS may ask whether Perch can use its saved password in your Keychain: click **Always Allow**.

## Uninstalling

1. Quit Perch and drag it from Applications to the Bin.
2. To remove its data too, delete these folders: `~/Library/Application Support/Perch` and `~/Library/Logs/Perch`.
3. Optionally, open **Keychain Access**, search for **Perch** and delete the saved password.

## FAQ

**Does Perch record?** No. Your NVR keeps recording as normal; Perch is for watching live and getting alerts.

**Does it replace the Reolink app?** For watching and alerts on your Mac, yes. Use the Reolink app for playback of recordings and changing NVR settings.

**Does it cost anything or send my data anywhere?** No and no. It's free, open source, and only talks to your NVR.

**Will it work with more than four cameras?** Yes. Perch reads however many channels your NVR has.

## Troubleshooting

- **"Can't reach the NVR"** – check the IP address, that your Mac is on the same network, and that Perch is allowed in **System Settings → Privacy & Security → Local Network**.
- **Stuck on "CONNECTING"** – check RTSP is switched on in the NVR's port settings. ffmpeg's messages are logged to `~/Library/Logs/Perch/ffmpeg.log`.
- **"NVR refused the login"** – check the username and password, and that the user is allowed to view live video.
- **No detections** – person and vehicle alerts need cameras with Reolink's smart detection. For other cameras, turn on **Any motion** in Settings › Alerts.
- **Date/time overlay won't change** – that setting changes the cameras themselves, so it needs a login that's allowed to change settings.

## Feedback and help

Found a bug or have an idea? [Open an issue](../../issues). Please include your Mac model, macOS version and NVR model.

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
