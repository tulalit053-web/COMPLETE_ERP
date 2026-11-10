"use client";

import React, { useState, useEffect } from "react";
import { usePromo } from "@/lib/promo-context";
import SimulatorView from "./simulator-view";
import {
  runCartSimulation,
  SimulatorEvaluatePayload,
  SimulatorEvaluateResult,
} from "./simulator.service";

export default function SimulatorPage() {
  const { lang, currency, data, showToast } = usePromo();
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<SimulatorEvaluateResult | null>(null);

  const [payload, setPayload] = useState<SimulatorEvaluatePayload>({
    channel: "APP",
    currency: "IDR",
    locale: "id-ID",
    customer: {
      id: "CUST-8821",
      tier: "GOLD",
      segments: ["ACTIVE_MEMBER"],
      isNewUser: false,
      daysSinceLastPurchase: 12,
    },
    cart: {
      lines: [
        {
          lineId: "L1",
          sku: "SKU-TEE-01",
          category: "APPAREL",
          brand: "ERP",
          qty: 2,
          unitPrice: 150000,
        },
      ],
      shippingFee: 20000,
      vouchers: [],
    },
    payment: {
      method: "CARD",
      bin: "411111",
      issuer: "BCA",
    },
  });

  const executeSimulation = async (customPayload?: SimulatorEvaluatePayload) => {
    const target = customPayload || payload;
    try {
      setRunning(true);
      const res = await runCartSimulation({
        ...target,
        locale: lang === "id" ? "id-ID" : "en-US",
      });
      setResult(res);
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Simulasi gagal";
      showToast(msg);
    } finally {
      setRunning(false);
    }
  };

  useEffect(() => {
    executeSimulation();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleApplyPreset = (preset: "bxgy" | "bca" | "newuser" | "tiered") => {
    let next: SimulatorEvaluatePayload = { ...payload };
    if (preset === "bxgy") {
      next = {
        ...payload,
        customer: { ...payload.customer, isNewUser: false },
        cart: {
          lines: [
            {
              lineId: "L1",
              sku: "SKU-TEE-01",
              category: "APPAREL",
              brand: "ERP",
              qty: 2,
              unitPrice: 150000,
            },
          ],
          shippingFee: 20000,
          vouchers: [],
        },
      };
    } else if (preset === "bca") {
      next = {
        ...payload,
        cart: {
          lines: [
            {
              lineId: "L1",
              sku: "SKU-SHOE-99",
              category: "FOOTWEAR",
              brand: "ERP",
              qty: 1,
              unitPrice: 600000,
            },
          ],
          shippingFee: 25000,
          vouchers: [],
        },
        payment: { method: "CARD", bin: "411111", issuer: "BCA" },
      };
    } else if (preset === "tiered") {
      next = {
        ...payload,
        cart: {
          lines: [
            {
              lineId: "L1",
              sku: "SKU-JACKET-01",
              category: "APPAREL",
              brand: "ERP",
              qty: 2,
              unitPrice: 600000,
            },
          ],
          shippingFee: 25000,
          vouchers: [],
        },
      };
    } else if (preset === "newuser") {
      next = {
        ...payload,
        customer: {
          id: "CUST-NEW-01",
          tier: "SILVER",
          segments: ["NEW_USER"],
          isNewUser: true,
          daysSinceLastPurchase: 0,
        },
        cart: {
          lines: [
            {
              lineId: "L1",
              sku: "SKU-TEE-01",
              category: "APPAREL",
              brand: "ERP",
              qty: 1,
              unitPrice: 150000,
            },
          ],
          shippingFee: 15000,
          vouchers: ["WELCOME50"],
        },
      };
    }
    setPayload(next);
    executeSimulation(next);
  };

  return (
    <SimulatorView
      lang={lang}
      currency={currency}
      rate={data?.fxRateUsdIdr || 16000}
      payload={payload}
      onPayloadChange={setPayload}
      onApplyPreset={handleApplyPreset}
      onRunSimulation={() => executeSimulation()}
      running={running}
      result={result}
    />
  );
}
