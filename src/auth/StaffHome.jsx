import { Link } from "react-router-dom";
import { ChefHat, Headset, ShoppingBag, Store } from "lucide-react";
import { useAuth } from "./context";
import { accessModules } from "./modules";
import "../admin/AdminControl.css";
const icons = {
  "/pdv": ShoppingBag,
  "/pedidos-online": Store,
  "/cozinha": ChefHat,
  "/atendimento": Headset,
};
export function StaffHomeView({ profile }) {
  return (
    <section className="staff-home">
      <span className="eyebrow">ÁREA DO FUNCIONÁRIO</span>
      <h1>Olá, {profile.name.split(" ")[0]}.</h1>
      <p>
        Seu acesso é individual. Escolha sua atividade para começar o
        atendimento.
      </p>
      <div className="staff-home-grid">
        {accessModules
          .filter(
            (m) => m.path !== "/funcionario" && m.roles.includes(profile.role),
          )
          .map((m) => {
            const Icon = icons[m.path] || Store;
            return (
              <Link key={m.path} to={m.path}>
                <Icon size={28} />
                <h2>{m.label}</h2>
                <p>
                  {m.path === "/pdv"
                    ? "Abra seu turno e registre as vendas."
                    : m.path === "/cozinha"
                      ? "Acompanhe os pedidos e o preparo do seu setor."
                      : m.path === "/pedidos-online"
                        ? "Confira os pedidos recebidos pelo site."
                        : "Acompanhe as conversas atribuídas a você."}
                </p>
                <strong>Acessar →</strong>
              </Link>
            );
          })}
      </div>
      <p className="control-muted">
        Use Bloquear terminal ao se afastar ou Trocar funcionário para outra
        pessoa entrar com o próprio PIN.
      </p>
    </section>
  );
}
export default function StaffHome() {
  const { profile } = useAuth();
  return <StaffHomeView profile={profile} />;
}
