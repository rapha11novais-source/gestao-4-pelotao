ALTER TABLE private.platoons ADD COLUMN parent_unit text NOT NULL DEFAULT '80ª CIPM';
ALTER TABLE private.platoons ADD COLUMN active boolean NOT NULL DEFAULT true;
ALTER TABLE private.platoons ADD COLUMN commander_officer_id text REFERENCES private.officers(id);
CREATE INDEX platoons_commander ON private.platoons(commander_officer_id);
UPDATE private.platoons p SET commander_officer_id=(SELECT o.id FROM private.officers o WHERE o.home_platoon=p.id AND o.role IN('comandante','comando') AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL ORDER BY o.id LIMIT 1);
CREATE TABLE private.municipalities(id text PRIMARY KEY,name text NOT NULL,uf text NOT NULL CHECK(length(uf)=2),active boolean NOT NULL DEFAULT true,UNIQUE(name,uf));
INSERT INTO private.municipalities(id,name,uf) SELECT 'mun-'||md5(name),name,'BA' FROM private.cities;
ALTER TABLE private.cities ADD COLUMN municipality_id text REFERENCES private.municipalities(id);
ALTER TABLE private.cities ADD COLUMN label text NOT NULL DEFAULT 'DPM';
ALTER TABLE private.cities ADD COLUMN active boolean NOT NULL DEFAULT true;
UPDATE private.cities SET municipality_id='mun-'||md5(name);
CREATE INDEX cities_municipality ON private.cities(municipality_id);
CREATE INDEX cities_platoon ON private.cities(platoon_id);
ALTER TABLE private.inventory ADD COLUMN armament_type text CHECK(armament_type IN('pistola','longa','outro'));
DROP INDEX private.checks_city_day;
DROP INDEX private.checks_actor_day;
DROP INDEX private.checks_officer_day;
ALTER TABLE private.loads DROP CONSTRAINT loads_actor_service_day_key;
ALTER TABLE private.loads DROP CONSTRAINT loads_officer_id_service_day_key;
ALTER TABLE private.loads ADD CONSTRAINT loads_officer_service_key UNIQUE(officer_id,check_id);
ALTER TABLE private.loads ADD COLUMN armament jsonb;
ALTER TABLE private.loads ADD COLUMN closing jsonb;
ALTER TABLE private.load_items ADD COLUMN returned_quantity integer NOT NULL DEFAULT 0;
ALTER TABLE private.load_items ADD COLUMN transferred_quantity integer NOT NULL DEFAULT 0;
ALTER TABLE private.load_items ADD CONSTRAINT load_item_balance CHECK(returned_quantity>=0 AND transferred_quantity>=0 AND returned_quantity+transferred_quantity<=quantity);
UPDATE private.load_items li SET returned_quantity=quantity FROM private.loads l WHERE l.id=li.load_id AND l.status='devolvida';
CREATE TABLE private.services(
 id text PRIMARY KEY REFERENCES private.checks(id),city text NOT NULL REFERENCES private.cities(name),platoon_id text NOT NULL REFERENCES private.platoons(id),platoon_name text NOT NULL,unit_name text NOT NULL,municipality_name text NOT NULL,municipality_uf text NOT NULL,
 commander_actor text NOT NULL,commander_officer_id text REFERENCES private.officers(id),commander_name text NOT NULL,crew jsonb NOT NULL,
 started_at text NOT NULL,duration_hours integer NOT NULL CHECK(duration_hours IN(8,24,48,72,96)),planned_end text NOT NULL,
 status text NOT NULL CHECK(status IN('ativo','aguardando_encerramento','encerrado')),conference_at text,created_at text NOT NULL,ended_at text,ended_by text,closing jsonb,legacy boolean NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX services_one_open_unit ON private.services(city) WHERE status<>'encerrado';
CREATE INDEX services_scope ON private.services(platoon_id,status,started_at);
CREATE INDEX services_commander ON private.services(commander_officer_id);
CREATE TABLE private.service_members(service_id text NOT NULL REFERENCES private.services(id),officer_id text NOT NULL REFERENCES private.officers(id),name text NOT NULL,registration text NOT NULL,rank text NOT NULL,status text NOT NULL DEFAULT 'ativo' CHECK(status IN('ativo','encerrado')),load_id text REFERENCES private.loads(id),started_at text,duration_hours integer CHECK(duration_hours IN(8,24,48,72,96)),planned_end text,ended_at text,ended_by text,closing jsonb,PRIMARY KEY(service_id,officer_id));
CREATE INDEX service_members_officer ON private.service_members(officer_id,status);
CREATE INDEX service_members_load ON private.service_members(load_id);
CREATE TABLE private.service_events(id text PRIMARY KEY,service_id text NOT NULL REFERENCES private.services(id),kind text NOT NULL,actor text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,created_at text NOT NULL,payload jsonb NOT NULL);
CREATE INDEX service_events_history ON private.service_events(service_id,created_at);
CREATE TABLE private.fixed_pistols(id text PRIMARY KEY,officer_id text NOT NULL REFERENCES private.officers(id),manufacturer text NOT NULL,model text NOT NULL,caliber text NOT NULL,serial text NOT NULL,active boolean NOT NULL DEFAULT true,created_at text NOT NULL,created_by text NOT NULL,replacement_reason text NOT NULL DEFAULT '');
CREATE INDEX fixed_pistols_officer_history ON private.fixed_pistols(officer_id,created_at);
CREATE UNIQUE INDEX fixed_pistols_current ON private.fixed_pistols(officer_id) WHERE active;
CREATE UNIQUE INDEX fixed_pistols_unique_active_serial ON private.fixed_pistols(upper(regexp_replace(manufacturer||':'||serial,'[^a-zA-Z0-9:]','','g'))) WHERE active;
CREATE TABLE private.load_returns(id text PRIMARY KEY,load_id text NOT NULL REFERENCES private.loads(id),item_id text NOT NULL,quantity integer NOT NULL CHECK(quantity>=0),state text NOT NULL CHECK(state IN('devolvido','avaria','nao_devolvido','transferido')),notes text NOT NULL DEFAULT '',actor text NOT NULL,created_at text NOT NULL);
CREATE INDEX load_returns_history ON private.load_returns(load_id,created_at);
CREATE TABLE private.service_attachments(id text PRIMARY KEY,service_id text NOT NULL REFERENCES private.services(id),phase text NOT NULL CHECK(phase IN('conferencia','individual','guarnicao','ocorrencia')),item_id text,path text NOT NULL UNIQUE,original_name text NOT NULL,content_type text NOT NULL,bytes integer NOT NULL CHECK(bytes>0 AND bytes<=8388608),sha256 text NOT NULL,actor text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,created_at text NOT NULL);
CREATE INDEX service_attachments_history ON private.service_attachments(service_id,created_at);

-- Legacy records are retained. The latest record per DPM needs explicit closure;
-- older records are marked as imported history without inventing a return or end time.
INSERT INTO private.services(id,city,platoon_id,platoon_name,unit_name,municipality_name,municipality_uf,commander_actor,commander_officer_id,commander_name,crew,started_at,duration_hours,planned_end,status,conference_at,created_at,legacy,closing)
 SELECT c.id,c.city,u.platoon_id,p.name,u.label,municipality.name,municipality.uf,c.actor,c.officer_id,c.actor_name,c.crew::jsonb,c.created_at,24,to_char(c.created_at::timestamptz+interval '24 hours','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 CASE WHEN c.deleted_at IS NULL AND c.id=(SELECT x.id FROM private.checks x WHERE x.city=c.city AND x.deleted_at IS NULL ORDER BY x.created_at DESC,x.id DESC LIMIT 1) THEN 'aguardando_encerramento' ELSE 'encerrado' END,c.finalized_at,c.created_at,true,'{"imported":true,"notice":"Registro anterior à implantação do encerramento formal; nenhuma devolução foi presumida."}'::jsonb
 FROM private.checks c JOIN private.cities u ON u.name=c.city JOIN private.platoons p ON p.id=u.platoon_id JOIN private.municipalities municipality ON municipality.id=u.municipality_id;
INSERT INTO private.service_members(service_id,officer_id,name,registration,rank,status,load_id,started_at,duration_hours,planned_end)
 SELECT s.id,o.id,o.name,o.registration,o.rank,CASE WHEN s.status='encerrado' THEN 'encerrado' ELSE 'ativo' END,(SELECT l.id FROM private.loads l WHERE l.check_id=s.id AND l.officer_id=o.id LIMIT 1),s.started_at,24,s.planned_end FROM private.services s JOIN private.officers o ON s.crew ? o.id;

CREATE FUNCTION private.service_command_allowed(who text,sid text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
 SELECT EXISTS(SELECT 1 FROM private.services s WHERE s.id=sid AND s.status<>'encerrado' AND s.commander_actor=who AND private.scope_allowed(who,s.city,'operate'));
$$;
CREATE FUNCTION private.enforce_service_scope() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE who text; s private.services; own boolean; elevated boolean;
BEGIN
 who:=NULLIF(current_setting('app.actor_id',true),'');IF who IS NULL THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Históricos de serviço não podem ser apagados' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME IN('platoons','cities','municipalities') THEN
  IF NOT private.scope_allowed(who,NULL,'global') THEN RAISE EXCEPTION 'Somente gestor geral administra a estrutura' USING ERRCODE='42501'; END IF;
  IF TG_OP='UPDATE' AND (TG_TABLE_NAME='cities' AND NEW.name<>OLD.name) THEN RAISE EXCEPTION 'Identificação histórica da unidade é imutável' USING ERRCODE='42501'; END IF;
  RETURN NEW;
 END IF;
 IF TG_TABLE_NAME='fixed_pistols' THEN
  own:=EXISTS(SELECT 1 FROM private.principals p JOIN private.officers o ON o.id=p.officer_id WHERE p.id=who AND o.id=NEW.officer_id AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL);
  IF NOT own OR TG_OP='UPDATE' AND ((to_jsonb(NEW)-'active')<>(to_jsonb(OLD)-'active') OR NOT OLD.active OR NEW.active) THEN RAISE EXCEPTION 'Cadastro pessoal protegido e histórico imutável' USING ERRCODE='42501'; END IF;
  RETURN NEW;
 END IF;
 IF TG_TABLE_NAME='services' THEN
  IF TG_OP='INSERT' THEN IF NEW.commander_actor<>who OR NOT private.scope_allowed(who,NEW.city,'operate') THEN RAISE EXCEPTION 'Serviço fora do vínculo operacional' USING ERRCODE='42501'; END IF; RETURN NEW; END IF;
  s:=OLD;
  IF OLD.status='encerrado' OR (to_jsonb(NEW)-ARRAY['status','conference_at','ended_at','ended_by','closing'])<>(to_jsonb(OLD)-ARRAY['status','conference_at','ended_at','ended_by','closing']) THEN RAISE EXCEPTION 'Dados originais do serviço são imutáveis' USING ERRCODE='42501'; END IF;
 ELSE SELECT * INTO s FROM private.services WHERE id=NEW.service_id;
 END IF;
 elevated:=private.scope_allowed(who,NULL,'global') OR EXISTS(SELECT 1 FROM private.officers o JOIN private.principals p ON p.officer_id=o.id WHERE p.id=who AND o.role IN('comandante','comando') AND o.home_platoon=s.platoon_id AND private.scope_allowed(who,s.city,'read'));
 own:=EXISTS(SELECT 1 FROM private.service_members m JOIN private.principals p ON p.officer_id=m.officer_id WHERE m.service_id=s.id AND p.id=who);
 IF TG_TABLE_NAME='service_members' THEN
  IF TG_OP='INSERT' THEN own:=private.service_command_allowed(who,s.id);
  ELSE own:=EXISTS(SELECT 1 FROM private.principals p WHERE p.id=who AND p.officer_id=NEW.officer_id) OR elevated;
   IF OLD.status='encerrado' OR (to_jsonb(NEW)-ARRAY['status','load_id','started_at','duration_hours','planned_end','ended_at','ended_by','closing'])<>(to_jsonb(OLD)-ARRAY['status','load_id','started_at','duration_hours','planned_end','ended_at','ended_by','closing']) THEN RAISE EXCEPTION 'Encerramento individual imutável' USING ERRCODE='42501'; END IF;
  END IF;
 ELSIF TG_TABLE_NAME IN('service_events','service_attachments') THEN
  IF TG_OP<>'INSERT' OR NEW.actor<>who THEN RAISE EXCEPTION 'Histórico e anexos imutáveis' USING ERRCODE='42501'; END IF;
  own:=own OR private.service_command_allowed(who,s.id) OR elevated;
 ELSIF TG_TABLE_NAME='services' THEN own:=private.service_command_allowed(who,s.id) OR elevated;
 END IF;
 IF NOT COALESCE(own,false) THEN RAISE EXCEPTION 'Operação de serviço não autorizada' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END; $$;
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['municipalities','services','service_members','service_events','fixed_pistols','load_returns','service_attachments'] LOOP EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated',t);END LOOP; FOREACH t IN ARRAY ARRAY['platoons','cities','municipalities','services','service_members','service_events','fixed_pistols','service_attachments'] LOOP EXECUTE format('CREATE TRIGGER enforce_service_scope BEFORE INSERT OR UPDATE OR DELETE ON private.%I FOR EACH ROW EXECUTE FUNCTION private.enforce_service_scope()',t);END LOOP; END $$;
CREATE FUNCTION private.guard_load_item_balance() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE who text;l private.loads;
BEGIN
 who:=NULLIF(current_setting('app.actor_id',true),'');IF who IS NULL THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Histórico de cautela imutável' USING ERRCODE='42501'; END IF;
 SELECT * INTO l FROM private.loads WHERE id=NEW.load_id;
 IF NOT (l.actor=who OR private.scope_allowed(who,l.city,'movements')) THEN RAISE EXCEPTION 'Cautela de outro policial' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='load_returns' THEN IF TG_OP<>'INSERT' OR NEW.actor<>who THEN RAISE EXCEPTION 'Histórico de devolução imutável' USING ERRCODE='42501'; END IF;
 ELSIF TG_OP='UPDATE' AND ((to_jsonb(NEW)-ARRAY['returned_quantity','transferred_quantity'])<>(to_jsonb(OLD)-ARRAY['returned_quantity','transferred_quantity']) OR NEW.returned_quantity<OLD.returned_quantity OR NEW.transferred_quantity<OLD.transferred_quantity) THEN RAISE EXCEPTION 'Reserva original imutável' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER guard_load_balance BEFORE INSERT OR UPDATE OR DELETE ON private.load_items FOR EACH ROW EXECUTE FUNCTION private.guard_load_item_balance();
CREATE TRIGGER guard_load_return_history BEFORE INSERT OR UPDATE OR DELETE ON private.load_returns FOR EACH ROW EXECUTE FUNCTION private.guard_load_item_balance();
REVOKE ALL ON FUNCTION private.service_command_allowed(text,text),private.enforce_service_scope(),private.guard_load_item_balance() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.vehicle_duty_allowed(who text,place text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
 SELECT private.scope_allowed(who,place,'operate') AND EXISTS(SELECT 1 FROM private.services s JOIN private.checks c ON c.id=s.id JOIN private.principals p ON p.id=c.actor AND p.officer_id=c.officer_id JOIN private.officers o ON o.id=c.officer_id WHERE s.city=place AND s.status<>'encerrado' AND s.commander_actor=who AND c.actor=who AND c.deleted_at IS NULL AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL);
$$;
CREATE FUNCTION private.guard_load_history() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF NULLIF(current_setting('app.actor_id',true),'') IS NULL THEN IF TG_OP='DELETE' THEN RETURN OLD;ELSE RETURN NEW;END IF; END IF;
 IF TG_OP='DELETE' OR (to_jsonb(NEW)-ARRAY['status','returned_at','closing'])<>(to_jsonb(OLD)-ARRAY['status','returned_at','closing']) OR (OLD.closing IS NOT NULL AND NEW.closing IS DISTINCT FROM OLD.closing) THEN RAISE EXCEPTION 'Dados originais da cautela e do encerramento são imutáveis' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER guard_load_history BEFORE UPDATE OR DELETE ON private.loads FOR EACH ROW EXECUTE FUNCTION private.guard_load_history();
REVOKE ALL ON FUNCTION private.guard_load_history() FROM PUBLIC,anon,authenticated;
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
 IF cap='operate' THEN RETURN EXISTS(SELECT 1 FROM private.officer_platoons m WHERE m.officer_id=o.id AND m.platoon_id=p AND m.active=1);END IF;
 IF p IS DISTINCT FROM o.home_platoon THEN RETURN false;END IF;
 RETURN o.role IN('comando','comandante','administrador') OR (o.role='subcomandante' AND COALESCE((o.permissions->>cap)::boolean,false));
END; $$;
