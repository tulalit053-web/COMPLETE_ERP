import { NextResponse } from "next/server";
import { fetchPromoBackend } from "@/lib/api-client";

export async function GET(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const username = searchParams.get("username") || "";
    const companyId = searchParams.get("companyId") || "";

    const qs = new URLSearchParams();
    if (username) qs.set("username", username);
    if (companyId) qs.set("companyId", companyId);
    const queryStr = qs.toString() ? `?${qs.toString()}` : "";

    const res = await fetchPromoBackend(`/v1/admin/promos${queryStr}`, {
      method: "GET",
      headers: username ? { "X-User-Name": username } : undefined,
      cache: "no-store",
    });
    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (err) {
    console.error("Error fetching promos:", err);
    return NextResponse.json(
      { error: "Gagal mengambil daftar promo" },
      { status: 500 }
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const username = body.username || "";
    const companyId = body.companyId || "";

    const qs = new URLSearchParams();
    if (username) qs.set("username", username);
    if (companyId) qs.set("companyId", String(companyId));
    const queryStr = qs.toString() ? `?${qs.toString()}` : "";

    const res = await fetchPromoBackend(`/v1/admin/promos${queryStr}`, {
      method: "POST",
      headers: username ? { "X-User-Name": username } : undefined,
      body: JSON.stringify(body),
    });
    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json(
        { error: data.message || data.error || "Gagal membuat promo" },
        { status: res.status }
      );
    }
    return NextResponse.json(data, { status: res.status });
  } catch (err) {
    console.error("Error creating promo:", err);
    return NextResponse.json(
      { error: "Gagal menyimpan promo baru" },
      { status: 500 }
    );
  }
}
