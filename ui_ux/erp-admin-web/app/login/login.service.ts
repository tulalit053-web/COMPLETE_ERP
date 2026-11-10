import { CONFIG } from "@/lib/config";

export async function loginToKeycloak(username: string, password: string, deviceId: string) {
  const res = await fetch("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password, deviceId }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(data.error || "Login gagal, username atau password salah.");
  }

  return data;
}

export async function verifyOtp(username: string, otp: string, deviceId: string) {
  const response = await fetch("/api/auth/verify-otp", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ username, otp, deviceId }),
  });

  const data = await response.json();

  if (!response.ok || data.status !== "SUCCESS") {
    throw new Error(data.error || data.status || "Gagal verifikasi OTP");
  }

  return data;
}

export async function recordLogin(deviceId: string) {
  await fetch(`${CONFIG.GATEWAY_URL}/api/admins/users/record-login`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      deviceId,
      status: "SUCCESS",
    }),
  });
}
