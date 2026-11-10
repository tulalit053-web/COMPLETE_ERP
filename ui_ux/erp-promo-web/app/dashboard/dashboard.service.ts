export interface GovernanceActionPayload {
  action: "submit" | "approve" | "reject" | "extend" | "pause";
  actor: string;
  username?: string;
  reason: string;
  newExpiresAt?: string;
}

export async function executePromoGovernanceAction(
  promoIdOrCode: string,
  payload: GovernanceActionPayload
) {
  const response = await fetch(`/api/promo/promos/${encodeURIComponent(promoIdOrCode)}/action`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Gagal memproses aksi governance promo");
  }
  return data;
}

export async function logoutFromSession() {
  if (typeof window !== "undefined") {
    localStorage.removeItem("erp_active_username");
  }
  await fetch("/api/auth/logout", { method: "POST" });
}
