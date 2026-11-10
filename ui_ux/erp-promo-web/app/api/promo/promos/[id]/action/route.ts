import { NextResponse } from "next/server";
import { fetchPromoBackend } from "@/lib/api-client";

export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await context.params;
    const body = await request.json();
    const action = body.action || "submit";
    const username = body.username || "";

    const allowedActions = ["submit", "approve", "reject", "extend", "pause"];
    if (!allowedActions.includes(action)) {
      return NextResponse.json(
        { error: "Action tidak valid" },
        { status: 400 }
      );
    }

    const res = await fetchPromoBackend(`/v1/admin/promos/${encodeURIComponent(id)}/${action}`, {
      method: "POST",
      headers: username ? { "X-User-Name": username } : undefined,
      body: JSON.stringify({
        actor: body.actor,
        note: body.reason || body.note,
        reason: body.reason || body.note,
        newExpiresAt: body.newExpiresAt,
      }),
    });

    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json(
        { error: data.message || data.error || "Aksi ditolak oleh server" },
        { status: res.status }
      );
    }

    return NextResponse.json(data, { status: 200 });
  } catch (err) {
    console.error("Error executing promo governance action:", err);
    return NextResponse.json(
      { error: "Gagal memproses aksi governance promo" },
      { status: 500 }
    );
  }
}
