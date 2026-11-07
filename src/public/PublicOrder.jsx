import { lazy } from "react";
import { useLocation } from "react-router-dom";
import CustomerOrder from "./CustomerOrder";
const LegacyOrder = lazy(() => import("./LegacyOrder"));
export default function PublicOrder() {
  const route = useLocation();
  return new URLSearchParams(route.search).has("token") ? <LegacyOrder /> : <CustomerOrder />;
}
