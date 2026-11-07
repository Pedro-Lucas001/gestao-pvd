-- O EXECUTE global concedido a PUBLIC também alcança anon/authenticated.
-- REVOKE em ALTER DEFAULT PRIVILEGES IN SCHEMA não remove o padrão global.
-- Preserva todos os GRANTs explícitos dos contratos 001–018.
begin;
revoke execute on all functions in schema public from public;
alter default privileges revoke execute on functions from public;
commit;
