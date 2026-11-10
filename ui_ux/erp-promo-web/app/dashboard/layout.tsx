import React from "react";
import { PromoProvider } from "@/lib/promo-context";
import DashboardShellView from "./dashboard-shell-view";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <PromoProvider>
      <DashboardShellView>{children}</DashboardShellView>
    </PromoProvider>
  );
}
