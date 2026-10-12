-- Compatibility only: do not rewrite any existing audit or operational row.
CREATE FUNCTION private.json_document(value jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE STRICT SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF jsonb_typeof(value)='string' THEN RETURN (value#>>'{}')::jsonb; END IF;
 RETURN value;
EXCEPTION WHEN invalid_text_representation THEN RETURN '{}'::jsonb;
END;$$;
REVOKE ALL ON FUNCTION private.json_document(jsonb) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.scope_allowed(who text,place text,cap text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE o private.officers;root_id text;global_officer text;p text;
BEGIN
 SELECT value INTO root_id FROM private.settings WHERE key='owner_user_id';IF who=root_id THEN RETURN true;END IF;
 SELECT value INTO global_officer FROM private.settings WHERE key='general_manager_officer_id';
 SELECT x.* INTO o FROM private.officers x LEFT JOIN private.principals u ON u.officer_id=x.id WHERE (x.auth_user_id=who OR u.id=who) AND x.active=1 AND x.validated=1 AND x.deleted_at IS NULL LIMIT 1;
 IF o.id IS NULL THEN RETURN false;END IF;IF o.id=global_officer THEN RETURN true;END IF;
 SELECT platoon_id INTO p FROM private.cities WHERE name=place;
 IF cap='global' THEN RETURN false;END IF;
 IF cap='read' THEN RETURN o.role<>'policial' AND p=o.home_platoon;END IF;
 IF NOT EXISTS(SELECT 1 FROM private.cities c JOIN private.platoons x ON x.id=c.platoon_id WHERE c.name=place AND c.active AND x.active) THEN RETURN false;END IF;
 IF cap='operate' THEN
  IF o.role<>'policial' AND p IS DISTINCT FROM o.home_platoon THEN RETURN false; END IF;
  IF o.role='policial' AND EXISTS(SELECT 1 FROM private.service_members sm JOIN private.services s ON s.id=sm.service_id WHERE sm.officer_id=o.id AND sm.status='ativo' AND s.status<>'encerrado' AND s.city<>place) THEN RETURN false; END IF;
  RETURN EXISTS(SELECT 1 FROM private.officer_platoons m WHERE m.officer_id=o.id AND m.platoon_id=p AND m.active=1);END IF;
 IF p IS DISTINCT FROM o.home_platoon THEN RETURN false;END IF;
 RETURN o.role IN('comando','comandante','administrador') OR (o.role='subcomandante' AND COALESCE((private.json_document(o.permissions)->>cap)::boolean,false));
END; $$;
