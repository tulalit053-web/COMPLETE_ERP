import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { CONFIG } from "@/lib/config";

export async function POST(request: Request) {
  const body = await request.json();
  const { otp, deviceId } = body;

  const forwardedFor = request.headers.get("x-forwarded-for") || "127.0.0.1";
  const userAgent = request.headers.get("user-agent") || "Unknown";

  try {
    const cookieStore = await cookies();
    const tempToken = cookieStore.get("temp_token")?.value;

    // Pastikan user sudah melewati tahap 1 (punya token sementara)
    if (!tempToken) {
      return NextResponse.json(
        { error: "Sesi verifikasi tidak valid atau sudah kedaluwarsa (lebih dari 5 menit)." },
        { status: 401 }
      );
    }

    // Tembak API verifikasi OTP di Spring Boot
    const sbRes = await fetch(`${CONFIG.GATEWAY_URL}/api/admins/users/verify-otp`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${tempToken}`,
        "X-Forwarded-For": forwardedFor,
        "User-Agent": userAgent,
      },
      body: JSON.stringify({ deviceId, otp }),
    });

    const sbData = await sbRes.json();

    if (!sbRes.ok || sbData.status !== "SUCCESS") {
      return NextResponse.json({ error: "Kode OTP salah atau sudah kedaluwarsa." }, { status: 400 });
    }

    // Jika OTP Benar: Hapus token sementara dan jadikan token utama
    cookieStore.delete("temp_token");
    cookieStore.set("access_token", tempToken, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      maxAge: 86400, // Sesuaikan dengan umur token Keycloak Anda (misal 1 hari)
      path: "/",
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Error verify OTP:", error);
    return NextResponse.json({ error: "Terjadi kesalahan internal server" }, { status: 500 });
  }
}