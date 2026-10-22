# Setting up your NVR for Perch

Perch talks directly to your Reolink NVR (or a single Reolink camera) over your home network. It needs a few settings switched on first. You only do this once.

Menu names vary slightly between NVR models, firmware versions and the Reolink apps. If you can't see an option exactly where described, look in the nearby menus for the same name.

You can change these settings in any of:

- **Reolink app** (iPhone/Android): tap your NVR, then the **⚙ gear** icon.
- **Reolink Client** (Mac/Windows desktop app): select the NVR, then **Device Settings**.
- **Web browser**: go to `http://<your NVR's IP address>` and log in as admin, then **Settings**.

---

## 1. Find your NVR's IP address

- **Reolink app:** ⚙ → **Network Information** (or **Device Info**). Note the **IP address**, e.g. `192.168.1.20`.
- Or check your router's list of connected devices for one named "Reolink" or "NVR".

**Recommended:** in your router, give the NVR a *reserved* (fixed) address, often called "DHCP reservation" or "static lease". Otherwise the address can change after a power cut and Perch won't find the NVR.

## 2. Switch on HTTP and RTSP

Perch uses **HTTP** for snapshots and detections, and **RTSP** for smooth live video.

- **Reolink app:** ⚙ → **Network Information** → **Advanced** → **Server Settings** (called **Port Settings** on some versions).
- **Web / Client:** **Settings → Network → Advanced → Server Settings / Port Settings**.

Turn on:

| Service | Default port | Needed for |
| --- | --- | --- |
| **HTTP** | 80 | Snapshots, detections, camera list |
| **RTSP** | 554 | Live video |

Save. HTTPS (443) and ONVIF are optional; Perch doesn't need them.

**Check it worked:** open `http://<NVR IP>` in Safari. You should see the Reolink login page.

## 3. Create a view-only user for Perch

Perch needs a username and password. It's safest not to use your admin account.

- **Reolink app:** ⚙ → **User Management** (or **Users**) → **Add User**.
- **Web / Client:** **Settings → System → User Management → Add User**.

Give it a name like `perch`, a strong password, and the **User** (sometimes called **Guest**) permission level, **not Administrator**. That lets Perch view live video and snapshots, but not change your NVR's settings.

> The one Perch feature that needs more permission is **Settings → Camera overlays** (turning the burned-in date/time on or off). With a view-only user, change that in the Reolink app under **Display → OSD** instead.

## 4. Make sure smart detection is on (for alerts)

Perch's person and vehicle alerts come from your cameras' own **smart detection**.

- **Reolink app:** tap a camera → ⚙ → **Detection Alarm** / **Smart Detection** → make sure **Person** and **Vehicle** are on.

Cameras without smart detection still work. Turn on **Any motion** in Perch's **Settings → Alerts** to be told about general movement instead.

## 5. Optional: faster camera switching

When you click a camera, Perch shows a lighter stream instantly and switches to full quality once the camera sends its next "key frame". By default some cameras only send one every few seconds.

- **Reolink app:** tap a camera → ⚙ → **Display** → **Encode** (or **Stream**) → **Frame Interval / I-frame Interval** → **1x**.

This makes full quality appear sooner. Recordings get slightly larger.

## 6. Connect Perch

1. Click Perch's icon in the menu bar → **⚙ gear**.
2. Enter the **NVR address** from step 1, and the **username** and **password** from step 3.
3. Click **Test connection**, then **Save**.
4. If macOS asks to let Perch find devices on your local network, click **Allow**.

Perch then reads your list of cameras and their names from the NVR automatically. You can re-run this any time from **Settings → Cameras → Detect cameras**.

---

## Troubleshooting

| Problem | Check |
| --- | --- |
| "Can't reach the NVR" | Is your Mac on the same network as the NVR? Is the IP address right? Does `http://<NVR IP>` open in Safari? |
| "NVR refused the login" | Username and password, and that the user is allowed to view live video. |
| Stuck on "CONNECTING" | RTSP is switched on (step 2) and ffmpeg is installed. Details are logged in `~/Library/Logs/Perch/ffmpeg.log`. |
| No person/vehicle alerts | Smart detection is on for that camera (step 4), and alerts are on in Perch's settings. |
| Works at home, not elsewhere | Expected: Perch connects directly to your NVR. Use a private VPN such as Tailscale to reach home. Don't open your NVR's ports to the internet. |
