import { NextResponse } from "next/server";
import { cookies } from "next/headers";

export async function POST() {
  const cookieStore = await cookies();
  cookieStore.delete("access_token");
  cookieStore.delete("temp_token");
  return NextResponse.json({ status: "LOGGED_OUT" });
}
