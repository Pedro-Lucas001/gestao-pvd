let reporter = null;
export function installReporter(callback) {
  reporter = callback;
}
export function reportError(error, context = "ui") {
  // Sentry can be injected with installReporter((error,meta)=>
  // Sentry.captureException(error,{tags:meta})). Do not attach forms or sessions.
  if (reporter)
    try {
      reporter(new Error(error?.name || "ApplicationError"), { context });
    } catch {
      /* Monitoring must never stop the PDV. */
    }
}

export async function setupMonitoring() {
  const dsn = import.meta.env.VITE_SENTRY_DSN;
  if (!dsn) return;
  const Sentry = await import("@sentry/react");
  Sentry.init({
    dsn,
    environment:
      import.meta.env.VITE_APP_ENV === "production" ? "production" : "staging",
    sendDefaultPii: false,
    defaultIntegrations: false,
    integrations: [],
    autoSessionTracking: false,
    tracesSampleRate: 0,
    sendClientReports: false,
    beforeSend(event) {
      // Deliberately omit route/query strings: a public tracking capability may be
      // present in the URL. No identities, forms, request bodies or breadcrumbs.
      return {
        event_id: event.event_id,
        timestamp: event.timestamp,
        platform: "javascript",
        level: "error",
        exception: {
          values: [{ type: "ApplicationError", value: "Falha operacional" }],
        },
        tags: { area: String(event.tags?.area || "ui").slice(0, 80) },
      };
    },
  });
  installReporter((error, metadata) =>
    Sentry.captureException(error, { tags: { area: metadata.context } }),
  );
}
