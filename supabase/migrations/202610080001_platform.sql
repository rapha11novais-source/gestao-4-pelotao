CREATE SCHEMA IF NOT EXISTS private;
SET search_path=private,public;
CREATE TABLE "alerts" (
	"id" text PRIMARY KEY NOT NULL,
	"check_id" text,
	"item_id" text,
	"city" text NOT NULL,
	"title" text NOT NULL,
	"detail" text NOT NULL,
	"status" text NOT NULL,
	"created_at" text NOT NULL,
	"resolved_at" text,
	"resolution" text,
	"resolved_by" text
);

CREATE INDEX "alerts_status" ON "alerts" ("status");
CREATE TABLE "audit" (
	"id" text PRIMARY KEY NOT NULL,
	"actor" text NOT NULL,
	"actor_name" text NOT NULL,
	"action" text NOT NULL,
	"entity" text NOT NULL,
	"before" text,
	"after" text,
	"created_at" text NOT NULL
);

CREATE INDEX "audit_date" ON "audit" ("created_at");
CREATE TABLE "categories" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"mode" text NOT NULL
);

CREATE TABLE "checks" (
	"id" text PRIMARY KEY NOT NULL,
	"city" text NOT NULL,
	"actor" text NOT NULL,
	"officer_id" text,
	"actor_name" text NOT NULL,
	"crew" text NOT NULL,
	"entries" text NOT NULL,
	"notes" text NOT NULL,
	"status" text NOT NULL,
	"created_at" text NOT NULL,
	"updated_at" text NOT NULL,
	"finalized_at" text
);

CREATE INDEX "checks_actor" ON "checks" ("actor");
CREATE INDEX "checks_city_date" ON "checks" ("city","finalized_at");
CREATE TABLE "operation_guards" (
	"id" text PRIMARY KEY NOT NULL,
	"ok" integer NOT NULL,
	CONSTRAINT "operation_valid" CHECK("ok" = 1)
);

CREATE TABLE "inventory" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"category" text NOT NULL,
	"serial" text,
	"manufacturer" text,
	"model" text,
	"caliber" text,
	"city" text NOT NULL,
	"location" text NOT NULL,
	"quantity" integer NOT NULL,
	"condition" text NOT NULL,
	"notes" text DEFAULT '' NOT NULL,
	"source" text DEFAULT 'Cadastro administrativo' NOT NULL,
	"version" integer DEFAULT 1 NOT NULL
);

CREATE INDEX "inventory_location" ON "inventory" ("location");
CREATE UNIQUE INDEX "inventory_serial" ON "inventory" ("serial");
CREATE TABLE "movements" (
	"id" text PRIMARY KEY NOT NULL,
	"item_id" text NOT NULL,
	"item_name" text NOT NULL,
	"officer_id" text NOT NULL,
	"origin" text NOT NULL,
	"destination" text NOT NULL,
	"quantity" integer NOT NULL,
	"withdrawn_at" text NOT NULL,
	"due_at" text,
	"received_at" text,
	"returned_at" text,
	"status" text NOT NULL,
	"notes" text NOT NULL,
	"created_by" text NOT NULL
);

CREATE INDEX "movements_item_status" ON "movements" ("item_id","status");
CREATE TABLE "officers" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"rank" text NOT NULL,
	"callsign" text NOT NULL,
	"registration" text NOT NULL,
	"city" text NOT NULL,
	"role" text DEFAULT 'policial' NOT NULL,
	"email" text,
	"active" integer DEFAULT 1 NOT NULL,
	"validated" integer DEFAULT 0 NOT NULL
);

CREATE UNIQUE INDEX "officers_registration" ON "officers" ("registration");
CREATE UNIQUE INDEX "officers_email" ON "officers" ("email");
CREATE TABLE "principals" (
	"id" text PRIMARY KEY NOT NULL,
	"officer_id" text,
	"role" text NOT NULL,
	"email" text NOT NULL,
	"name" text NOT NULL
);

ALTER TABLE "checks" ADD "crew_labels" text DEFAULT '[]' NOT NULL;
CREATE TABLE private.settings (key text PRIMARY KEY, value text NOT NULL);
ALTER TABLE private.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.operation_guards ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.officers ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.principals ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON SCHEMA private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC,anon,authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA private REVOKE ALL ON TABLES FROM PUBLIC,anon,authenticated;
-- The dashboard's automatic RLS trigger is internal, never a client RPC.
DO $$ BEGIN
  IF to_regprocedure('public.rls_auto_enable()') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC,anon,authenticated;
  END IF;
END $$;
