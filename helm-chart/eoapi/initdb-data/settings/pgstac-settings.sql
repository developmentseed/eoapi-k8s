-- Apply pgstac settings
DELETE FROM pgstac.pgstac_settings WHERE name = 'context';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context', 'auto');

DELETE FROM pgstac.pgstac_settings WHERE name = 'context_estimated_count';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context_estimated_count', '100000');

DELETE FROM pgstac.pgstac_settings WHERE name = 'context_estimated_cost';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context_estimated_cost', '100000');

DELETE FROM pgstac.pgstac_settings WHERE name = 'context_stats_ttl';
INSERT INTO pgstac.pgstac_settings (name, value) VALUES ('context_stats_ttl', '1 day');
