<div align="center">

# 🪟 WFS Windows Remote Workspace

### Windows • RDP • noVNC • Tailscale • Cloudflare HTTPS

**One workflow. Your temporary Windows development desktop.**

[![Workflow](https://img.shields.io/github/actions/workflow/status/wawanwfs/RDP/windows-remote-workspace-with-apps.yml?branch=main&style=for-the-badge&logo=githubactions&label=Windows%20Workspace)](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml)
[![Windows](https://img.shields.io/badge/Windows-2022%20%7C%202025-0078D4?style=for-the-badge&logo=windows)](https://github.com/wawanwfs/RDP/actions)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-HTTPS%20Preview-F38020?style=for-the-badge&logo=cloudflare)](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)
[![Tailscale](https://img.shields.io/badge/Tailscale-Private%20Access-242424?style=for-the-badge)](https://tailscale.com/)

[🚀 Run Workspace](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml) · [📊 Actions](https://github.com/wawanwfs/RDP/actions) · [🔐 Repository Secrets](https://github.com/wawanwfs/RDP/settings/secrets/actions)

</div>

---

## ✨ Apa ini?

**WFS Windows Remote Workspace** menyiapkan desktop Windows sementara lewat GitHub Actions. Pilih aplikasi, lalu masuk menggunakan **RDP**, **noVNC di browser**, atau keduanya. Gunakan **Tailscale** untuk akses privat atau **Cloudflare Quick Tunnel HTTPS** untuk pengujian browser melalui internet dengan autentikasi email OTP.

> [!IMPORTANT]
> Ini **runner sementara**, bukan VPS permanen. **Maksimal 6 jam total per job** sejak proses dimulai (termasuk instalasi). Data runner dapat hilang setelah sesi berakhir.

## 🧭 Arsitektur

```text
                        GitHub Actions Windows runner
                                     │
                             Windows desktop
                           ┌─────────┴──────────┐
                           │                    │
                        RDP :3389         TightVNC :5900
                           │               (localhost)
                        Tailscale               │
                           │             websockify :6081
                           │               (localhost)
                           │              ┌─────┴──────────────┐
                           │              │                    │
                           │       Tailscale Serve      Cloudflare Tunnel
                           │       :6082 TCP OR         HTTPS *.trycloudflare.com
                           │       :443 HTTPS           + email OTP
                           └──────────────┴────────────────────┘
                                      Browser / RDP client
```

| Metode | Alamat | Persyaratan |
|:--|:--|:--|
| 🖥️ RDP | Hostname/IP Tailscale | Tailnet + password Windows |
| 🌐 noVNC TCP | `http://IP-TAILSCALE:6082/vnc.html` | Tailnet, `tailscale_tcp` |
| 🔒 noVNC HTTPS | `https://hostname.tailnet.ts.net/vnc.html` | Tailnet, HTTPS Serve enabled |
| ☁️ Cloudflare HTTPS | `https://nama-acak.trycloudflare.com/vnc.html` | Email OTP + password VNC |

**Port lokal 5900 dan 6081 tidak dibuka ke jaringan.** Pilih satu port Tailscale Serve per run: TCP 6082 atau HTTPS 443. Cloudflare Tunnel menggunakan koneksi keluar, bukan membuka port inbound.

## 🚀 Mulai dari GitHub Actions

1. Buka [Settings → Secrets and variables → Actions](https://github.com/wawanwfs/RDP/settings/secrets/actions) dan isi secret yang dibutuhkan: `TS_AUTHKEY` (Tailscale), `RDP_PASSWORD` (RDP tetap), `VNC_PASSWORD` (noVNC tetap), dan `CLOUDFLARE_ALLOWED_EMAIL` (**satu email** yang diizinkan mengakses preview Cloudflare).
2. Buka [Windows Remote Workspace with Apps](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml), klik **Run workflow** dari branch `main`.
3. Pilih `remote_access=novnc` untuk browser, `rdp` untuk Remote Desktop, atau `both`.
4. Pilih `novnc_transport=tailscale_tcp` untuk port 6082, atau `tailscale_https` jika HTTPS/sertifikat tailnet sudah diaktifkan.
5. Aktifkan `cloudflare_preview=true` bila ingin **link HTTPS yang dapat dibuka tanpa Tailscale**. Pastikan secret `CLOUDFLARE_ALLOWED_EMAIL` sudah terisi.
6. Tunggu step **Verify noVNC HTTP, WebSocket and RFB**, **Cloudflare HTTPS Preview** (opsional), lalu **Remote READY – Keep Alive**. URL aktif ada di **Actions Summary**.

> [!CAUTION]
> Cloudflare Quick Tunnel dapat dijangkau dari internet. Workflow mewajibkan **email OTP** sebelum mengizinkan akses ke desktop. Gunakan `vnc_password_mode=same_from_secret` ketika memakai Cloudflare: password acak yang dicetak di log publik tidak cocok untuk akses internet. Jangan pernah menulis password, token, atau secret di README atau screenshot.

## ☁️ Uji browser melalui Cloudflare HTTPS

1. Set secret `CLOUDFLARE_ALLOWED_EMAIL` menjadi email pribadi Anda.
2. Jalankan workflow dengan `remote_access=novnc` atau `both`, serta `cloudflare_preview=true`.
3. Di **Actions Summary**, buka link `https://....trycloudflare.com/vnc.html`.
4. Masukkan email yang diizinkan, kemudian **PIN sekali pakai** yang dikirim Cloudflare.
5. Setelah halaman noVNC tampil, klik **Connect**, lalu masukkan password dari secret `VNC_PASSWORD`.
6. Jika halaman terbuka tetapi Connect gagal, tekan `F12` → **Network → WS** untuk memeriksa WebSocket. Bandingkan dengan hasil **HTTP / WebSocket / VNC-RFB** di Summary.

**URL Cloudflare berubah setiap run** dan berhenti ketika tunnel/runner berhenti. Quick Tunnel hanya untuk pengujian, bukan produksi. Keberhasilan memperoleh URL tidak otomatis menjamin koneksi desktop berhasil.

## 🧪 Pengujian lokal Windows 10/11

Untuk menguji **halaman web noVNC** di komputer sendiri, tanpa GitHub Actions:

1. Instal **TightVNC Server** dan atur password. Batasi server agar hanya mendengarkan di `127.0.0.1:5900`.
2. Instal **Python 3** dan unduh source [noVNC](https://github.com/novnc/noVNC) ke `C:\WFS\noVNC`.
3. Jalankan PowerShell:

```powershell
py -m pip install --upgrade websockify
py -m websockify --web "C:\WFS\noVNC" 127.0.0.1:6081 127.0.0.1:5900
```

4. Buka **http://127.0.0.1:6081/vnc.html**. Jika halaman muncul tetapi Connect gagal, periksa TightVNC di `127.0.0.1:5900`.

Untuk menguji HTTPS lokal dengan email OTP, unduh [cloudflared Windows](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) dan jalankan di PowerShell **kedua**:

```powershell
.\cloudflared.exe tunnel --url http://127.0.0.1:6081 --allowed-mail "email-anda@example.com"
```

Buka URL `https://….trycloudflare.com/vnc.html` yang muncul, verifikasi email, lalu masukkan password VNC. Tekan `Ctrl+C` untuk menghentikan tunnel. **Jangan menghilangkan `--allowed-mail` untuk desktop.**

## 🔍 Diagnostik koneksi

```powershell
# Ganti IP dengan IP dari Actions run yang masih aktif
tailscale ping 100.x.x.x
Test-NetConnection 100.x.x.x -Port 6082
curl.exe --noproxy "*" --max-time 15 -I "http://100.x.x.x:6082/vnc.html"
```

| Gejala | Solusi |
|:--|:--|
| Ping berhasil tetapi port gagal | Cek Tailscale Serve, status runner, ACL/grants |
| TCP berhasil tetapi halaman tidak tampil | Uji respons HTTP, pastikan browser tidak memaksa HTTPS pada port 6082 |
| Halaman tampil tetapi Connect gagal | Periksa tab Network → WS dan status WebSocket/RFB di Actions Summary |
| Link Cloudflare tidak bisa dibuka | Periksa step Cloudflare, email OTP, dan apakah runner masih aktif |
| URL lama mati | Gunakan URL dari run baru; hostname Quick Tunnel berubah |

## ⏳ Keep Alive — sampai 6 jam atau dibatalkan

Job memakai `timeout-minutes: 360`. Setelah instalasi, **Remote READY – Keep Alive** terus mengirim heartbeat setiap 60 detik dan tidak berhenti berdasarkan durasi tidur buatan. Job berakhir ketika Anda menekan **Cancel workflow** atau ketika GitHub mencapai batas **6 jam total sejak job mulai**. Waktu instalasi **termasuk** dalam enam jam tersebut.

Cleanup Tailscale dijalankan secara *best effort*; saat timeout atau cancel paksa, cleanup tidak selalu sempat selesai. Runner tidak dapat dipertahankan melebihi batas platform.

## 📦 Aplikasi yang dapat dipilih

VS Code, Antigravity, CapCut, Shotcut, MetaTrader 4/5, AI API routers, Codex CLI, Claude Code, Hermes, OpenClaw, OpenCode, ArtCraft Launcher, serta aplikasi dasar. Ketersediaan tergantung image Windows dan installer.

## 🛡️ Keamanan

- Tailscale adalah jalur **privat** yang direkomendasikan.
- Cloudflare Preview memakai **HTTPS + email OTP + password VNC**, tetapi endpoint dapat dijangkau dari internet.
- VNCAuth klasik hanya memakai **delapan byte pertama** password.
- Jangan simpan data penting secara eksklusif pada runner sementara.
- **Success** pada tahap setup tidak membuktikan browser eksternal bisa tersambung; lakukan pengujian nyata.

---

<div align="center">

**WFS Tech • Build, connect, test.**

[▶️ Start Workspace](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml) · [📖 Cloudflare Docs](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) · [🛡️ Tailscale Docs](https://tailscale.com/kb)

</div>
