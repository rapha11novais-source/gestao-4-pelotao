ALTER TABLE private.checks ADD COLUMN vehicle_entries jsonb NOT NULL DEFAULT '[]';
CREATE TABLE private.vehicle_custodies(
 id text PRIMARY KEY, city text NOT NULL REFERENCES private.cities(name), type text NOT NULL,
 physical jsonb NOT NULL, documented jsonb NOT NULL DEFAULT '{}', registration_city text NOT NULL DEFAULT '',registration_uf text NOT NULL DEFAULT '',
 seized_at text NOT NULL,entered_at text NOT NULL,location text NOT NULL,reason text NOT NULL,report_number text NOT NULL DEFAULT '',notes text NOT NULL DEFAULT '',difference_notes text NOT NULL DEFAULT '',
 plate_key text NOT NULL DEFAULT '',chassis_key text NOT NULL DEFAULT '',engine_key text NOT NULL DEFAULT '',
 status text NOT NULL DEFAULT 'aguardando' CHECK(status IN('aguardando','encaminhado_detran','encaminhado_civil','liberado','outra_destinacao')),
 created_at text NOT NULL,created_by text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,crew jsonb NOT NULL,
 version integer NOT NULL DEFAULT 1,exit_at text,exit_data jsonb
);
CREATE INDEX vehicle_city_status ON private.vehicle_custodies(city,status,entered_at);
CREATE INDEX vehicle_active_plate ON private.vehicle_custodies(city,plate_key) WHERE status='aguardando' AND plate_key<>'';
CREATE INDEX vehicle_active_chassis ON private.vehicle_custodies(city,chassis_key) WHERE status='aguardando' AND chassis_key<>'';
CREATE INDEX vehicle_active_engine ON private.vehicle_custodies(city,engine_key) WHERE status='aguardando' AND engine_key<>'';
CREATE TABLE private.vehicle_events(
 id text PRIMARY KEY,vehicle_id text NOT NULL REFERENCES private.vehicle_custodies(id),check_id text REFERENCES private.checks(id),kind text NOT NULL,
 actor text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,created_at text NOT NULL,payload jsonb NOT NULL
);
CREATE INDEX vehicle_events_history ON private.vehicle_events(vehicle_id,created_at DESC,id);
CREATE INDEX vehicle_events_check ON private.vehicle_events(check_id,vehicle_id,created_at DESC) WHERE check_id IS NOT NULL;
CREATE TABLE private.vehicle_alerts(
 id text PRIMARY KEY,vehicle_id text NOT NULL REFERENCES private.vehicle_custodies(id),city text NOT NULL REFERENCES private.cities(name),check_id text REFERENCES private.checks(id),kind text NOT NULL,
 actor text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,created_at text NOT NULL,detail text NOT NULL,
 status text NOT NULL DEFAULT 'aberta' CHECK(status IN('aberta','resolvida')),seen_at text,seen_by text,seen_name text,resolved_at text,resolved_by text,resolved_name text,resolution text
);
CREATE UNIQUE INDEX vehicle_active_check_alert ON private.vehicle_alerts(vehicle_id,check_id,kind) WHERE status='aberta' AND check_id IS NOT NULL;
CREATE UNIQUE INDEX vehicle_prolonged_once ON private.vehicle_alerts(vehicle_id,kind) WHERE kind='permanencia';
CREATE INDEX vehicle_alerts_scope ON private.vehicle_alerts(city,status,created_at DESC);
CREATE INDEX vehicle_alerts_check ON private.vehicle_alerts(check_id) WHERE check_id IS NOT NULL;
CREATE TABLE private.vehicle_authorizations(
 id text PRIMARY KEY,vehicle_id text NOT NULL REFERENCES private.vehicle_custodies(id),vehicle_version integer NOT NULL,reference text NOT NULL,reason text NOT NULL,
 actor text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,created_at text NOT NULL,revoked_at text,revoked_by text,used_at text
);
CREATE INDEX vehicle_authorizations_history ON private.vehicle_authorizations(vehicle_id,created_at DESC);
CREATE TABLE private.vehicle_attachments(
 id text PRIMARY KEY,vehicle_id text NOT NULL REFERENCES private.vehicle_custodies(id),check_id text REFERENCES private.checks(id),path text NOT NULL UNIQUE,phase text NOT NULL CHECK(phase IN('entrada','saida','geral')),
 original_name text NOT NULL,content_type text NOT NULL,bytes integer NOT NULL CHECK(bytes>0 AND bytes<=8388608),sha256 text NOT NULL,
 actor text NOT NULL,actor_name text NOT NULL,actor_registration text NOT NULL,created_at text NOT NULL
);
CREATE INDEX vehicle_attachments_history ON private.vehicle_attachments(vehicle_id,created_at);
CREATE INDEX vehicle_attachments_check ON private.vehicle_attachments(check_id) WHERE check_id IS NOT NULL;
CREATE TABLE private.vehicle_settings(city text PRIMARY KEY REFERENCES private.cities(name),max_days integer CHECK(max_days BETWEEN 1 AND 3650),updated_by text NOT NULL,updated_at text NOT NULL);

CREATE FUNCTION private.vehicle_command_allowed(who text,place text) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE o private.officers; p text;
BEGIN
 IF private.scope_allowed(who,NULL,'global') THEN RETURN true; END IF;
 SELECT x.* INTO o FROM private.officers x JOIN private.principals u ON u.officer_id=x.id WHERE u.id=who AND x.active=1 AND x.validated=1 AND x.deleted_at IS NULL;
 SELECT platoon_id INTO p FROM private.cities WHERE name=place;
 RETURN COALESCE(o.home_platoon=p AND o.role IN('comandante','comando'),false);
END; $$;
CREATE FUNCTION private.vehicle_duty_allowed(who text,place text) RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,private AS $$
 SELECT private.scope_allowed(who,place,'operate') AND EXISTS(
  SELECT 1 FROM (SELECT actor,officer_id,deleted_at FROM private.checks WHERE city=place ORDER BY created_at DESC,id DESC LIMIT 1) c
  JOIN private.principals p ON p.id=c.actor AND p.officer_id=c.officer_id JOIN private.officers o ON o.id=c.officer_id
  WHERE c.actor=who AND c.deleted_at IS NULL AND o.active=1 AND o.validated=1 AND o.deleted_at IS NULL
 );
$$;
CREATE FUNCTION private.enforce_vehicle_scope() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE who text;place text;allowed boolean:=false;
BEGIN
 who:=NULLIF(current_setting('app.actor_id',true),'');
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Histórico de custódia não pode ser apagado' USING ERRCODE='42501'; END IF;
 IF who IS NULL THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='vehicle_custodies' THEN
  place:=NEW.city;
  IF TG_OP='INSERT' THEN allowed:=NEW.created_by=who AND NEW.status='aguardando' AND private.vehicle_duty_allowed(who,place);
  ELSE
   IF NEW.city<>OLD.city OR NEW.created_by<>OLD.created_by OR NEW.created_at<>OLD.created_at OR NEW.actor_name<>OLD.actor_name OR NEW.actor_registration<>OLD.actor_registration OR NEW.crew<>OLD.crew THEN RAISE EXCEPTION 'Origem da custódia imutável' USING ERRCODE='42501'; END IF;
   IF OLD.status<>'aguardando' AND (NEW.status<>OLD.status OR NEW.exit_at IS DISTINCT FROM OLD.exit_at OR NEW.exit_data IS DISTINCT FROM OLD.exit_data) THEN RAISE EXCEPTION 'Saída formal imutável' USING ERRCODE='42501'; END IF;
   IF OLD.status='aguardando' AND NEW.status<>OLD.status THEN allowed:=private.vehicle_duty_allowed(who,place) AND NEW.exit_at IS NOT NULL AND NEW.exit_data IS NOT NULL;
   ELSE allowed:=private.scope_allowed(who,place,'movements'); END IF;
  END IF;
 ELSIF TG_TABLE_NAME='vehicle_settings' THEN allowed:=private.vehicle_command_allowed(who,NEW.city);
 ELSE
  SELECT city INTO place FROM private.vehicle_custodies WHERE id=NEW.vehicle_id;
  IF TG_TABLE_NAME='vehicle_events' THEN
   IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Eventos de custódia imutáveis' USING ERRCODE='42501'; END IF;
   allowed:=NEW.actor=who AND (private.vehicle_duty_allowed(who,place) OR private.scope_allowed(who,place,'movements') OR private.scope_allowed(who,place,'read'));
  ELSIF TG_TABLE_NAME='vehicle_attachments' THEN
   IF TG_OP<>'INSERT' THEN RAISE EXCEPTION 'Anexos de custódia imutáveis' USING ERRCODE='42501'; END IF;
   allowed:=NEW.actor=who AND (private.vehicle_duty_allowed(who,place) OR private.scope_allowed(who,place,'movements'));
  ELSIF TG_TABLE_NAME='vehicle_authorizations' THEN
   IF TG_OP='INSERT' THEN allowed:=NEW.actor=who AND private.vehicle_command_allowed(who,place);
   ELSE
    IF (to_jsonb(NEW)-ARRAY['revoked_at','revoked_by','used_at'])<>(to_jsonb(OLD)-ARRAY['revoked_at','revoked_by','used_at']) OR OLD.revoked_at IS NOT NULL OR OLD.used_at IS NOT NULL THEN RAISE EXCEPTION 'Autorização imutável' USING ERRCODE='42501'; END IF;
    allowed:=(NEW.revoked_at IS NOT NULL AND private.vehicle_command_allowed(who,place)) OR (NEW.used_at IS NOT NULL AND private.vehicle_duty_allowed(who,place));
   END IF;
  ELSIF TG_TABLE_NAME='vehicle_alerts' THEN
   IF TG_OP='INSERT' THEN allowed:=NEW.actor=who AND NEW.city=place AND (private.vehicle_duty_allowed(who,place) OR private.scope_allowed(who,place,'movements'));
   ELSE
    IF (to_jsonb(NEW)-ARRAY['status','seen_at','seen_by','seen_name','resolved_at','resolved_by','resolved_name','resolution'])<>(to_jsonb(OLD)-ARRAY['status','seen_at','seen_by','seen_name','resolved_at','resolved_by','resolved_name','resolution']) THEN RAISE EXCEPTION 'Origem do alerta imutável' USING ERRCODE='42501'; END IF;
    allowed:=private.vehicle_duty_allowed(who,place) OR private.scope_allowed(who,place,'read');
   END IF;
  END IF;
 END IF;
 IF NOT COALESCE(allowed,false) THEN RAISE EXCEPTION 'Operação fora das permissões de custódia' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END; $$;
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['vehicle_custodies','vehicle_events','vehicle_alerts','vehicle_authorizations','vehicle_attachments','vehicle_settings'] LOOP
 EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated',t);
 EXECUTE format('CREATE TRIGGER enforce_vehicle_scope BEFORE INSERT OR UPDATE OR DELETE ON private.%I FOR EACH ROW EXECUTE FUNCTION private.enforce_vehicle_scope()',t);
END LOOP; END $$;
CREATE FUNCTION private.refresh_vehicle_age_alerts() RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,private AS $$
DECLARE n integer;
BEGIN
 INSERT INTO private.vehicle_alerts(id,vehicle_id,city,kind,actor,actor_name,actor_registration,created_at,detail)
 SELECT gen_random_uuid()::text,v.id,v.city,'permanencia','sistema','Monitoramento automático','',to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'Permanência superior ao prazo de acompanhamento de '||s.max_days||' dia(s) configurado para o DPM. Entrada: '||v.entered_at
 FROM private.vehicle_custodies v JOIN private.vehicle_settings s ON s.city=v.city
 WHERE v.status='aguardando' AND s.max_days IS NOT NULL AND v.entered_at::timestamptz + make_interval(days=>s.max_days)<now()
 ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n;
END; $$;
REVOKE ALL ON FUNCTION private.vehicle_command_allowed(text,text),private.vehicle_duty_allowed(text,text),private.enforce_vehicle_scope(),private.refresh_vehicle_age_alerts() FROM PUBLIC,anon,authenticated;
