export const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
export const supabasePublicKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY;

function publicKey(value) {
  if (!value || value.startsWith("sb_secret_")) return false;
  if (value.startsWith("sb_publishable_")) return true;
  try {
    return (
      JSON.parse(
        atob(value.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
      ).role === "anon"
    );
  } catch {
    return false;
  }
}
function validUrl(value) {
  try {
    const parsed = new URL(value);
    return (
      Boolean(parsed.hostname) &&
      (parsed.protocol === "https:" ||
        (parsed.protocol === "http:" &&
          ["localhost", "127.0.0.1"].includes(parsed.hostname)))
    );
  } catch {
    return false;
  }
}
export const configured = Boolean(
  validUrl(supabaseUrl) && publicKey(supabasePublicKey),
);
