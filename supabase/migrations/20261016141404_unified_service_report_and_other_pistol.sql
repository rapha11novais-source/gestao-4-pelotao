-- Add a model choice without rewriting versioned profiles or service snapshots.
ALTER TABLE private.fixed_pistols DROP CONSTRAINT fixed_pistols_model_code_check;
ALTER TABLE private.fixed_pistols ADD CONSTRAINT fixed_pistols_model_code_check
 CHECK(model_code IN('PT100','GLOCK','PT840','OUTRA'));
ALTER TABLE private.fixed_pistols ADD CONSTRAINT fixed_pistols_other_model_check
 CHECK(model_code IS DISTINCT FROM 'OUTRA' OR model IS NOT NULL AND length(trim(model)) BETWEEN 1 AND 100);
CREATE INDEX vehicle_events_service_report ON private.vehicle_events(check_id,created_at,id) WHERE check_id IS NOT NULL;
