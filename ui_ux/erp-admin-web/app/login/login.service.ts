import { CONFIG } from "@/lib/config";

export async function loginToKeycloak(username: string, password: string, deviceId: string) {
  const res = await fetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password, deviceId }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error || "Login gagal");
  }
  return data;
}

export async function verifyOtp(otp: string, deviceId: string) {
  const res = await fetch("/api/auth/verify-otp", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ otp, deviceId }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error || "Gagal memverifikasi OTP");
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