import { lazy, Suspense } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import ErrorBoundary from "./components/ErrorBoundary";
import PublicMenu from "./public/PublicMenu";
import CartProvider from "./public/CartProvider";

// A autenticação e os módulos internos só carregam nas rotas da equipe.
const InternalApp = lazy(() => import("./InternalApp"));
const PublicOrder = lazy(() => import("./public/PublicOrder"));

export default function App() {
  return (
    <ErrorBoundary area="application">
      <BrowserRouter>
        <CartProvider>
        <Suspense fallback={<div className="loading">Carregando…</div>}>
          <Routes>
            <Route path="/" element={<PublicMenu />} />
            <Route path="/cardapio" element={<PublicMenu />} />
            <Route
              path="/previa"
              element={<Navigate to="/cardapio" replace />}
            />
            <Route path="/pedido" element={<PublicOrder />} />
            <Route path="/*" element={<InternalApp />} />
          </Routes>
        </Suspense>
        </CartProvider>
      </BrowserRouter>
    </ErrorBoundary>
  );
}
