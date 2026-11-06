import { CONFIG } from "@/lib/config";

export async function loginToKeycloak(username: string, password: string, deviceId: string) {
  // 1. Cek kecocokan password via Keycloak (Next.js API)
  const res = await fetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password, deviceId }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error || "Login gagal, username atau password salah.");
  }

  // 2. JIKA PASSWORD BENAR, TEMBAK SPRING BOOT UNTUK CATAT LOG & CEK OTP
  const deviceRes = await fetch("http://localhost:8080/api/auth/check-device", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, deviceId }),
  });

  const deviceData = await deviceRes.json();
  
  if (!deviceRes.ok) {
    // Akan menangkap error seperti USER_LOCKED jika minta OTP lebih dari 5x sehari
    throw new Error(deviceData.error || "Gagal verifikasi perangkat di sistem ERP");
  }

  // Gabungkan token dari Keycloak dengan status requireOtp dari Spring Boot
  return { 
    ...data, 
    requireOtp: deviceData.requireOtp 
  };
}

export async function verifyOtp(username: string, otp: string, deviceId: string) {
  const response = await fetch("http://localhost:8080/api/auth/verify-otp", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    // Pastikan username ikut dikirim
    body: JSON.stringify({ username, otp, deviceId }), 
  });

  const data = await response.json();

  if (!response.ok || data.status !== "SUCCESS") {
    throw new Error(data.error || data.status || "Gagal verifikasi OTP");
  }

  return data;
}

export async function recordLogin(deviceId: string) {
  // Token tidak perlu dikirim manual, karena akan otomatis terbawa di dalam Cookie oleh browser
  await fetch(`${CONFIG.GATEWAY_URL}/api/admins/users/record-login`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Catatan: Anda harus menyesuaikan Gateway untuk membaca Bearer Token dari Cookie 
      // Atau tetap mengirimkan header tambahan jika Gateway hanya menerima Authorization header.
    },
    body: JSON.stringify({
      deviceId,
      status: "SUCCESS",
    }),
  });

  
}