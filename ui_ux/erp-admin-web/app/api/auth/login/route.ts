import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { CONFIG } from "@/lib/config";

export async function POST(request: Request) {
  const body = await request.json();
  const { username, password, deviceId } = body;

  // 1. Tangkap IP dan User-Agent asli dari browser klien
  const forwardedFor = request.headers.get("x-forwarded-for") || "127.0.0.1";
  const userAgent = request.headers.get("user-agent") || "Unknown";

  try {
    // ==========================================
    // TAHAP 1: OTENTIKASI KE KEYCLOAK
    // ==========================================
    const kcRes = await fetch(`${CONFIG.KEYCLOAK_URL}/realms/erp-realm/protocol/openid-connect/token`, {
      method: "POST",
      headers: { 
        "Content-Type": "application/x-www-form-urlencoded",
        "X-Forwarded-For": forwardedFor,
        "User-Agent": userAgent // Teruskan ke Keycloak untuk anti Brute-Force
      },
      body: new URLSearchParams({
        grant_type: "password",
        client_id: "erp-client",
        username,
        password,
      }),
    });

    const kcData = await kcRes.json();

    if (!kcRes.ok) {
      console.log(">>> Respons Error Keycloak:", kcData);
      let errorMessage = "Login gagal. Silakan coba lagi.";
      
      if (kcData.error_description === "Invalid user credentials") {
        errorMessage = "Username/Password salah, atau akun Anda sedang terkunci sementara.";
      } else if (kcData.error_description === "Account disabled" || kcData.error_description === "Account is disabled") {
        errorMessage = "Akun Anda dinonaktifkan oleh Administrator.";
      } else if (kcData.error_description) {
        errorMessage = kcData.error_description;
      }
      return NextResponse.json({ error: errorMessage }, { status: 401 });
    }


    // ==========================================
    // TAHAP 2: VERIFIKASI DEVICE KE SPRING BOOT
    // ==========================================
    // Catatan: Anda harus membuat endpoint /verify-device ini di Spring Boot nanti.
    // Endpoint ini bertugas mengecek tabel adm_log_login dan mengirim OTP jika device baru.
    const sbRes = await fetch(`${CONFIG.GATEWAY_URL}/api/admins/users/verify-device`, { method: "POST", headers: { "Content-Type": "application/json", "Authorization": `Bearer ${kcData.access_token}`, // Bukti user valid
        "X-Forwarded-For": forwardedFor,
        "User-Agent": userAgent // <--- Fix masalah tulisan "node" di database
      },
      body: JSON.stringify({ 
        deviceId, 
        status: "SUCCESS" 
      }),
    });

    const sbData = await sbRes.json();
    const cookieStore = await cookies();

    // ==========================================
    // TAHAP 3: EVALUASI STATUS DARI SPRING BOOT
    // ==========================================
    if (sbData.status === "REQUIRE_OTP") {
      // Skenario Device Baru: Tanam cookie sementara (berlaku 5 menit)
      // Cookie ini TIDAK BISA dipakai untuk akses API lain selain endpoint verifikasi OTP
      cookieStore.set("temp_token", kcData.access_token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax",
        maxAge: 300, 
        path: "/",
      });
      
      // Beritahu frontend untuk menampilkan form OTP
      return NextResponse.json({ success: true, requireOtp: true, message: "OTP telah dikirim" });
      
    } else {
      // Skenario Device Dikenal (Status OK/SUCCESS)
      // Tanam cookie utama untuk akses Dashboard dan API lainnya
      cookieStore.set("access_token", kcData.access_token, {
        httpOnly: true,
        secure: process.env.NODE_ENV === "production",
        sameSite: "lax",
        maxAge: kcData.expires_in,
        path: "/",
      });

      return NextResponse.json({ success: true, requireOtp: false });
    }

  } catch (error) {
    console.error("Terjadi kesalahan sistem saat login:", error);
    return NextResponse.json({ error: "Terjadi kesalahan internal server" }, { status: 500 });
  }
}