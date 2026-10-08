ALTER TABLE private.officers ADD COLUMN auth_user_id text;
CREATE UNIQUE INDEX officers_auth_identity ON private.officers(auth_user_id) WHERE auth_user_id IS NOT NULL;
ALTER TABLE private.checks ADD COLUMN service_day text NOT NULL DEFAULT '';
ALTER TABLE private.checks ADD COLUMN deleted_at text;
ALTER TABLE private.checks ADD COLUMN deleted_by text;
ALTER TABLE private.checks ADD COLUMN deletion_reason text;
UPDATE private.checks SET service_day=to_char(COALESCE(finalized_at,created_at)::timestamptz AT TIME ZONE 'America/Sao_Paulo','YYYY-MM-DD');
CREATE UNIQUE INDEX checks_city_day ON private.checks(city,service_day) WHERE status='finalizada' AND deleted_at IS NULL;
CREATE UNIQUE INDEX checks_actor_day ON private.checks(actor,service_day) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX checks_officer_day ON private.checks(officer_id,service_day) WHERE deleted_at IS NULL;
CREATE TABLE private.loads (
 id text PRIMARY KEY,check_id text NOT NULL REFERENCES private.checks(id),actor text NOT NULL,
 officer_id text NOT NULL REFERENCES private.officers(id),officer_name text NOT NULL,city text NOT NULL,
 service_day text NOT NULL,entries text NOT NULL,notes text NOT NULL DEFAULT '',
 status text NOT NULL CHECK(status IN ('ativa','devolvida')),created_at text NOT NULL,returned_at text,
 UNIQUE(actor,service_day),UNIQUE(officer_id,service_day)
);
CREATE TABLE private.load_items (
 load_id text NOT NULL REFERENCES private.loads(id),item_id text NOT NULL,
 quantity integer NOT NULL CHECK(quantity>0),PRIMARY KEY(load_id,item_id)
);
CREATE INDEX load_items_stock ON private.load_items(item_id,load_id);
CREATE INDEX loads_check ON private.loads(check_id);
CREATE INDEX loads_active ON private.loads(id) WHERE status='ativa';
ALTER TABLE private.loads ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.load_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.loads,private.load_items FROM PUBLIC,anon,authenticated;
