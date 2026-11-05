import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import "./design/operational.css";
import App from "./App.jsx";
import { reportError, setupMonitoring } from "./lib/monitoring";
setupMonitoring().catch(() => {});
window.addEventListener("unhandledrejection", (event) =>
  reportError(event.reason, "unhandled_promise"),
);

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
