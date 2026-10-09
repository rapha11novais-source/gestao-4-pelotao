CREATE TABLE private.platoons(id text PRIMARY KEY,name text NOT NULL);
INSERT INTO private.platoons VALUES ('p2','2º Pelotão'),('p3','3º Pelotão'),('p4','4º Pelotão');
CREATE TABLE private.cities(name text PRIMARY KEY,platoon_id text NOT NULL REFERENCES private.platoons(id));
INSERT INTO private.cities VALUES ('Ribeirão do Largo','p2'),('Encruzilhada','p2'),('Belo Campo','p3'),('Tremedal','p3'),('Piripá','p3'),('Condeúba','p4'),('Cordeiros','p4'),('Mortugaba','p4');
ALTER TABLE private.officers ADD COLUMN must_change_password boolean NOT NULL DEFAULT false;
ALTER TABLE private.officers ADD COLUMN credentials_job_id text;
ALTER TABLE private.officers ADD COLUMN home_platoon text NOT NULL DEFAULT 'p4' REFERENCES private.platoons(id);
ALTER TABLE private.officers ADD COLUMN created_txid bigint NOT NULL DEFAULT txid_current();
ALTER TABLE private.officers ADD COLUMN permissions jsonb NOT NULL DEFAULT '{}';
CREATE TABLE private.officer_platoons(officer_id text NOT NULL REFERENCES private.officers(id),platoon_id text NOT NULL REFERENCES private.platoons(id),active integer NOT NULL DEFAULT 1 CHECK(active IN(0,1)),PRIMARY KEY(officer_id,platoon_id));
CREATE INDEX officer_platoons_scope ON private.officer_platoons(platoon_id,officer_id) WHERE active=1;
INSERT INTO private.officer_platoons SELECT id,'p4',1 FROM private.officers;
ALTER TABLE private.inventory ADD COLUMN deleted_at text;
ALTER TABLE private.inventory ADD COLUMN deleted_by text;
ALTER TABLE private.inventory ADD COLUMN deletion_reason text;
ALTER TABLE private.audit ADD COLUMN actor_registration text;
ALTER TABLE private.audit ADD COLUMN city text;
ALTER TABLE private.audit ADD COLUMN platoon_id text;
UPDATE private.audit a SET city=COALESCE(a.after::jsonb->>'city',a.before::jsonb->>'city',a.after::jsonb->>'origin',(SELECT city FROM private.checks WHERE id=a.entity),(SELECT city FROM private.loads WHERE id=a.entity),(SELECT origin FROM private.movements WHERE id=a.entity),(SELECT city FROM private.inventory WHERE id=a.entity),(SELECT city FROM private.officers WHERE id=a.entity));
UPDATE private.audit a SET platoon_id=c.platoon_id FROM private.cities c WHERE c.name=a.city;
UPDATE private.audit a SET actor_registration=o.registration FROM private.principals p JOIN private.officers o ON o.id=p.officer_id WHERE p.id=a.actor;
ALTER TABLE private.platoons ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.officer_platoons ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.platoons,private.cities,private.officer_platoons FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.scope_allowed(who text,place text,cap text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE o private.officers; root_id text; global_officer text; p text;
BEGIN
 SELECT value INTO root_id FROM private.settings WHERE key='owner_user_id';
 IF who=root_id THEN RETURN true; END IF;
 SELECT value INTO global_officer FROM private.settings WHERE key='general_manager_officer_id';
 SELECT x.* INTO o FROM private.officers x LEFT JOIN private.principals u ON u.officer_id=x.id WHERE (x.auth_user_id=who OR u.id=who) AND x.active=1 AND x.validated=1 AND x.deleted_at IS NULL LIMIT 1;
 IF o.id IS NULL THEN RETURN false; END IF;
 IF o.id=global_officer THEN RETURN true; END IF;
 SELECT platoon_id INTO p FROM private.cities WHERE name=place;
 IF cap='global' THEN RETURN false; END IF;
 IF cap='operate' THEN RETURN EXISTS(SELECT 1 FROM private.officer_platoons m WHERE m.officer_id=o.id AND m.platoon_id=p AND m.active=1); END IF;
 IF cap='read' THEN RETURN o.role<>'policial' AND p=o.home_platoon; END IF;
 IF p IS DISTINCT FROM o.home_platoon THEN RETURN false; END IF;
 RETURN o.role IN('comando','comandante','administrador') OR (o.role='subcomandante' AND COALESCE((o.permissions->>cap)::boolean,false));
END; $$;
REVOKE ALL ON FUNCTION private.scope_allowed(text,text,text) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.enforce_operational_scope() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE who text; place text; cap text; allowed boolean; old_city text;
BEGIN
 who:=NULLIF(current_setting('app.actor_id',true),'');
 -- Privileged migration/import tools have no application context; public roles have no table privileges.
 IF who IS NULL THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 IF TG_TABLE_NAME IN ('audit','check_corrections') AND TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Histórico imutável' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='checks' AND TG_OP='UPDATE' THEN IF OLD.status='finalizada' AND (to_jsonb(NEW)-ARRAY['deleted_at','deleted_by','deletion_reason']) IS DISTINCT FROM (to_jsonb(OLD)-ARRAY['deleted_at','deleted_by','deletion_reason']) THEN RAISE EXCEPTION 'Conferência finalizada imutável' USING ERRCODE='42501'; END IF; END IF;
 IF private.scope_allowed(who,NULL,'global') THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 IF TG_TABLE_NAME='officers' AND TG_OP='UPDATE' THEN IF OLD.auth_user_id=who AND OLD.must_change_password AND NOT NEW.must_change_password AND (to_jsonb(NEW)-'must_change_password')=(to_jsonb(OLD)-'must_change_password') THEN RETURN NEW; END IF; END IF;
 IF TG_TABLE_NAME='inventory' THEN
  IF TG_OP='UPDATE' AND (to_jsonb(NEW)-'condition')=(to_jsonb(OLD)-'condition') THEN allowed:=private.scope_allowed(who,OLD.location,'operate');
  ELSE
   IF TG_OP='DELETE' THEN place:=OLD.city; old_city:=OLD.location; ELSE place:=NEW.city; old_city:=NEW.location; END IF;
   allowed:=private.scope_allowed(who,place,'materials') AND private.scope_allowed(who,old_city,'materials');
   IF TG_OP='UPDATE' THEN allowed:=allowed AND private.scope_allowed(who,OLD.city,'materials') AND private.scope_allowed(who,OLD.location,'materials'); END IF;
  END IF;
 ELSIF TG_TABLE_NAME='officers' THEN
  IF TG_OP='DELETE' THEN place:=OLD.city; ELSE place:=NEW.city; END IF;
  allowed:=private.scope_allowed(who,place,'officers');
  IF TG_OP='INSERT' THEN allowed:=allowed AND NEW.role='policial' AND NEW.permissions='{}'::jsonb;
  ELSIF TG_OP='UPDATE' THEN allowed:=allowed AND private.scope_allowed(who,OLD.city,'officers') AND NEW.home_platoon=OLD.home_platoon AND NEW.role=OLD.role AND NEW.permissions=OLD.permissions; END IF;
 ELSIF TG_TABLE_NAME='officer_platoons' THEN
  allowed:=TG_OP='INSERT' AND EXISTS(SELECT 1 FROM private.officers x WHERE x.id=NEW.officer_id AND x.home_platoon=NEW.platoon_id AND x.created_txid=txid_current() AND private.scope_allowed(who,x.city,'officers')) AND NOT EXISTS(SELECT 1 FROM private.officer_platoons m WHERE m.officer_id=NEW.officer_id);
 ELSIF TG_TABLE_NAME='categories' THEN allowed:=false;
 ELSIF TG_TABLE_NAME='checks' THEN
  IF TG_OP='DELETE' THEN allowed:=false;
  ELSIF TG_OP='UPDATE' AND NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN allowed:=private.scope_allowed(who,OLD.city,'materials');
  ELSE allowed:=private.scope_allowed(who,NEW.city,'operate') AND NEW.actor=who; END IF;
 ELSIF TG_TABLE_NAME='loads' THEN
  IF TG_OP='DELETE' THEN allowed:=false;
  ELSIF TG_OP='INSERT' THEN allowed:=NEW.actor=who AND private.scope_allowed(who,NEW.city,'operate');
  ELSE allowed:=(OLD.actor=who OR private.scope_allowed(who,OLD.city,'movements')); END IF;
 ELSIF TG_TABLE_NAME='movements' THEN
  IF TG_OP='DELETE' THEN place:=OLD.origin; cap:=OLD.destination; ELSE place:=NEW.origin; cap:=NEW.destination; END IF;
  allowed:=private.scope_allowed(who,place,'movements') AND private.scope_allowed(who,cap,'movements');
 ELSIF TG_TABLE_NAME='check_corrections' THEN allowed:=TG_OP='INSERT' AND NEW.actor=who AND EXISTS(SELECT 1 FROM private.checks c WHERE c.id=NEW.check_id AND private.scope_allowed(who,c.city,'materials'));
 ELSIF TG_TABLE_NAME='audit' THEN allowed:=TG_OP='INSERT' AND NEW.actor=who;
 END IF;
 IF NOT COALESCE(allowed,false) THEN RAISE EXCEPTION 'Operação fora das permissões do pelotão' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION private.enforce_operational_scope() FROM PUBLIC,anon,authenticated;
CREATE TABLE private.check_corrections(id text PRIMARY KEY,check_id text NOT NULL REFERENCES private.checks(id),actor text NOT NULL,actor_name text NOT NULL,actor_registration text,reason text NOT NULL,correction text NOT NULL,created_at text NOT NULL);
CREATE INDEX check_corrections_history ON private.check_corrections(check_id,created_at);
ALTER TABLE private.check_corrections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.check_corrections FROM PUBLIC,anon,authenticated;
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['inventory','officers','officer_platoons','categories','checks','loads','movements','audit','check_corrections'] LOOP EXECUTE format('CREATE TRIGGER enforce_platoon_scope BEFORE INSERT OR UPDATE OR DELETE ON private.%I FOR EACH ROW EXECUTE FUNCTION private.enforce_operational_scope()',t); END LOOP; END $$;

CREATE FUNCTION private.protect_general_manager() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN IF OLD.id=(SELECT value FROM private.settings WHERE key='general_manager_officer_id') THEN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Gestor geral protegido'; END IF;
 IF NEW.deleted_at IS NOT NULL OR NEW.active<>1 OR NEW.validated<>1 OR NEW.registration IS DISTINCT FROM OLD.registration OR NEW.id IS DISTINCT FROM OLD.id THEN RAISE EXCEPTION 'Gestor geral deve manter sua identidade e acesso'; END IF;
END IF; IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END; $$;
REVOKE ALL ON FUNCTION private.protect_general_manager() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER protect_general_manager BEFORE UPDATE OR DELETE ON private.officers FOR EACH ROW EXECUTE FUNCTION private.protect_general_manager();

INSERT INTO private.categories(id,name,mode) VALUES('outros','Outros equipamentos operacionais','quantidade') ON CONFLICT(id) DO NOTHING;
