-- Apply pgstac settings
-- These settings are configured via Helm values at pgstacBootstrap.settings.pgstacSettings

-- Queue settings
DELETE FROM pgstac.pgstac_settings WHERE name = 'queue_timeout';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('queue_timeout', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.queue_timeout }}');

DELETE FROM pgstac.pgstac_settings WHERE name = 'use_queue';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('use_queue', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.use_queue }}');

-- Collection extent management
DELETE FROM pgstac.pgstac_settings WHERE name = 'update_collection_extent';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('update_collection_extent', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.update_collection_extent }}');

-- Context settings
DELETE FROM pgstac.pgstac_settings WHERE name = 'context';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.context }}');

DELETE FROM pgstac.pgstac_settings WHERE name = 'context_estimated_count';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context_estimated_count', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.context_estimated_count }}');

DELETE FROM pgstac.pgstac_settings WHERE name = 'context_estimated_cost';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context_estimated_cost', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.context_estimated_cost }}');

DELETE FROM pgstac.pgstac_settings WHERE name = 'context_stats_ttl';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context_stats_ttl', '{{ .Values.pgstacBootstrap.settings.pgstacSettings.context_stats_ttl }}');
