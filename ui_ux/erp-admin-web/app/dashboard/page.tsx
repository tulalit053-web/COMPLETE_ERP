import { Suspense } from "react";
import { fetchWithToken } from "@/lib/api-client";
import { redirect } from "next/navigation";

// Tambahkan ini agar Next.js tahu halaman ini boleh diblokir hingga data siap
export const instant = false;

async function UserProfile() {
  const res = await fetchWithToken("/api/admins/me");
  
  if (res.status === 401) {
    redirect("/login");
  }

  const userData = res.ok ? await res.json() : null;

  if (!userData) {
    return <p className="text-red-500">Gagal memuat profil pengguna.</p>;
  }

  return (
    <div className="p-4 bg-white rounded shadow">
      <p><strong>Info User:</strong> {JSON.stringify(userData)}</p>
    </div>
  );
}

export default async function DashboardPage() {
  return (
    <div className="p-8 space-y-4">
      <h1 className="text-2xl font-bold">Dashboard ERP</h1>
      
      <Suspense fallback={<p>Memuat profil pengguna...</p>}>
        <UserProfile />
      </Suspense>
    </div>
  );
}