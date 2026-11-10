import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { CONFIG } from "@/lib/config";

export async function POST(request: Request) {
  const body = await request.json();
  const { username, password, deviceId } = body;

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
        "User-Agent": userAgent,
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
      } else if (
        kcData.error_description === "Account disabled" ||
        kcData.error_description === "Account is disabled"
      ) {
        errorMessage = "Akun Anda dinonaktifkan oleh Administrator.";
      } else if (kcData.error_description) {
        errorMessage = kcData.error_description;
      }
      return NextResponse.json({ error: errorMessage }, { status: 401 });
    }

    // ==========================================
    // TAHAP 2: VERIFIKASI DEVICE KE SPRING BOOT
    // (Sementara dinonaktifkan untuk mode developer lokal agar tidak terkendala SMTP Email)
    // ==========================================
    /*
    const sbRes = await fetch(`${CONFIG.GATEWAY_URL}/api/admins/users/verify-device`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${kcData.access_token}`,
        "X-Forwarded-For": forwardedFor,
        "User-Agent": userAgent,
      },
      body: JSON.stringify({
        deviceId,
        status: "SUCCESS",
      }),
    });

    const sbData = await sbRes.json();
    */

    const cookieStore = await cookies();

    cookieStore.set("access_token", kcData.access_token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      maxAge: kcData.expires_in || 3600,
      path: "/",
    });

    return NextResponse.json({ success: true, requireOtp: false });
  } catch (error) {
    console.error("Terjadi kesalahan sistem saat login:", error);
    return NextResponse.json({ error: "Terjadi kesalahan internal server" }, { status: 500 });
  }
}
