"use client";

import { useState } from "react";
import LoginView from "./login-view";
import { loginToKeycloak, verifyOtp } from "./login.service";

export default function LoginPage() {
  const [isOtpMode, setIsOtpMode] = useState(false);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Fungsi untuk mengembalikan form ke halaman login awal
  const handleCancelOtp = () => {
    setIsOtpMode(false);
    setOtp("");
    setPassword(""); 
    setError("");
    // Hapus token Keycloak sementara yang tersimpan dari tahap pertama (jika ada)
    localStorage.removeItem("access_token");
    localStorage.removeItem("refresh_token");
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError("");

    try {
      let deviceId = localStorage.getItem("device_id");
      if (!deviceId) {
        deviceId = crypto.randomUUID();
        localStorage.setItem("device_id", deviceId);
      }

      if (!isOtpMode) {
        // Mode 1: Login Standar
        const res = await loginToKeycloak(username, password, deviceId);
        
        // Tangkap penolakan dari backend (misal: user_locked dilempar via error key)
        if (res.status === "USER_LOCKED" || res.error === "USER_LOCKED") {
           throw new Error("USER_LOCKED");
        }
        
        if (res.requireOtp) {
          setIsOtpMode(true);
        } else {
          window.location.href = "/dashboard";
        }
      } else {
        // Mode 2: Submit OTP ke BFF
        await verifyOtp(username, otp, deviceId); // PASTIKAN username DIKIRIM KE VERIFY OTP
        window.location.href = "/dashboard"; 
      }

    } catch (err) {
      const message = err instanceof Error ? err.message : "Terjadi kesalahan";
      
      // LOGIKA PENANGANAN STATUS KEAMANAN
      if (message.includes("USER_LOCKED")) {
        alert("Akun Anda dikunci karena melebihi batas pengiriman OTP harian (5x). Silakan hubungi Admin.");
        handleCancelOtp();
      } else if (message.includes("MAX_ATTEMPT_REACHED")) {
        alert("Anda telah salah memasukkan OTP 3 kali. Silakan login kembali dari awal.");
        handleCancelOtp();
      } else if (message.includes("INVALID_CODE")) {
        // JIKA SALAH KODE, JANGAN BATALKAN (Biarkan mereka mencoba sampai attempt habis)
        setError("Kode OTP yang Anda masukkan salah.");
      } else if (message.includes("EXPIRED")) {
        setError("Kode OTP sudah kadaluarsa. Silakan batal dan login kembali.");
      } else {
        setError(message);
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <LoginView
      isOtpMode={isOtpMode}
      username={username}
      password={password}
      otp={otp}
      loading={loading}
      error={error}
      onUsernameChange={setUsername}
      onPasswordChange={setPassword}
      onOtpChange={setOtp}
      onSubmit={handleLogin}
      onCancel={handleCancelOtp}
    />
  );
}