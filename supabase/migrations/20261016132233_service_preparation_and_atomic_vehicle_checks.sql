-- Drafts retain their IDs, attachments and original creation times; confirmed histories are untouched.
ALTER TABLE private.services DROP CONSTRAINT services_status_check;
ALTER TABLE private.services ADD CONSTRAINT services_status_check CHECK(status IN('preparacao','ativo','aguardando_encerramento','encerrado'));
WITH changed AS (
 UPDATE private.services s SET status='preparacao' FROM private.checks c WHERE c.id=s.id AND c.status='rascunho' AND NOT s.legacy AND s.conference_at IS NULL AND s.status IN('ativo','aguardando_encerramento') AND NOT EXISTS(SELECT 1 FROM private.loads l WHERE l.check_id=s.id) AND NOT EXISTS(SELECT 1 FROM private.service_members m WHERE m.service_id=s.id AND m.status='encerrado') RETURNING s.id
)
INSERT INTO private.service_events(id,service_id,kind,actor,actor_name,actor_registration,created_at,payload)
SELECT gen_random_uuid()::text,id,'preparacao_reclassificada','sistema','Atualização da plataforma','',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'{"reason":"Rascunho preservado; ativação somente após a finalização da conferência."}'::jsonb FROM changed;
UPDATE private.service_members m SET started_at=NULL FROM private.services s WHERE s.id=m.service_id AND s.status='preparacao' AND m.status='ativo';
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
  IF OLD.status='encerrado' OR (to_jsonb(NEW)-ARRAY['status','conference_at','ended_at','ended_by','closing']-CASE WHEN OLD.status='preparacao' AND NEW.status='ativo' AND NEW.started_at=NEW.conference_at THEN 'started_at' ELSE '' END)<>(to_jsonb(OLD)-ARRAY['status','conference_at','ended_at','ended_by','closing']-CASE WHEN OLD.status='preparacao' AND NEW.status='ativo' AND NEW.started_at=NEW.conference_at THEN 'started_at' ELSE '' END) THEN RAISE EXCEPTION 'Dados originais do serviço são imutáveis' USING ERRCODE='42501'; END IF;
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


CREATE FUNCTION private.guard_service_activation() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE c private.checks;
BEGIN
 IF NEW.legacy THEN RETURN NEW;END IF;
 SELECT * INTO c FROM private.checks WHERE id=NEW.id;
 IF NEW.status='preparacao' AND (c.status IS DISTINCT FROM 'rascunho' OR NEW.conference_at IS NOT NULL) THEN RAISE EXCEPTION 'Preparação exige conferência em rascunho' USING ERRCODE='23514';END IF;
 IF NEW.status IN('ativo','aguardando_encerramento') AND (c.status IS DISTINCT FROM 'finalizada' OR c.deleted_at IS NOT NULL OR NEW.conference_at IS NULL) THEN RAISE EXCEPTION 'Serviço somente pode ficar ativo após a finalização da conferência' USING ERRCODE='23514';END IF;
 IF TG_OP='UPDATE' AND OLD.status='preparacao' AND NEW.status='ativo' AND (NEW.started_at IS DISTINCT FROM NEW.conference_at OR NEW.conference_at IS DISTINCT FROM c.finalized_at OR abs(extract(epoch FROM (NEW.started_at::timestamptz-clock_timestamp())))>300) THEN RAISE EXCEPTION 'Ativação exige o horário real da finalização' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_service_activation BEFORE INSERT OR UPDATE ON private.services FOR EACH ROW EXECUTE FUNCTION private.guard_service_activation();
REVOKE ALL ON FUNCTION private.guard_service_activation() FROM PUBLIC,anon,authenticated;

-- Preparing a conference does not authorize custody entries/exits or confirmed vehicle events.
CREATE OR REPLACE FUNCTION private.vehicle_duty_allowed(who text,place text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
 SELECT private.scope_allowed(who,place,'operate') AND EXISTS(
  SELECT 1 FROM private.checks c JOIN private.services s ON s.id=c.id JOIN private.principals p ON p.id=c.actor AND p.officer_id=c.officer_id JOIN private.officers o ON o.id=c.officer_id
  WHERE c.city=place AND c.actor=who AND c.status='finalizada' AND c.deleted_at IS NULL AND s.status IN('ativo','aguardando_encerramento') AND s.conference_at IS NOT NULL AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL
 );
$$;
CREATE FUNCTION private.guard_confirmed_vehicle_check() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
BEGIN
 IF NEW.kind='conferencia' AND NULLIF(current_setting('app.actor_id',true),'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.checks c JOIN private.services s ON s.id=c.id WHERE c.id=NEW.check_id AND c.status='finalizada' AND c.deleted_at IS NULL AND s.status IN('ativo','aguardando_encerramento') AND s.conference_at IS NOT NULL AND c.actor=NEW.actor) THEN RAISE EXCEPTION 'Conferência de veículo exige finalização do serviço' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END;$$;
CREATE TRIGGER guard_confirmed_vehicle_check BEFORE INSERT ON private.vehicle_events FOR EACH ROW EXECUTE FUNCTION private.guard_confirmed_vehicle_check();
REVOKE ALL ON FUNCTION private.guard_confirmed_vehicle_check() FROM PUBLIC,anon,authenticated;
