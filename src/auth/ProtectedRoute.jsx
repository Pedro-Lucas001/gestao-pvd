import { Navigate, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "./context";
import { canAccess } from "./permissions";
export default function ProtectedRoute({ roles }) {
  const { profile, session, loading, authError } = useAuth();
  const location = useLocation();
  if (loading) return <div className="loading">Verificando seu acesso…</div>;
  if (!session)
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  if (authError || !profile) return <Navigate to="/login" replace />;
  if (!canAccess(profile.role, roles))
    return <Navigate to="/acesso-negado" replace />;
  return <Outlet />;
}
