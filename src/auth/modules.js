// A mesma matriz governa a navegação e as rotas; o banco valida as operações.
export const accessModules = [
  {
    path: "/pdv",
    label: "Frente de caixa",
    icon: "sales",
    roles: ["admin", "cashier"],
  },
  {
    path: "/cozinha",
    label: "Cozinha · KDS",
    icon: "kitchen",
    roles: ["admin", "kitchen"],
  },
  {
    path: "/dashboard",
    label: "Visão geral",
    icon: "dashboard",
    roles: ["admin"],
  },
  {
    path: "/estoque",
    label: "Estoque e fichas",
    icon: "inventory",
    roles: ["admin"],
  },
  {
    path: "/relatorios",
    label: "Relatórios",
    icon: "reports",
    roles: ["admin"],
  },
  { path: "/dre", label: "DRE gerencial", icon: "reports", roles: ["admin"] },
  {
    path: "/atendimento",
    label: "Atendimento e delivery",
    icon: "team",
    roles: ["admin", "cashier"],
  },
  {
    path: "/catalogo",
    label: "Catálogo e preços",
    icon: "sales",
    roles: ["admin"],
  },
  {
    path: "/pagamentos",
    label: "Pagamentos e estornos",
    icon: "dashboard",
    roles: ["admin"],
  },
  {
    path: "/auditoria",
    label: "Auditoria",
    icon: "security",
    roles: ["admin"],
  },
  {
    path: "/links",
    label: "QR e autoatendimento",
    icon: "links",
    roles: ["admin"],
  },
  {
    path: "/integracoes",
    label: "Integrações",
    icon: "inventory",
    roles: ["admin"],
  },
  {
    path: "/equipe",
    label: "Equipe e acessos",
    icon: "team",
    roles: ["admin"],
  },
];

export const roleDescriptions = [
  {
    role: "cashier",
    name: "Caixa e atendimento",
    scope:
      "Vendas, pagamentos da própria operação, turno e atendimento atribuído.",
  },
  {
    role: "kitchen",
    name: "Cozinha",
    scope:
      "Fila, preparo e conclusão dos pedidos do setor atribuído. Sem dados financeiros.",
  },
  {
    role: "admin",
    name: "Administrador",
    scope:
      "Gestão completa, catálogo, estoque, relatórios, finanças e administração da equipe.",
  },
];
