INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types) VALUES('vehicle-custody','vehicle-custody',false,8388608,ARRAY['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf']) ON CONFLICT(id) DO NOTHING;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;
SELECT cron.schedule('vehicle-custody-age-alerts','0 * * * *','SELECT private.refresh_vehicle_age_alerts();');
