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

    const res = await fetchPromoBackend(`/v1/dashboard/overview${queryStr}`, {
      method: "GET",
      headers: username ? { "X-User-Name": username } : undefined,
      cache: "no-store",
    });

    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (err) {
    console.error("Error fetching promo overview:", err);
    return NextResponse.json(
      { error: "Gagal mengambil ringkasan PromoHub dari backend" },
      { status: 500 }
    );
  }
}
