import { cookies } from "next/headers";
import { CONFIG } from "./config";

export async function fetchWithToken(endpoint: string, options: RequestInit = {}) {
  // Ambil token dari brankas cookie
  const cookieStore = await cookies();
  const token = cookieStore.get("access_token")?.value;

  const headers = new Headers(options.headers);
  
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  // Sisipkan token jika ada
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  // Susun URL dengan rapi
  const baseUrl = CONFIG.GATEWAY_URL.replace(/\/$/, "");
  const path = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;
  const url = `${baseUrl}${path}`;

  // Eksekusi request tanpa cache
  const response = await fetch(url, {
    cache: "no-store", 
    ...options,
    headers,
  });

  return response;
}