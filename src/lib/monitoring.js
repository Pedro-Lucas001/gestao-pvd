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
