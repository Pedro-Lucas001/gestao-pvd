import { Flame } from "lucide-react";
export default function OperationalBrand({ title = "PDV" }) {
  return (
    <div className="pl:flex pl:min-w-0 pl:items-center pl:gap-2">
      <Flame
        className="pl:h-8 pl:w-8 pl:shrink-0 pl:text-[#ff5722]"
        aria-hidden="true"
      />
      <div className="pl:min-w-0">
        <h1 className="pl:m-0 pl:text-xl pl:font-bold pl:tracking-wider pl:text-white pl:sm:text-2xl">
          PLANETA <span className="pl:text-[#ff5722]">LANCHES</span>
        </h1>
        <p className="pl:mt-1 pl:text-xs pl:font-medium pl:tracking-wide pl:text-gray-400">
          {title}
        </p>
      </div>
    </div>
  );
}
