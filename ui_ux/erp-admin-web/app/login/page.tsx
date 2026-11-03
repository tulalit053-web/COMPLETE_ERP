"use client";

import { useState } from "react";
import LoginView from "./login-view";
import { loginToKeycloak, verifyOtp } from "./login.service"; // Tambahkan import verifyOtp

export default function LoginPage() {
  const [isOtpMode, setIsOtpMode] = useState(false);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

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
        
        if (res.requireOtp) {
          setIsOtpMode(true); // Ubah tampilan ke form OTP
        } else {
          window.location.href = "/dashboard";
        }
      } else {
        // Mode 2: Submit OTP ke BFF
        await verifyOtp(otp, deviceId);
        window.location.href = "/dashboard"; // Masuk ke dashboard jika OTP valid
      }

    } catch (err) {
      const message = err instanceof Error ? err.message : "Terjadi kesalahan";
      setError(message);
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
    />
  );
}