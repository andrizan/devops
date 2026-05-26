# Update NGINX ke Repo Resmi (Ubuntu 20.04+)

Playbook ini melakukan:
- Install dependency repo (`curl`, `gnupg2`, `ca-certificates`, `lsb-release`, `ubuntu-keyring`)
- Pasang key resmi NGINX dan verifikasi fingerprint
- Set repo resmi `nginx.org` + apt pinning agar prioritas ke paket resmi
- Update/instal `nginx` versi terbaru dari repo resmi
- Menjalankan update dengan mode rolling

## 1. Prasyarat

- Control node sudah terpasang `ansible`
- Akses SSH ke semua target server
- User SSH punya hak `sudo` (karena playbook pakai `become: true`)

## 2. Siapkan daftar host

Edit file [host.ini](./host.ini):

```ini
[nginx_targets]
app01 ansible_host=10.10.10.11 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
app02 ansible_host=10.10.10.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa

[nginx_targets:vars]
ansible_port=22
ansible_python_interpreter=auto_silent
# Optional global SSH options:
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

## 3. Cek koneksi SSH (opsional tapi disarankan)

```bash
ansible -i update-nginx/host.ini nginx_targets -m ping
```

## 4. Jalankan playbook

Perintah standar:

```bash
ansible-playbook -i update-nginx/host.ini update-nginx/update-nginx.yml
```

Default rolling update adalah `20%` host per batch.

## 5. Ubah ukuran rolling batch

Contoh 10% per batch:

```bash
ansible-playbook -i update-nginx/host.ini update-nginx/update-nginx.yml -e "rollout_batch=10%"
```

Contoh 2 host per batch:

```bash
ansible-playbook -i update-nginx/host.ini update-nginx/update-nginx.yml -e "rollout_batch=2"
```

## 6. Dry run (cek perubahan tanpa eksekusi penuh)

```bash
ansible-playbook -i update-nginx/host.ini update-nginx/update-nginx.yml --check
```

## Catatan

- Target OS wajib Ubuntu Server `20.04` ke atas.
- Playbook akan memastikan kandidat paket `nginx` berasal dari `nginx.org`.
- Saat upgrade paket, service `nginx` bisa restart. Rolling update mengurangi dampak downtime total.
