export const CONFIG = {
  GATEWAY_URL: process.env.NEXT_PUBLIC_GATEWAY_URL || "http://localhost:8084",
  KEYCLOAK_URL: process.env.NEXT_PUBLIC_KEYCLOAK_URL || "http://localhost:8180",
  PROMO_SERVICE_DIRECT_URL: process.env.PROMO_SERVICE_DIRECT_URL || "http://localhost:8885",
};
