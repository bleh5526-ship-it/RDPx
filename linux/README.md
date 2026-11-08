<div align="center">

# 🐧 WFS Linux Remote Workspace

### 5 Linux distros · 4 desktop environments · 20 combinations

**Desktop Linux yang responsif melalui browser, privat dengan Tailscale, dijalankan dari GitHub Actions.**

[![Linux](https://img.shields.io/badge/Linux-5%20Distros-17805C?style=for-the-badge&logo=linux)](https://docs.linuxserver.io/images/docker-webtop/)
[![Desktop](https://img.shields.io/badge/UI-Xfce%20%7C%20KDE%20%7C%20MATE%20%7C%20i3-2255DD?style=for-the-badge)](https://docs.linuxserver.io/selkies/user-guide/)
[![Tailscale](https://img.shields.io/badge/Tailscale-Private-242424?style=for-the-badge)](https://tailscale.com/)

[**▶ Jalankan Linux Desktop**](https://github.com/wawanwfs/RDP/actions/workflows/linux-remote-workspace.yml) · [Workflow Windows](https://github.com/wawanwfs/RDP/actions/workflows/windows-remote-workspace-with-apps.yml) · [README Root](../README.md)

</div>

---

## ✨ Pilihan Linux dan Desktop

| Distro | Xfce | MATE | KDE Plasma | i3 |
|:--|:--:|:--:|:--:|:--:|
| **Debian** | ✅ | ✅ | ✅ | ✅ |
| **Ubuntu** | ✅ | ✅ | ✅ | ✅ |
| **Fedora** | ✅ | ✅ | ✅ | ✅ |
| **Arch Linux** | ✅ | ✅ | ✅ | ✅ |
| **Alpine Linux** | ✅ | ✅ | ✅ | ✅ |

**Xfce** adalah pilihan default terbaik untuk pemakaian ringan dan nyaman. **MATE** cocok untuk tampilan desktop klasik. **KDE Plasma** lebih modern dan kaya pengaturan tetapi menggunakan lebih banyak sumber daya. **i3** paling minimalis dan efisien tetapi lebih cocok untuk pengguna yang nyaman memakai keyboard.

> [!IMPORTANT]
> Kelima distro berjalan sebagai **container LinuxServer.io Webtop** pada runner GitHub **Ubuntu 24.04**, bukan VM/kernel terpisah. Ini menyediakan userland dan tampilan dari distro yang dipilih, tetapi **tidak dapat mengganti kernel host**. Desktop menggunakan **Selkies**, bukan noVNC/RDP native; aksesnya melalui browser dengan responsivitas dan auto-resize. Versi distro mengikuti image upstream yang dipilih; tidak dipatok ke Debian 12/13 tertentu.

## 🚀 Cara menjalankan

1. Di [GitHub Repository Secrets](https://github.com/wawanwfs/RDP/settings/secrets/actions), gunakan secret `TAILSCALE_AUTH_KEY` yang sudah berfungsi pada workflow Windows. Buat secret baru **`LINUX_DESKTOP_PASSWORD`** dengan password kuat minimal **12 karakter**.
2. Pasang dan login [Tailscale](https://tailscale.com/download) di komputer/Android yang akan digunakan. Pastikan berada dalam tailnet yang sama dan peraturan ACL/grants mengizinkan akses.
3. Buka [**WFS Linux Remote Workspace Actions**](https://github.com/wawanwfs/RDP/actions/workflows/linux-remote-workspace.yml) → **Run workflow** → `main`. Pilih distro, desktop, transport, aplikasi dan durasi.
4. Buka URL yang muncul pada langkah **Publish exactly one private HTTPS browser endpoint** atau Actions Summary dari **run aktif**. Username: **`wfs`**. Password: nilai secret `LINUX_DESKTOP_PASSWORD`.

| Input workflow | Pilihan | Default |
|:--|:--|:--|
| `distro` | debian, ubuntu, fedora, arch, alpine | debian |
| `desktop` | xfce, mate, kde, i3 | xfce |
| `duration_hours` | 1, 3, 6 jam | 6 |
| `transport` | auto, tailnet_https, tailnet_tls_tcp | auto |
| `apps_bundle` | none, developer, office, media, all | none |
| `install_artcraft` | true atau false | false |

## 🔐 Arsitektur aman

```text
          GitHub Actions — Ubuntu 24.04 ephemeral runner
                          │
             LinuxServer Webtop container
             Debian / Ubuntu / Fedora / Arch / Alpine
                Xfce / MATE / KDE Plasma / i3
                          │
             Selkies Desktop HTTPS + Login
              ↙                         ↘
  127.0.0.1:13000 (HTTP)        127.0.0.1:13001 (HTTPS)
              │                          │
     Tailscale Serve HTTPS 443   Tailscale Serve TCP 6082
        valid tailnet TLS          native Webtop HTTPS
              └────────────┬─────────────┘
                           │
            SATU remote endpoint saja
                           │
          Perangkat dengan Tailscale aktif
```

**Mode `auto`**: mencoba HTTPS resmi Tailscale `https://hostname.ts.net/`, lalu jika gagal beralih ke `https://100.x.x.x:6082/`. Port TCP 6082 meneruskan HTTPS milik Webtop, sehingga **sertifikat self-signed akan menyebabkan peringatan browser**. Periksa alamat IP dari Actions Summary lalu terima peringatan hanya jika Anda yakin sedang mengakses runner milik sendiri. Untuk menghindari peringatan, aktifkan **MagicDNS + HTTPS Certificates** pada tailnet lalu gunakan `tailnet_https`. Koneksi tidak menggunakan Cloudflare, Funnel atau port forwarding router.

Seluruh port Docker diikat ke **loopback `127.0.0.1`**, bukan IP publik. Password Webtop dibaca dari file yang dihasilkan dari GitHub Secret dan **tidak dicetak pada log**. Login browser adalah lapisan tambahan; tetap gunakan tailnet ACL/grants yang ketat. Akses ke desktop dapat memberikan sudo di dalam container.

## 📦 Instalasi aplikasi (opsional)

| Bundle | Paket utama |
|:--|:--|
| `none` | Hanya aplikasi bawaan image, start tercepat |
| `developer` | Git, curl, wget, Python, Node.js/npm, Vim |
| `office` | LibreOffice |
| `media` | GIMP, VLC |
| `all` | Developer + Office + Media |

`install_artcraft=true` akan mengambil **rilis stabil ArtCraft Launcher terbaru** dari [repository upstream resmi](https://github.com/storytold/craft-launcher/releases/latest), memvalidasi URL, ukuran dan SHA-256 dari metadata GitHub sebelum memasang file **DEB** (Debian/Ubuntu), **RPM** (Fedora), atau **pkg.tar.zst** (Arch). Alpine menggunakan musl dan belum didukung paket native ArtCraft sehingga instalasi dilewati dengan peringatan.

Instalasi aplikasi opsional bersifat **best effort**; jika repository paket atau dependensi bermasalah, desktop remote yang sudah hidup tetap dipertahankan. Penginstalan paket tambahan dapat membuat waktu setup jauh lebih panjang.

## 🖥️ Auto-resize dan layar penuh

Desktop Selkies sudah menggunakan `SELKIES_ENABLE_RESIZE=true`, sehingga menyesuaikan ukuran jendela browser. Tidak perlu mengubah resolusi Windows/driver virtual seperti workflow sebelumnya. Gunakan **F11** atau tombol fullscreen browser untuk mengisi layar monitor. Mode KDE dan aplikasi grafis berat dapat lebih lambat pada CPU runner tanpa GPU; gunakan Debian atau Alpine **Xfce** jika mengutamakan responsivitas.

## 🛠️ Troubleshooting

Dari **PowerShell Windows** dengan IP terbaru dari Actions Summary:

```powershell
tailscale ping 100.x.x.x
Test-NetConnection 100.x.x.x -Port 6082
# Buka https://100.x.x.x:6082/ untuk fallback TLS
# Mode HTTPS resmi menggunakan hostname .ts.net dan port 443.
```

Pada log GitHub Actions, langkah Start, Publish, dan Keep Alive memeriksa kondisi container dan Tailscale. Untuk mendiagnosis container dari shell host runner:

```bash
docker ps
docker logs --tail 50 wfs-linux-webtop
tailscale serve status
tailscale ip -4
```

| Gejala | Solusi |
|:--|:--|
| Password tidak ditemukan | Tambahkan `LINUX_DESKTOP_PASSWORD` minimal 12 karakter |
| Pull image gagal | Pilih Debian + Xfce atau ulangi saat registry LinuxServer tersedia |
| Webtop local HTTP check gagal | Periksa Docker logs, auth, dan startup desktop |
| HTTPS resmi timeout | Gunakan `transport=auto` atau aktifkan HTTPS Certificates |
| Sertifikat tidak valid pada 6082 | Normal untuk TLS self-signed Webtop; gunakan port 443 untuk trusted certificate |
| Layar kosong atau terlambat | Periksa browser Console/Network dan log container, coba Xfce |
| ArtCraft / bundle gagal | Instalasi opsional tidak memutus akses desktop; baca step terkait |

## ⏳ Keep Alive dan batas platform

Pilihan **1/3/6 jam** dihitung sejak remote selesai disiapkan, tetapi **total GitHub Actions job dibatasi 360 menit** termasuk pull image, instalasi dan setup. Sesudah mencapai batas, runner berhenti dan datanya hilang. Jangan menutup atau mematikan proses GitHub runner dari dalam desktop; untuk meninggalkan tampilan cukup tutup tab browser. Untuk menghentikan sesi, gunakan **Cancel workflow** di GitHub Actions. Cleanup mencoba menghentikan container dan menghapus file password; Tailscale GitHub Action menjalankan logout pada post-step.

**Bukan hosting permanen** dan tidak ada persistence lintas run. Backup file penting sebelum mengakhiri pekerjaan.

## 📚 Referensi

Sistem memakai [LinuxServer Webtop](https://docs.linuxserver.io/images/docker-webtop/), [Selkies](https://docs.linuxserver.io/selkies/user-guide/), [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve), dan [official Tailscale GitHub Action](https://tailscale.com/docs/integrations/github/github-action). Workflow Windows tidak diubah; Linux adalah workflow baru yang terpisah.

---

<div align="center">

**WFS Tech — Linux Anywhere, Privately.**

[**▶ Run Linux Workspace**](https://github.com/wawanwfs/RDP/actions/workflows/linux-remote-workspace.yml)

</div>
