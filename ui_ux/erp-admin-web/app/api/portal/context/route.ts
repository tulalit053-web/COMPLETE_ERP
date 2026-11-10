import { NextResponse } from "next/server";
import { cookies } from "next/headers";

const PROMO_SERVICE_URL = process.env.PROMO_SERVICE_URL || "http://localhost:8885";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const username = searchParams.get("username") || "";
  const companyId = searchParams.get("companyId") || "";

  const cookieStore = await cookies();
  const token = cookieStore.get("access_token")?.value;

  const qs = new URLSearchParams();
  if (username) qs.set("username", username);
  if (companyId) qs.set("companyId", companyId);

  try {
    const res = await fetch(`${PROMO_SERVICE_URL}/v1/me/context?${qs.toString()}`, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(username ? { "X-User-Name": username } : {}),
      },
      cache: "no-store",
    });

    if (!res.ok) {
      return NextResponse.json(
        { error: `Backend returned ${res.status}` },
        { status: res.status }
      );
    }

    const data = await res.json();
    return NextResponse.json(data);
  } catch (err) {
    console.error("Failed to fetch /v1/me/context:", err);
    return NextResponse.json(
      { error: "Gagal menghubungi erp-promo-service (:8885)" },
      { status: 502 }
    );
  }
}
