Detail Tech Stack \& Versi Pustaka (Library)



Proyek ERP Microservices (Fokus: Admin Service)



Dokumen ini merangkum seluruh teknologi dan versi dependensi spesifik yang menggerakkan sistem ERP ini. Sangat berguna untuk keperluan deployment, audit keamanan, atau saat penambahan pengembang baru ke dalam tim.



1\. Backend (Layanan Mikro Java)



Sistem backend dibangun menggunakan ekosistem Spring yang teruji di level enterprise.



Java Runtime: Java 17 LTS (Terlihat dari rujukan memori Method.java:568 di stack trace).



Framework Utama: Spring Boot v3.3.0



Inti Spring (Core/Context/Web): Spring Framework v6.1.8



Server Web Bawaan: Apache Tomcat v10.1.24 (Embedded)



Spring Cloud Ecosystem:



spring-cloud-starter-netflix-eureka-client: Untuk layanan penemuan (Service Discovery).



spring-cloud-starter-config: Untuk konfigurasi terpusat.



spring-cloud-starter-gateway: API Gateway (Di rute port 8084).



2\. Keamanan \& Otentikasi (Backend)



Otentikasi didistribusikan menggunakan standar OAuth2 dan enkripsi tingkat tinggi.



Modul Keamanan: Spring Security v6.3.0



Otentikasi Token: spring-security-oauth2-resource-server v6.3.0 (Memvalidasi JWT yang diterbitkan Keycloak).



Enkripsi Hashing (OTP): BCryptPasswordEncoder (Bawaan Spring Security).



Enkripsi Data (PII): Algoritma AES-256 menggunakan javax.crypto.Cipher (Bawaan Java JDK) untuk mengenkripsi Email, NIK, dan No HP.



3\. Basis Data \& ORM



Koneksi dan manipulasi basis data dilakukan secara efisien menggunakan pendekatan ORM.



Database Server: PostgreSQL (Minimal v13+, direkomendasikan v15+)



Driver JDBC: PostgreSQL JDBC Driver v42.7.3



Connection Pooling: HikariCP v5.1.0 (Optimalisasi koneksi DB).



ORM Framework: Hibernate ORM Core v6.5.2.Final



Abstraksi Data: Spring Data JPA v3.3.0



4\. Frontend (Antarmuka Pengguna)



Antarmuka web dibangun dengan framework berbasis React yang dirender di sisi server (Server-Side Rendering / SSR) dan sisi klien.



Core Framework: Next.js 14+ (Menggunakan paradigma App Router).



UI Library: React 18+



Bahasa Pemrograman: TypeScript (Superset dari JavaScript dengan strict typing).



CSS Framework: Tailwind CSS v3+ (Kustomisasi gaya secara langsung melalui class).



Komponen Antarmuka: shadcn/ui (Dibangun di atas Radix UI Primitives, menyediakan aksesibilitas tinggi dan komponen yang bisa disesuaikan sepenuhnya).



Ikonografi: lucide-react.



5\. Identity \& Access Management (IAM)



Server SSO Utama: Keycloak (Berjalan di port 8180).



Protokol IAM: OpenID Connect (OIDC) \& OAuth 2.0.



Integrasi Pihak Ketiga (Opsional): Google Identity Provider (OAuth).



Pustaka Admin Java: keycloak-admin-client (Digunakan oleh UserApplicationService untuk mengelola pengguna Keycloak langsung dari basis data lokal).



6\. Utilitas Lainnya



Notifikasi / Email: spring-boot-starter-mail (Membungkus JavaMailSender untuk pengiriman OTP melalui SMTP).



Manajemen Proyek \& Build: Maven (Backend) \& npm / pnpm (Frontend).



Peralatan IDE: Spring Tool Suite (STS) untuk Java, Visual Studio Code untuk Frontend, DBeaver/pgAdmin untuk pemantauan PostgreSQL.

