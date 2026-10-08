ALTER TABLE private.officers ADD COLUMN deleted_at text;
ALTER TABLE private.officers ADD COLUMN deleted_by text;
ALTER TABLE private.officers ADD COLUMN deletion_reason text;
INSERT INTO private.settings(key,value)
 SELECT 'owner_user_id',u.id::text FROM auth.users u
 WHERE lower(u.email)=(SELECT lower(value) FROM private.settings WHERE key='owner_email')
 ON CONFLICT(key) DO NOTHING;

CREATE FUNCTION private.protect_primary_account() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE root_id text;
BEGIN
 SELECT value INTO root_id FROM private.settings WHERE key='owner_user_id';
 IF TG_TABLE_NAME='principals' THEN
 IF OLD.id=root_id THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'O perfil principal 4º Pelotão não pode ser excluído.'; END IF;
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.role<>'comando' OR NEW.email IS DISTINCT FROM OLD.email THEN
   RAISE EXCEPTION 'O perfil principal 4º Pelotão deve manter sua identidade e privilégios.';
  END IF;
 END IF;
 ELSIF TG_TABLE_NAME='officers' THEN
 IF OLD.auth_user_id=root_id THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'O perfil principal 4º Pelotão não pode ser excluído.'; END IF;
  IF NEW.deleted_at IS NOT NULL OR NEW.active<>1 OR NEW.validated<>1 OR NEW.role NOT IN ('comando','administrador') OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id THEN
   RAISE EXCEPTION 'O cadastro vinculado ao perfil principal não pode perder acesso.';
  END IF;
 END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.protect_primary_account() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER protect_primary_principal BEFORE UPDATE OR DELETE ON private.principals
 FOR EACH ROW EXECUTE FUNCTION private.protect_primary_account();
CREATE TRIGGER protect_primary_officer BEFORE UPDATE OR DELETE ON private.officers
 FOR EACH ROW EXECUTE FUNCTION private.protect_primary_account();
