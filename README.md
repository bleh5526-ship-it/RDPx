<div align="center">

# 🖥️ WFS Remote Workspaces

### Windows RDP/noVNC + Linux Desktop • Tailscale • GitHub Actions

**Dua workflow terpisah untuk desktop Windows dan Linux sementara, dengan akses privat melalui Tailscale.**

[![Windows Workspace](https://img.shields.io/github/actions/workflow/status/wawanwfs/RDP/windows-remote-workspace-with-apps.yml?branch=main&style=for-the-badge&logo=githubactions&label=Windows%20Workspace)](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml)
[![Linux Workspace](https://img.shields.io/github/actions/workflow/status/wawanwfs/RDP/linux-remote-workspace.yml?branch=main&style=for-the-badge&logo=linux&label=Linux%20Workspace)](https://github.com/wawanwfs/RDP/actions/workflows/linux-remote-workspace.yml)
[![Windows](https://img.shields.io/badge/Windows-2022%20%7C%202025-0078D4?style=for-the-badge&logo=windows)](https://github.com/wawanwfs/RDP/actions)
[![Tailscale](https://img.shields.io/badge/Tailscale-Private%20Tailnet-242424?style=for-the-badge)](https://tailscale.com/)
[![PowerShell](https://img.shields.io/badge/PowerShell-7-5391FE?style=for-the-badge&logo=powershell)](https://learn.microsoft.com/powershell/)

[**▶ Windows Workspace**](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml) · [**▶ Linux Workspace**](https://github.com/wawanwfs/RDP/actions/workflows/linux-remote-workspace.yml) · [Lihat Actions](https://github.com/wawanwfs/RDP/actions) · [Atur Repository Secrets](https://github.com/wawanwfs/RDP/settings/secrets/actions)

</div>

---

## 🐧 Linux Remote Workspace — RDP / noVNC / Both

Workflow Linux berjalan **terpisah** dari Windows, tetap memakai Tailscale, GitHub Actions Keep Alive, dan aplikasi pilihan. Distro adalah container pada host Ubuntu 24.04. Pilihan **Debian, Ubuntu, Fedora, Arch, Alpine** dikombinasikan dengan desktop **Xfce, MATE, KDE, i3** (20 kombinasi GUI browser).

| Perbandingan | 🪟 Windows | 🐧 Linux |
|:--|:--|:--|
| Jenis remote | RDP / noVNC / Both | **RDP / noVNC (Selkies web) / Both** |
| RDP | Windows Remote Desktop | xrdp, port 3389 melalui Tailscale |
| Browser | TightVNC + noVNC | Webtop Selkies, HTTPS 443 atau TLS/TCP 6082 |
| Password RDP | Secret `RDP_PASSWORD` | **Secret yang sama** |
| Password browser | Secret `VNC_PASSWORD` | **Secret yang sama** |
| Password mode | Secret tetap / acak per run | Secret tetap / acak per run, **tidak dicetak di log publik** |
| Nama runner | Hostname + mode tetap/unik | Hostname + mode tetap/unik |
| Nama akun RDP | RDP | Dapat diubah (default `wfsrdp`) |
| Nama login browser | Password VNC | Dapat diubah (default `wfs`) |
| Durasi | 1 / 3 / 6 jam | 1 / 3 / 6 jam; job maksimal 360 menit |
| Aplikasi | IDE, editor, MetaTrader, router, agent, ArtCraft | **Menu kategori sama**; instalasi hanya bila kompatibel |

**Aplikasi Linux:** pilihan VS Code/Antigravity, CapCut/Shotcut, MT4/MT5, 9Router/OmniRoute, Codex/Claude, Hermes/OpenClaw/OpenCode, ArtCraft, serta paket Developer/Office/Media. Installer mengeluarkan status **INSTALLED**, **FAILED**, **MANUAL**, atau **UNSUPPORTED** per aplikasi. CapCut native Linux dan MetaTrader native bukan instalasi Linux resmi yang dapat dianggap berhasil otomatis; lihat Summary.

**Perhatian:** mode noVNC pada Linux adalah **Selkies Webtop**, bukan server VNC klasik. RDP menggunakan sesi Xorg/Xfce terpisah, sehingga **RDP dan browser tidak otomatis menampilkan satu layar yang sama**. Arch Linux xrdp tidak tersedia dari repositori resmi yang dipakai script; gunakan `novnc` di Arch. Fitur xrdp distro lain masih memerlukan pengujian runtime.

[**▶ Jalankan Linux Remote Workspace**](https://github.com/wawanwfs/RDP/actions/workflows/linux-remote-workspace.yml) · [**Panduan lengkap Linux, password per run, dan daftar app**](linux/README.md)

---

## 🪟 Windows Remote Workspace

## ✨ Ringkasan

WFS Windows Remote Workspace menggunakan **GitHub-hosted Windows runner sementara** untuk menyiapkan desktop serta aplikasi pilihan Anda. Sambungkan perangkat ke tailnet yang sama menggunakan **Tailscale**, lalu akses melalui Microsoft Remote Desktop, browser noVNC, atau keduanya.

| Fitur | Detail |
|:--|:--|
| 🖥️ Mode | `rdp`, `novnc`, atau `both` |
| 🔐 Jaringan | Tailscale privat; tanpa tunnel publik |
| 🌐 noVNC | TCP `6082` atau HTTPS `443`; **auto-fit browser** dan auto-connect pada run baru |
| ⏳ Durasi | Pilihan `1`, `3`, atau `6` jam setelah setup, tetap tunduk pada batas job total `360` menit |
| 🔎 Verifikasi | Pemeriksaan HTTP, WebSocket, dan handshake RFB/VNC |
| 🧹 Penutupan | Logout Tailscale saat selesai, dengan penanganan cleanup best-effort |

> [!IMPORTANT]
> **Ini bukan VPS/komputer permanen.** Runner dan isinya dapat hilang ketika Actions selesai, gagal, dibatalkan, atau mencapai batas platform. Simpan pekerjaan penting ke storage/repository terpisah. Status setup `success` belum membuktikan browser dari PC lain dapat terhubung.

## 🧭 Arsitektur dan port

```text
                         GitHub Actions • Windows runner
                                       │
                                Windows desktop
                      ┌────────────────┴────────────────┐
                      │                                 │
                RDP (jika dipilih)               TightVNC Server
                TCP 3389 / tailnet              127.0.0.1:5900
                      │                                 │
                      │                           websockify/noVNC
                      │                           127.0.0.1:6081
                      │                                 │
                      │                      Tailscale Serve (pilih SATU)
                      │                       ├─ TCP 6082 (HTTP)
                      │                       └─ HTTPS 443 (*.ts.net)
                      │                                 │
                      └────────────────┬────────────────┘
                                       │
                             Perangkat di tailnet yang sama
```

| Port | Komponen | Visibilitas |
|:--|:--|:--|
| `3389/TCP` | Windows RDP | Hanya dibuka melalui firewall untuk IP tailnet saat mode `rdp`/`both` |
| `5900/TCP` | TightVNC (RFB) | **Loopback lokal** |
| `6081/TCP` | websockify / noVNC web UI | **Loopback lokal** |
| `6082/TCP` | Tailscale Serve TCP | Pilihan default noVNC, hanya lewat tailnet |
| `443/TCP` | Tailscale Serve HTTPS | Alternatif noVNC, membutuhkan HTTPS/sertifikat tailnet yang sudah tersedia |
| `6080` | HTTP direct lama | **Tidak digunakan lagi** |

**Tidak perlu membuka port 5900/6081 ke internet atau membuat port forwarding router.** Untuk noVNC, workflow hanya mengonfigurasi **salah satu** dari `6082` atau `443` pada satu run. Server websockify dijalankan lewat Windows Scheduled Task agar tetap berjalan setelah langkah instalasi selesai.

## 🔐 Persiapan: Secrets

Buka **[Settings → Secrets and variables → Actions](https://github.com/wawanwfs/RDP/settings/secrets/actions)**, lalu buat repository secrets sesuai mode:

| Secret | Kapan dibutuhkan | Fungsi |
|:--|:--|:--|
| `TAILSCALE_AUTH_KEY` | **Selalu** | Menghubungkan Windows runner ke tailnet |
| `RDP_PASSWORD` | Jika `rdp_password_mode=same_from_secret` (default) | Password akun Windows `RDP` |
| `VNC_PASSWORD` | Jika noVNC digunakan dan `vnc_password_mode=same_from_secret` (default) | Password autentikasi VNC |

> [!WARNING]
> Nama secret Tailscale yang **benar adalah `TAILSCALE_AUTH_KEY`**, bukan `TS_AUTHKEY`. Jangan tempelkan nilai secret ke README, issue, atau log yang dibagikan. Mode `random_each_run` untuk password VNC mencetak password di log Actions; **log repo publik dapat dibaca umum**. Gunakan secret tetap untuk penggunaan yang lebih aman. VNCAuth klasik hanya memakai **8 byte pertama** password.

## 🚀 Menjalankan workflow

1. Instal/login **[Tailscale](https://tailscale.com/download)** pada PC Windows 10/11 Anda, pastikan berada pada tailnet yang sama dengan auth key runner.
2. Buka **[Windows Remote Workspace with Apps](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml)** → **Run workflow** → pilih branch `main`.
3. Pilih `windows_version` (disarankan `windows-2025`), lalu `remote_access`: `rdp`, `novnc`, atau `both`.
4. Pilih `duration_hours`: `1`, `3`, atau `6` (default), serta aplikasi/IDE yang ingin dipasang.
5. Untuk noVNC, pilih `novnc_transport=tailscale_tcp` (default). Mode `tailscale_https` memerlukan HTTPS Certificates dan MagicDNS aktif pada tailnet; jika setup/sertifikat HTTPS gagal, workflow akan mencoba otomatis **fallback ke TCP privat 6082**.
6. Klik **Run workflow**, buka run tersebut, dan lihat **Summary** untuk hostname, IP, URL noVNC aktual, serta petunjuk password. Gunakan **URL dari run yang sedang aktif**, bukan URL sesi sebelumnya.

**Pilihan utama pada formulir Actions**

| Input | Pilihan penting | Default |
|:--|:--|:--|
| `windows_version` | `windows-latest`, `windows-2025`, `windows-2022`, `windows-11-arm`, `windows-2025-vs2026` | `windows-2025` |
| `remote_access` | `rdp` / `novnc` / `both` | `rdp` |
| `duration_hours` | `1` / `3` / `6` | `6` |
| `hostname_mode` | `same_each_run` / `unique_each_run` | `same_each_run` |
| `rdp_password_mode` / `vnc_password_mode` | `same_from_secret` / `random_each_run` | `same_from_secret` |
| `novnc_transport` | `tailscale_tcp` / `tailscale_https` | `tailscale_tcp` |

**Catatan:** mode noVNC tidak didukung pada runner Windows ARM64 dalam workflow ini; pilih runner x64 untuk `novnc` atau `both`. Label `windows-2025-vs2026` mungkin tidak tersedia untuk semua jenis repository.

## 🖥️ Cara masuk ke workspace

<details>
<summary><strong>Opsi A — Microsoft Remote Desktop (RDP)</strong></summary>

Pastikan `remote_access=rdp` atau `both` dan PC Anda tersambung ke Tailscale.

1. Tekan `Win + R` → ketik `mstsc` → Enter.
2. Isi **Computer** dengan hostname Tailscale atau IP `100.x.x.x` yang tercantum pada Actions Summary.
3. Login dengan username `RDP` dan password sesuai `rdp_password_mode`.
4. Port yang digunakan adalah TCP `3389` melalui Tailscale; **bukan** RDP yang dipublikasikan ke internet.

</details>

<details>
<summary><strong>Opsi B — noVNC dari browser (disarankan untuk akses web)</strong></summary>

Pastikan `remote_access=novnc` atau `both`. Buka **alamat aktual yang dicetak pada Summary** dari perangkat yang sudah terhubung ke tailnet:

| Transport | Format URL | Catatan |
|:--|:--|:--|
| `tailscale_tcp` | `http://100.x.x.x:6082/vnc.html#resize=scale&autoconnect=1` | **HTTP** pada port 6082; lalu autentikasi VNC |
| `tailscale_https` | `https://nama-host.tailnet.ts.net/vnc.html#resize=scale&autoconnect=1` | **HTTPS** via Tailscale Serve port 443 jika berhasil diuji; jika gagal gunakan URL HTTP 6082 dari Summary |

Halaman noVNC **mencoba terkoneksi otomatis** ketika dibuka (password VNC tetap diminta jika diperlukan). Jika memilih `tailscale_https` tetapi sertifikat/izin Tailscale Serve belum siap, workflow akan menonaktifkan konfigurasi HTTPS yang gagal, lalu mengaktifkan **TCP 6082**. Summary mencantumkan **Requested transport**, **Active transport**, dan **HTTPS fallback** (bila terjadi), sehingga jangan mengasumsikan HTTPS aktif sebelum melihat URL aktual. **Jangan** mengganti `http://` menjadi `https://` pada port `6082`: layanan HTTP tersebut tetap dilindungi enkripsi antar-node Tailscale, bukan port publik.

noVNC mengakses **sesi console Windows**, yang dapat berbeda dari desktop user pada sesi RDP. Keberhasilan membuka HTML tidak otomatis berarti koneksi WebSocket atau layar VNC sudah berfungsi.

</details>

## 🖼️ Wallpaper dan layar browser otomatis

**Penyebab wallpaper hitam teridentifikasi:** TightVNC memasang `RemoveWallpaper=1` secara default, yang menyembunyikan wallpaper saat VNC tersambung. Workflow sekarang memasang `VALUE_OF_REMOVEWALLPAPER=0` dan memverifikasi registry serta servis setelah instalasi. Tampilan tetap dapat berbeda antara sesi console dan sesi RDP.

Workflow terbaru mencoba menggunakan **wallpaper bawaan Windows** jika wallpaper belum disetel dan tidak lagi memaksakan opsi visual "best performance". Ini *best effort*: wallpaper mungkin tetap gelap jika console yang dilihat berbeda dari profil Windows yang diubah. Jika ingin mengganti secara manual, di desktop remote pilih **klik kanan → Personalize → Background → Picture**.

**Skala tampilan otomatis:** noVNC menggunakan `resize=scale` agar gambar desktop mengikuti ukuran browser. Run terbaru memperbaiki logika resolusi Windows: karena proses Actions tidak memiliki display aktif, workflow **membuat Scheduled Task yang mencoba pengaturan 16:9 setelah login interaktif Windows** (`1920×1080`, `1600×900`, `1366×768`, atau `1280×720` yang tersedia). Jika sudah ada pengguna console aktif, task juga dicoba segera. Hasil perubahan aktual dicatat di `C:\ProgramData\RDP-Setup\wfs-display-resolution.log`. **Ini bukan jaminan driver virtual runner mendukung resolusi tersebut**; jika gagal, resolusi asli tetap digunakan dan menu Windows Display Settings masih dapat dipakai manual. Fullscreen browser tetap memerlukan klik atau F11.

**Layar penuh:** noVNC tidak dapat otomatis mengambil kontrol fullscreen browser tanpa interaksi pengguna. Gunakan **F11** di browser atau ikon **Full screen** pada toolbar noVNC. Untuk mengubah pengaturan secara manual: **noVNC → Settings → Scaling mode → Local scaling**.

Jika ingin mengubahnya pada koneksi yang **sudah berjalan**, cukup tambahkan fragment berikut setelah `vnc.html` di address bar (tanpa membuat ulang runner):

```text
#resize=scale&autoconnect=1
```

Refresh halaman jika perlu; Anda akan diminta autentikasi VNC lagi bila sesi baru memerlukannya. Pengaturan otomatis dari workflow hanya berlaku untuk **run baru** setelah perubahan di GitHub.

## 🔬 Verifikasi di Actions

Untuk mode noVNC, jalur yang diperiksa workflow adalah:

```text
Install noVNC + TightVNC
           ↓
Websockify sebagai Scheduled Task (SYSTEM) di 127.0.0.1:6081
           ↓
Tailscale Serve TCP 6082 atau HTTPS 443
           ↓
Verify noVNC HTTP, WebSocket and RFB
           ↓
Generate Dashboard Summary
           ↓
Remote READY – Keep Alive
```

Di Summary, lihat nilai **noVNC localhost HTTP**, **localhost WebSocket/VNC-RFB**, **Tailscale Serve self-probe HTTP**, dan **self-probe WebSocket/VNC-RFB**.

> [!NOTE]
> Self-probe berjalan **dari dalam runner**, bukan dari PC Anda. Hasil `PASS` membantu memisahkan masalah backend dan Serve, tetapi **belum membuktikan akses eksternal**. Setelah run aktif, uji koneksi dari PC Tailscale Anda sendiri.

## 🛠️ Diagnostik di Windows 10/11

Gunakan **PowerShell** dan **IP Tailscale terbaru** dari Summary run aktif (ganti `100.x.x.x` pada contoh):

```powershell
# Pastikan perangkat runner masih dapat dihubungi di tailnet
tailscale ping 100.x.x.x

# Mode default: Tailscale Serve TCP 6082
Test-NetConnection 100.x.x.x -Port 6082

# Periksa status HTTP, bukan sekadar port TCP
curl.exe --noproxy "*" --max-time 15 -sS -o NUL -w "HTTP %{http_code}\n" "http://100.x.x.x:6082/vnc.html"

# Untuk mode tailscale_https, cek port 443:
# Test-NetConnection <IP-TAILSCALE> -Port 443
# Buka URL https://<hostname>.ts.net/vnc.html dari Actions Summary
```

| Gejala | Pemeriksaan |
|:--|:--|
| Tailscale ping gagal | Runner mungkin sudah berhenti; periksa IP terbaru, perangkat online, dan login tailnet |
| Ping berhasil tetapi TCP 6082 gagal | Periksa mode `novnc_transport`, pemetaan Tailscale Serve, dan ACL/grants tailnet |
| TCP 6082 sukses tetapi `curl` gagal | Periksa langkah verifikasi HTTP dan status Scheduled Task websockify pada log run |
| HTTP 200 tetapi tombol **Connect** gagal | Buka `F12 → Network → WS`, lalu bandingkan log WebSocket/VNC-RFB di Actions |
| Browser mencoba HTTPS pada port 6082 | Gunakan `http://` secara eksplisit, nonaktifkan upgrade HTTPS otomatis untuk alamat tersebut bila diperlukan |
| Halaman lama mati | Runner GitHub Actions bersifat sementara; salin IP/URL dari run baru |
| Password VNC ditolak | Periksa pilihan password mode; VNCAuth hanya memproses delapan byte pertama |
| Ingin HTTPS tanpa port 6082 | Aktifkan MagicDNS dan HTTPS Certificates di pengaturan DNS Tailscale, lalu pilih `tailscale_https` pada run berikutnya |
| HTTPS Serve timeout, runner sebelumnya langsung gagal | Workflow baru melakukan retry/probe HTTPS dan otomatis fallback ke TCP 6082. Gunakan URL **Active transport** dari Summary. Jika tetap menginginkan HTTPS, periksa persetujuan tailnet dan sertifikat Tailscale |

Untuk diagnosis koneksi noVNC lebih detail, tambahkan `&logging=debug` ke URL yang sudah berisi `#resize=scale&autoconnect=1`, lalu lihat Developer Tools di browser.

### 🛡️ Jangan tutup terminal GitHub runner

Log [run #42505446065](https://github.com/wawanwfs/RDP/actions/runs/42505446065) menunjukkan runner menerima shutdown signal **sebelum** Tailscale logout. Karena runner GitHub-hosted bersifat sementara, menutup jendela console yang menjalankan proses runner dapat menghentikan seluruh sesi.

Workflow terbaru mencoba menyembunyikan jendela console proses **Runner.Listener** tanpa mematikan proses tersebut. Ini best effort: jika proses tidak memiliki console yang dapat diakses, langkah tersebut dilewati dengan peringatan.

Untuk meninggalkan desktop, gunakan **Disconnect** pada noVNC atau tutup tab browser—**jangan menutup terminal GitHub runner jika masih terlihat**. Logout dari blok `finally` pada Keep Alive sudah dihapus; logout Tailscale kini ditangani oleh step terpisah **Cleanup Tailscale Logout**. Jika GitHub menghentikan runner, koneksi tetap tidak dapat dipertahankan.
## ⏳ Durasi, Keep Alive, dan cleanup

- `duration_hours` tersedia dengan pilihan **1, 3, atau 6 jam**; penghitung sesi dimulai saat langkah **Remote READY – Keep Alive** berjalan.
- Job GitHub Actions tetap memiliki **`timeout-minutes: 360` (maksimal 6 jam dari awal job)**. Waktu instalasi ikut dihitung, sehingga opsi 6 jam tidak menjamin enam jam penuh *setelah* proses setup.
- Heartbeat Keep Alive tercetak setiap sekitar **60 detik**. Status `in_progress` pada tahap ini **normal**: runner sedang dipertahankan untuk remote access.
- Sesi dapat dihentikan lebih awal dengan **Cancel workflow**. Langkah cleanup mencoba melakukan `tailscale logout`; ketika dibatalkan paksa atau timeout, cleanup bersifat *best effort*.
- Data, aplikasi, dan proses di runner **tidak persist** setelah runner dihentikan.

## 📦 Aplikasi opsional

Form workflow menyediakan pilihan IDE (VS Code/Antigravity), editor video (CapCut/Shotcut), MetaTrader 4/5, AI API router (9Router/OmniRoute), coding agent (Codex CLI/Claude Code), AI agent (Hermes/OpenClaw/OpenCode), dan **ArtCraft Launcher**.

**ArtCraft Launcher terbaru:** workflow tidak lagi menginstal versi lama `v0.3.2`. Saat `install_artcraft=true`, installer membaca [rilis stabil terbaru dari `storytold/craft-launcher`](https://github.com/storytold/craft-launcher/releases/latest), mencari MSI Windows x64 resmi, mengunduhnya, lalu **memverifikasi SHA-256 terhadap digest aset GitHub** sebelum memasang untuk pengguna `RDP`. Versi yang didapat dicatat pada kolom **App Status** di Actions Summary. Rilis terbaru yang tersedia saat pembaruan panduan ini adalah **v0.16.1 (8 November 2026)**; run berikutnya bisa memakai versi yang lebih baru jika sudah diterbitkan. Jika API/rilis tidak dapat diverifikasi, instalasi akan gagal daripada memakai installer yang tidak tepercaya.

**Perbaikan lokasi installer v0.16+:** ArtCraft Launcher kini menggunakan `%LOCALAPPDATA%\Programs\ArtCraft\Launcher\artcraft-launcher.exe`, bukan path lama `%LOCALAPPDATA%\Programs\ArtCraft Launcher\artcraft-launcher.exe`. Workflow membaca path aktual yang dicatat MSI pada registry akun `RDP` (`HKCU\Software\Learning Machines LLC\ArtCraft Launcher`, nilai `InstallDir`), serta memeriksa kedua lokasi agar instalasi baru dan upgrade lama sama-sama dikenali. Jika instalasi masih gagal, lihat log step **Install Apps in Parallel (Skip Existing)** dan `msi.log` pada direktori diagnostik `C:\ProgramData\RDP-Setup\UserTasks\RdpSetup-ArtCraft-*`.

Ketersediaan setiap aplikasi bergantung pada image Windows, installer, dan hasil langkah instalasi. Periksa tabel **App Status** pada Actions Summary; jangan menganggap semua aplikasi berhasil hanya karena workflow mencapai tahap Remote READY.

## 🔒 Keamanan dan batasan

- Akses remote ditujukan ke **tailnet**, bukan tautan publik.
- Jangan membuka port RDP/VNC ke internet atau membagikan auth key/password.
- Untuk akun remote, gunakan password kuat dan hindari mempublikasikan log yang mengandung kredensial acak.
- noVNC dan RDP bisa menampilkan sesi Windows berbeda; tidak ada jaminan semua aplikasi memiliki UI aktif di console session.
- Proyek ini menyediakan **lingkungan pengujian sementara**. Keberhasilan koneksi nyata tetap harus dikonfirmasi pada perangkat klien.

---

<div align="center">

**WFS Tech • Build. Connect. Test.**

[▶ Run Windows Workspace](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml) · [GitHub Actions](https://github.com/wawanwfs/RDP/actions) · [Tailscale Docs](https://tailscale.com/kb) · [noVNC Project](https://github.com/novnc/noVNC)

</div>
