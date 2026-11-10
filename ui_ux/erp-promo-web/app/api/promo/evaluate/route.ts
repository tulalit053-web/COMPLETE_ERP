import { NextResponse } from "next/server";
import { fetchWithToken } from "@/lib/api-client";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const res = await fetchWithToken("/api/promo/v1/promos/evaluate", {
      method: "POST",
      body: JSON.stringify(body),
    });
    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (error) {
    const msg = error instanceof Error ? error.message : "Failed to evaluate cart";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
