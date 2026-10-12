-- Additive migration: historical rows and original timestamps remain unchanged.
ALTER TABLE private.platoons ADD COLUMN ordinary_start_time time NOT NULL DEFAULT '09:00';
UPDATE private.platoons SET ordinary_start_time='10:00' WHERE id='p4';
ALTER TABLE private.services ADD COLUMN modality text CHECK(modality IN('ordinario','extraordinario'));
ALTER TABLE private.services ADD COLUMN planned_start text;
ALTER TABLE private.services ADD COLUMN reference_time text;
ALTER TABLE private.services ADD COLUMN timing_source text CHECK(timing_source='automatico');
ALTER TABLE private.services ALTER COLUMN duration_hours DROP NOT NULL;
DROP INDEX private.services_one_open_unit;
-- Unclassified historical open teams retain their transition lock; no modality is invented.
CREATE UNIQUE INDEX services_one_open_ordinary_unit ON private.services(city) WHERE status<>'encerrado' AND coalesce(modality,'ordinario')='ordinario';
CREATE INDEX services_modality_scope ON private.services(platoon_id,modality,status,created_at);
CREATE FUNCTION private.guard_service_modality() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF TG_OP='INSERT' AND NULLIF(current_setting('app.actor_id',true),'') IS NOT NULL THEN
  PERFORM 1 FROM private.cities WHERE name=NEW.city FOR UPDATE;
  IF NEW.modality IS NULL OR NEW.planned_start IS NULL OR NEW.timing_source IS DISTINCT FROM 'automatico' OR NEW.planned_end::timestamptz<=NEW.planned_start::timestamptz OR NEW.started_at IS DISTINCT FROM NEW.created_at OR abs(extract(epoch FROM (NEW.started_at::timestamptz-clock_timestamp())))>300 THEN RAISE EXCEPTION 'Modalidade, planejamento e início efetivo automático são obrigatórios' USING ERRCODE='23514'; END IF;
  IF NEW.modality='ordinario' AND (NEW.duration_hours IS NULL OR NEW.reference_time IS DISTINCT FROM (SELECT substring(ordinary_start_time::text,1,5) FROM private.platoons WHERE id=NEW.platoon_id) OR to_char(NEW.planned_start::timestamptz AT TIME ZONE 'America/Sao_Paulo','HH24:MI') IS DISTINCT FROM NEW.reference_time OR NEW.planned_end::timestamptz IS DISTINCT FROM NEW.planned_start::timestamptz+make_interval(hours=>NEW.duration_hours)) THEN RAISE EXCEPTION 'Referência oficial ordinária inválida' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_service_modality BEFORE INSERT ON private.services FOR EACH ROW EXECUTE FUNCTION private.guard_service_modality();
REVOKE ALL ON FUNCTION private.guard_service_modality() FROM PUBLIC,anon,authenticated;
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
 RETURN o.role IN('comando','comandante','administrador') OR (o.role='subcomandante' AND COALESCE((o.permissions->>cap)::boolean,false));
END; $$;

CREATE FUNCTION private.guard_shared_service_stock() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE i private.inventory; used bigint;
BEGIN
 SELECT * INTO i FROM private.inventory WHERE id=NEW.item_id FOR UPDATE;
 SELECT coalesce(sum(li.quantity-li.returned_quantity-li.transferred_quantity),0) INTO used FROM private.load_items li JOIN private.loads l ON l.id=li.load_id WHERE li.item_id=NEW.item_id AND l.status='ativa';
 used:=used+coalesce((SELECT sum(m.quantity) FROM private.movements m WHERE (m.status='aguardando' AND m.item_id=i.id) OR (m.status='recebida' AND (i.id='lote-'||m.id OR (m.item_id=i.id AND NOT EXISTS(SELECT 1 FROM private.inventory x WHERE x.id='lote-'||m.id))))),0);
 IF i.id IS NULL OR used+NEW.quantity>i.quantity OR i.serial<>'' AND used+NEW.quantity>1 THEN RAISE EXCEPTION 'Material já reservado ou quantidade disponível insuficiente' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_shared_service_stock BEFORE INSERT ON private.load_items FOR EACH ROW EXECUTE FUNCTION private.guard_shared_service_stock();
REVOKE ALL ON FUNCTION private.guard_shared_service_stock() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.guard_fixed_pistol_inventory() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM private.inventory i WHERE i.category='armas' AND i.deleted_at IS NULL AND i.quantity>0 AND upper(regexp_replace(i.serial,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(NEW.serial,'[^a-zA-Z0-9]','','g'))) THEN RAISE EXCEPTION 'Identificação pertence ao estoque patrimonial; use cautela do acervo' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_fixed_pistol_inventory BEFORE INSERT ON private.fixed_pistols FOR EACH ROW EXECUTE FUNCTION private.guard_fixed_pistol_inventory();
REVOKE ALL ON FUNCTION private.guard_fixed_pistol_inventory() FROM PUBLIC,anon,authenticated;
