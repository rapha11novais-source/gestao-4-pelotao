-- Extend the existing versioned pistol records; no historical values are backfilled.
ALTER TABLE private.fixed_pistols ADD COLUMN model_code text CHECK(model_code IN('PT100','GLOCK','PT840'));
ALTER TABLE private.fixed_pistols ADD COLUMN ammunition integer CHECK(ammunition>=0 AND ammunition<=1000000);
ALTER TABLE private.fixed_pistols ADD COLUMN ballistic_plate text;
ALTER TABLE private.fixed_pistols ADD COLUMN profile_notes text;
ALTER TABLE private.fixed_pistols ADD COLUMN created_by_name text;
ALTER TABLE private.fixed_pistols ADD COLUMN created_by_registration text;
ALTER TABLE private.fixed_pistols ADD CONSTRAINT complete_fixed_load CHECK(model_code IS NULL OR ammunition IS NOT NULL AND ballistic_plate IS NOT NULL AND length(trim(ballistic_plate))>0);
ALTER TABLE private.service_members ADD COLUMN fixed_load_confirmation jsonb;
CREATE FUNCTION private.fixed_load_authorized(who text,target text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
 SELECT EXISTS(SELECT 1 FROM private.officers o WHERE o.id=target AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL AND (
 private.scope_allowed(who,NULL,'global') OR private.scope_allowed(who,o.city,'officers') OR EXISTS(SELECT 1 FROM private.principals p WHERE p.id=who AND p.officer_id=o.id)
 OR EXISTS(SELECT 1 FROM private.services s JOIN private.service_members m ON m.service_id=s.id WHERE s.id=current_setting('app.fixed_load_service_id',true) AND s.status<>'encerrado' AND m.officer_id=o.id AND m.status='ativo' AND private.service_command_allowed(who,s.id))));
$$;
REVOKE ALL ON FUNCTION private.fixed_load_authorized(text,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION private.enforce_service_scope() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
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
  own:=private.fixed_load_authorized(who,NEW.officer_id);
  IF TG_OP='INSERT' AND NEW.created_by<>who THEN RAISE EXCEPTION 'Responsável pelo cadastro inválido' USING ERRCODE='42501'; END IF;
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
  ELSE own:=(current_setting('app.fixed_load_service_id',true)=s.id AND private.fixed_load_authorized(who,NEW.officer_id) AND (to_jsonb(NEW)-'fixed_load_confirmation')=(to_jsonb(OLD)-'fixed_load_confirmation')) OR EXISTS(SELECT 1 FROM private.principals p WHERE p.id=who AND p.officer_id=NEW.officer_id) OR elevated OR (private.service_closure_allowed(who,s.id) AND NEW.status='encerrado' AND (to_jsonb(NEW)-ARRAY['status','ended_at','ended_by','closing'])=(to_jsonb(OLD)-ARRAY['status','ended_at','ended_by','closing']));
   IF OLD.status='encerrado' OR (to_jsonb(NEW)-ARRAY['status','load_id','started_at','duration_hours','planned_end','ended_at','ended_by','closing','fixed_load_confirmation'])<>(to_jsonb(OLD)-ARRAY['status','load_id','started_at','duration_hours','planned_end','ended_at','ended_by','closing','fixed_load_confirmation']) THEN RAISE EXCEPTION 'Encerramento individual imutável' USING ERRCODE='42501'; END IF;
  END IF;
 ELSIF TG_TABLE_NAME IN('service_events','service_attachments') THEN
  IF TG_OP<>'INSERT' OR NEW.actor<>who THEN RAISE EXCEPTION 'Histórico e anexos imutáveis' USING ERRCODE='42501'; END IF;
  own:=own OR private.service_command_allowed(who,s.id) OR elevated;
 ELSIF TG_TABLE_NAME='services' THEN own:=private.service_command_allowed(who,s.id) OR elevated;
 END IF;
 IF NOT COALESCE(own,false) THEN RAISE EXCEPTION 'Operação de serviço não autorizada' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END; $$;

CREATE FUNCTION private.guard_fixed_load_confirmation() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF OLD.fixed_load_confirmation IS NOT NULL AND NEW.fixed_load_confirmation IS DISTINCT FROM OLD.fixed_load_confirmation THEN RAISE EXCEPTION 'Confirmação original de carga fixa é imutável' USING ERRCODE='42501';END IF;
 IF NEW.fixed_load_confirmation IS DISTINCT FROM OLD.fixed_load_confirmation AND NULLIF(current_setting('app.actor_id',true),'') IS NOT NULL AND NOT (private.scope_allowed(current_setting('app.actor_id',true),(SELECT city FROM private.services WHERE id=NEW.service_id),'operate') OR private.scope_allowed(current_setting('app.actor_id',true),(SELECT city FROM private.services WHERE id=NEW.service_id),'read')) THEN RAISE EXCEPTION 'Confirmação fora do vínculo autorizado' USING ERRCODE='42501';END IF;
 IF NEW.fixed_load_confirmation IS DISTINCT FROM OLD.fixed_load_confirmation AND (OLD.status='encerrado' OR NEW.fixed_load_confirmation->>'officer_id' IS DISTINCT FROM NEW.officer_id OR NEW.fixed_load_confirmation->>'service_id' IS DISTINCT FROM NEW.service_id) THEN RAISE EXCEPTION 'Confirmação fora do serviço ou policial' USING ERRCODE='42501';END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_fixed_load_confirmation BEFORE UPDATE ON private.service_members FOR EACH ROW EXECUTE FUNCTION private.guard_fixed_load_confirmation();
CREATE UNIQUE INDEX fixed_load_complete_serial ON private.fixed_pistols(upper(regexp_replace(serial,'[^a-zA-Z0-9]','','g'))) WHERE active AND model_code IS NOT NULL;
CREATE UNIQUE INDEX fixed_load_complete_plate ON private.fixed_pistols(upper(regexp_replace(ballistic_plate,'[^a-zA-Z0-9]','','g'))) WHERE active AND model_code IS NOT NULL;
CREATE FUNCTION private.guard_fixed_load_identifications() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF NEW.active AND NEW.model_code IS NOT NULL AND EXISTS(SELECT 1 FROM private.fixed_pistols f WHERE f.active AND f.id<>NEW.id AND (upper(regexp_replace(f.serial,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(NEW.serial,'[^a-zA-Z0-9]','','g')) OR NEW.ballistic_plate IS NOT NULL AND upper(regexp_replace(f.ballistic_plate,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(NEW.ballistic_plate,'[^a-zA-Z0-9]','','g')))) THEN RAISE EXCEPTION 'Pistola ou placa já vinculada a outra carga fixa' USING ERRCODE='23514';END IF;
 IF NEW.model_code IS NOT NULL AND EXISTS(SELECT 1 FROM private.service_members m JOIN private.services s ON s.id=m.service_id WHERE m.officer_id<>NEW.officer_id AND m.status='ativo' AND s.status<>'encerrado' AND (upper(regexp_replace(m.fixed_load_confirmation->>'serial','[^a-zA-Z0-9]','','g'))=upper(regexp_replace(NEW.serial,'[^a-zA-Z0-9]','','g')) OR upper(regexp_replace(m.fixed_load_confirmation->>'ballistic_plate','[^a-zA-Z0-9]','','g'))=upper(regexp_replace(NEW.ballistic_plate,'[^a-zA-Z0-9]','','g')))) THEN RAISE EXCEPTION 'Material confirmado em outro serviço ativo' USING ERRCODE='23514';END IF;
 IF NEW.model_code IS NOT NULL AND EXISTS(SELECT 1 FROM private.inventory i WHERE i.deleted_at IS NULL AND i.quantity>0 AND i.category IN('coletes','placas') AND upper(regexp_replace(i.serial,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(NEW.ballistic_plate,'[^a-zA-Z0-9]','','g'))) THEN RAISE EXCEPTION 'Placa pertence ao estoque do DPM; use cautela temporária' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_fixed_load_identifications BEFORE INSERT ON private.fixed_pistols FOR EACH ROW EXECUTE FUNCTION private.guard_fixed_load_identifications();
REVOKE ALL ON FUNCTION private.guard_fixed_load_confirmation(),private.guard_fixed_load_identifications() FROM PUBLIC,anon,authenticated;
