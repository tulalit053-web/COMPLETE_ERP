BAGIAN 1: Definisi Aktor dan Peran (RBAC & Multi-Tenancy)
Sistem ini menggunakan penggabungan Keycloak Realm Roles dan Isolasi Company di Database.

Bapak Anton (Global Super Admin)

Role Keycloak: SUPER_ADMIN

Company ID: NULL (Tidak terikat pada satu perusahaan, bisa mengakses semua data).

Tugas: Mengelola master data perusahaan (Company), mendaftarkan aplikasi (ACC, CRM, HRD) ke perusahaan tertentu, dan bisa melakukan Unlock Account jika ada user yang terkunci sistem.

Budi Santoso (Company Admin - PT Maju Jaya)

Role Keycloak: ADMIN

Company ID: 1 (Hanya bisa melihat dan mengelola data PT Maju Jaya).

Tugas: Mengelola Role, mengatur Permission tiap menu, serta membuat akun untuk karyawan PT Maju Jaya (akun akan tersinkronisasi otomatis ke Keycloak).

Dewi HRD (HR Manager - PT Maju Jaya)

Role Keycloak: HR

Company ID: 1

Tugas: Mengakses modul HRD System (Employee, Payroll, Attendance). Dewi tidak akan bisa melihat menu Keuangan atau CRM.

Andi Finance (Finance Staff - PT Maju Jaya)

Role Keycloak: FINANCE

Company ID: 1

Tugas: Mengakses modul Accounting System (GL, AP, AR, Cash & Bank).

Citra Sales (Sales/User - PT Maju Jaya)

Role Keycloak: USER

Company ID: 1

Tugas: Mengakses modul CRM System (Lead, Contact, Opportunity).

BAGIAN 2: Alur Proses Bisnis (Business Flows)
Berikut adalah urutan proses bisnis dari hulu ke hilir berdasarkan sistem yang telah kita buat:

Flow 1: Setup Awal & Registrasi (Oleh Global Super Admin)
Anton (Super Admin) login ke sistem.

Ia mendaftarkan klien baru bernama "PT Maju Jaya".

Ia mengatur modul apa saja yang dibeli/diaktifkan oleh klien ini (Misal: PT Maju Jaya hanya berlangganan modul HRD dan ACC, tidak langganan CRM).

Anton membuatkan akun pertama untuk Budi Santoso sebagai Company Admin PT Maju Jaya.

Flow 2: Otentikasi & Keamanan (Alur Login OJK Compliance)
Alur ini berlaku untuk semua aktor saat mencoba mengakses sistem:

Dewi HRD membuka halaman Login Next.js.

Ia memasukkan username dan password (atau klik Login with Google). Sistem Next.js menembak API /api/auth/login (Keycloak).

Jika password benar, Next.js mengirimkan ID Perangkat (Browser) Dewi ke Backend Spring Boot (/api/auth/check-device).

Validasi Perangkat (Oleh Spring Boot):

Skenario A (Perangkat Lama): Jika Dewi login dari laptop kantor yang biasa ia pakai, sistem langsung membiarkannya masuk ke Dashboard.

Skenario B (Perangkat Baru): Dewi login dari HP. Sistem menahan akses Dewi dan memicu sistem MFA (Multi-Factor Authentication).

Proses OTP (Skenario B):

Backend membuat 6 digit angka acak, melakukan hashing dengan BCrypt, lalu menyimpannya ke tabel adm_otp dengan status PENDING.

Backend memicu Thread asinkron untuk mengirimkan OTP tersebut ke Email atau WhatsApp Dewi.

Muncul layar Modal Pop-up di browser Dewi meminta kode.

Keamanan Ekstra (Brute Force & Lockout):

Jika Dewi salah ketik 3x beruntun, OTP hangus dan ia disuruh login ulang (Max Attempt Reached).

Jika Dewi me-request OTP lebih dari 5x dalam sehari, akun Dewi otomatis terkunci (is_active = 0). Anton (Super Admin) atau Budi (Company Admin) harus membuka kuncinya.

Flow 3: Pembuatan Layout Dinamis (Setelah Login Berhasil)
Setelah Dewi HRD lolos OTP dan masuk ke /dashboard, Next.js langsung memanggil endpoint GET /me/menus di backend.

Backend (Spring Boot) akan mengecek:

"Siapa orang ini?" -> Dewi HRD dari PT Maju Jaya.

"Apa Role-nya?" -> HR.

"Aplikasi apa yang aktif di PT Maju Jaya?" -> HRD & ACC (CRM tidak aktif).

Backend mengembalikan daftar menu berbentuk tree (hierarki) khusus untuk HR.

Next.js menampilkan Sidebar di kiri layar yang isinya murni hanya menu-menu HRD (Karyawan, Presensi, Penggajian).

Flow 4: Manajemen Pengguna & Sinkronisasi Keycloak (Oleh Company Admin)
Budi Santoso ingin menambahkan karyawan baru, Andi Finance.

Budi masuk ke menu "Manajemen User" dan mengisi formulir tambah user.

Saat Budi menekan "Simpan", backend Spring Boot melakukan 2 hal secara transaksional:

Langkah 1: Memanggil API Keycloak (targetRealm) untuk mendaftarkan username Andi, menyetel password sementaranya, dan men-set Required Actions menjadi UPDATE_PASSWORD (memaksa Andi ganti password saat login pertama kalinya).

Langkah 2: Menyimpan data Andi (Nama, Company ID, Role ID, beserta Email dan No HP yang dienkripsi menggunakan AES-256) ke tabel PostgreSQL adm_mst_user_application.

Jika salah satu langkah gagal, seluruh proses dibatalkan (Rollback Transaction) untuk menjaga konsistensi data.

Flow 5: Operasional Harian & Jejak Audit
Andi Finance masuk ke sistem dan mencoba membuka menu "Approval Pembayaran".

Spring Boot mencegat permintaan Andi melalui PermissionInterceptor.

Interseptor memeriksa tabel adm_role_menus untuk Role Finance. Karena Andi punya hak approve di menu tersebut, transaksi diteruskan.

Setiap kali Andi, Budi, atau Dewi berhasil masuk ke sistem, aksi mereka diam-diam dicatat di tabel adm_log_login lengkap dengan IP Address, Waktu, dan User Agent, untuk kebutuhan audit log.