-- NULL preserves the meaning of custody records created before this option.
ALTER TABLE private.vehicle_custodies ADD COLUMN tampering_reported boolean;
ALTER TABLE private.vehicle_custodies ADD CONSTRAINT vehicle_tampering_description
 CHECK(tampering_reported IS DISTINCT FROM true OR length(trim(difference_notes))>=5);
