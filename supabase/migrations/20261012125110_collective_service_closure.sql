CREATE FUNCTION private.service_closure_allowed(who text,sid text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
 SELECT sid IS NOT NULL AND current_setting('app.closing_service_id',true)=sid AND EXISTS(SELECT 1 FROM private.services v WHERE v.id=sid AND v.status<>'encerrado' AND (private.service_command_allowed(who,sid) OR private.scope_allowed(who,NULL,'global') OR EXISTS(SELECT 1 FROM private.officers o JOIN private.principals p ON p.officer_id=o.id WHERE p.id=who AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL AND o.role IN('comandante','comando') AND o.home_platoon=v.platoon_id AND private.scope_allowed(who,v.city,'read'))));
$$;
REVOKE ALL ON FUNCTION private.service_closure_allowed(text,text) FROM PUBLIC,anon,authenticated;

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
  ELSE own:=EXISTS(SELECT 1 FROM private.principals p WHERE p.id=who AND p.officer_id=NEW.officer_id) OR elevated OR (private.service_closure_allowed(who,s.id) AND NEW.status='encerrado' AND (to_jsonb(NEW)-ARRAY['status','ended_at','ended_by','closing'])=(to_jsonb(OLD)-ARRAY['status','ended_at','ended_by','closing']));
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
CREATE OR REPLACE FUNCTION private.guard_load_item_balance() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE who text;l private.loads;
BEGIN
 who:=NULLIF(current_setting('app.actor_id',true),'');IF who IS NULL THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Histórico de cautela imutável' USING ERRCODE='42501'; END IF;
 SELECT * INTO l FROM private.loads WHERE id=NEW.load_id;
 IF NOT (l.actor=who OR private.scope_allowed(who,l.city,'movements') OR private.service_closure_allowed(who,l.check_id)) THEN RAISE EXCEPTION 'Cautela de outro policial' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='load_returns' THEN IF TG_OP<>'INSERT' OR NEW.actor<>who THEN RAISE EXCEPTION 'Histórico de devolução imutável' USING ERRCODE='42501'; END IF;
 ELSIF TG_OP='UPDATE' AND ((to_jsonb(NEW)-ARRAY['returned_quantity','transferred_quantity'])<>(to_jsonb(OLD)-ARRAY['returned_quantity','transferred_quantity']) OR NEW.returned_quantity<OLD.returned_quantity OR NEW.transferred_quantity<OLD.transferred_quantity) THEN RAISE EXCEPTION 'Reserva original imutável' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END; $$;
CREATE OR REPLACE FUNCTION private.enforce_operational_scope() RETURNS trigger
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
  ELSE allowed:=(OLD.actor=who OR private.scope_allowed(who,OLD.city,'movements') OR private.service_closure_allowed(who,OLD.check_id)); END IF;
 ELSIF TG_TABLE_NAME='movements' THEN
  IF TG_OP='DELETE' THEN place:=OLD.origin; cap:=OLD.destination; ELSE place:=NEW.origin; cap:=NEW.destination; END IF;
  allowed:=private.scope_allowed(who,place,'movements') AND private.scope_allowed(who,cap,'movements');
  IF TG_OP='UPDATE' AND NEW.status='devolvida' AND OLD.status='recebida' AND (to_jsonb(NEW)-ARRAY['status','returned_at'])=(to_jsonb(OLD)-ARRAY['status','returned_at']) THEN allowed:=allowed OR EXISTS(SELECT 1 FROM private.services v JOIN private.service_members sm ON sm.service_id=v.id WHERE v.id=current_setting('app.closing_service_id',true) AND sm.officer_id=OLD.officer_id AND v.city=OLD.origin AND v.city=OLD.destination AND private.service_closure_allowed(who,v.id));END IF;
 ELSIF TG_TABLE_NAME='check_corrections' THEN allowed:=TG_OP='INSERT' AND NEW.actor=who AND EXISTS(SELECT 1 FROM private.checks c WHERE c.id=NEW.check_id AND private.scope_allowed(who,c.city,'materials'));
 ELSIF TG_TABLE_NAME='audit' THEN allowed:=TG_OP='INSERT' AND NEW.actor=who;
 END IF;
 IF NOT COALESCE(allowed,false) THEN RAISE EXCEPTION 'Operação fora das permissões do pelotão' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $$;
