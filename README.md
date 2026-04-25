# OpenVPN-Bonding

Bond 2 atau lebih koneksi menjadi satu (konsep/teori).

Video demo: https://youtu.be/9dtMrifnAcs

## Ringkasan

Repo ini menyediakan script untuk:

- **Server**: instalasi & menjalankan OpenVPN pada port **1191** dan **1192**
- **Client**: instalasi & menjalankan client OpenVPN yang memakai shared secret (`ta.key`)

Semua contoh perintah di bawah ditulis dalam blok kode agar mudah dibedakan dari penjelasan.

## Prasyarat

- Sistem berbasis Linux (perintah memakai `sudo`/`bash`).
- OpenVPN terpasang/akan dipasang oleh script.
- Pastikan firewall / security group **mengizinkan port 1191 dan 1192** (TCP/UDP sesuai konfigurasi OpenVPN di script).

## Cara Pakai

### 1) Server Side

1. Clone repo dan masuk ke foldernya:

```bash
git clone https://github.com/mgi24/OpenVPN-Bonding.git
cd OpenVPN-Bonding
```

2. Jalankan installer server:

```bash
sudo bash serverinstall.sh
```

3. Ambil isi `ta.key` (ini yang perlu disalin ke client):

```bash
cat /etc/openvpn/ta.key
```

4. Simpan output kunci tersebut di tempat aman untuk dipakai di sisi client.

5. Start service/server:

```bash
sudo bash serverstart.sh
```

6. Verifikasi firewall tidak memblok port berikut:

```text
1191
1192
```

### 2) Client Side

1. Clone repo dan masuk ke foldernya:

```bash
git clone https://github.com/mgi24/OpenVPN-Bonding.git
cd OpenVPN-Bonding
```

2. Edit `clientinstall.sh` dan isi IP server kamu.

3. Buat/isi file `ta.key` di client, lalu tempelkan isi kunci dari server (hasil `cat /etc/openvpn/ta.key` di atas):

```bash
sudo nano /etc/openvpn/ta.key
```

4. Jalankan installer client:

```bash
sudo bash clientinstall.sh
```

5. Start client:

```bash
sudo bash clientstart.sh
```

## Shut Down

Jalankan perintah ini di masing-masing mesin:

- Di client:

```bash
sudo bash clientdown.sh
```

- Di server:

```bash
sudo bash serverdown.sh
```

## Catatan

- `ta.key` adalah kunci bersama (shared secret). Jangan dibagikan publik.
- Jika koneksi gagal, paling sering penyebabnya adalah port 1191/1192 tertutup firewall atau IP server di `clientinstall.sh` belum benar.
