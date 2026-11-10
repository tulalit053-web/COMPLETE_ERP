import { cookies, headers as nextHeaders } from "next/headers";
import { CONFIG } from "./config";

/**
 * Server-side BFF API Client.
 * - Membaca access_token dari HttpOnly Cookie (aman dari XSS).
 * - Meneruskan X-Forwarded-For dan User-Agent asli klien untuk keperluan audit log.
 * - Jika token tersedia, memanggil melalui API Gateway (:8084/api/promo/...).
 * - Jika belum ada token (mode development/testing), fallback aman ke erp-promo-service (:8885).
 */
export async function fetchWithToken(endpoint: string, options: RequestInit = {}) {
  const cookieStore = await cookies();
  const reqHeaders = await nextHeaders();
  const token = cookieStore.get("access_token")?.value;

  const headers = new Headers(options.headers);
  if (!headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }

  const forwardedFor = reqHeaders.get("x-forwarded-for") || "127.0.0.1";
  const userAgent = reqHeaders.get("user-agent") || "PromoHub-Web";
  headers.set("X-Forwarded-For", forwardedFor);
  headers.set("User-Agent", userAgent);

  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  const cleanPath = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;

  // Jika endpoint mengarah ke /api/promo/... dan ada token, panggil via Gateway (:8084).
  // Jika Gateway mengembalikan 401 atau token belum ada saat dev, fallback ke direct service (:8885).
  if (cleanPath.startsWith("/api/promo/")) {
    const directPath = cleanPath.replace(/^\/api\/promo/, "");
    if (token) {
      try {
        const gwUrl = `${CONFIG.GATEWAY_URL.replace(/\/$/, "")}${cleanPath}`;
        const gwRes = await fetch(gwUrl, { cache: "no-store", ...options, headers });
        if (gwRes.status !== 401 && gwRes.status !== 502 && gwRes.status !== 503) {
          return gwRes;
        }
      } catch {
        // Fallback ke direct service jika gateway sedang restart
      }
    }
    const directUrl = `${CONFIG.PROMO_SERVICE_DIRECT_URL.replace(/\/$/, "")}${directPath}`;
    const directHeaders = new Headers(headers);
    directHeaders.delete("Authorization");
    return fetch(directUrl, { cache: "no-store", ...options, headers: directHeaders });
  }

  const baseUrl = CONFIG.GATEWAY_URL.replace(/\/$/, "");
  const url = `${baseUrl}${cleanPath}`;
  return fetch(url, {
    cache: "no-store",
    ...options,
    headers,
  });
}
