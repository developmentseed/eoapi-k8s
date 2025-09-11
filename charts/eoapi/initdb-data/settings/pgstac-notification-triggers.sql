-- Create the notification function
CREATE OR REPLACE FUNCTION notify_items_change_func()
RETURNS TRIGGER AS $$
DECLARE

BEGIN
    PERFORM pg_notify('pgstac_items_change'::text, json_build_object(
            'operation', TG_OP,
            'items', jsonb_agg(
                jsonb_build_object(
                    'collection', data.collection,
                    'id', data.id
                )
            )
        )::text
        )
        FROM data
    ;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for INSERT operations
CREATE OR REPLACE TRIGGER notify_items_change_insert
    AFTER INSERT ON pgstac.items
    REFERENCING NEW TABLE AS data
    FOR EACH STATEMENT EXECUTE FUNCTION notify_items_change_func()
;

-- Create triggers for UPDATE operations
CREATE OR REPLACE TRIGGER notify_items_change_update
    AFTER UPDATE ON pgstac.items
    REFERENCING NEW TABLE AS data
    FOR EACH STATEMENT EXECUTE FUNCTION notify_items_change_func()
;

-- Create triggers for DELETE operations
CREATE OR REPLACE TRIGGER notify_items_change_delete
    AFTER DELETE ON pgstac.items
    REFERENCING OLD TABLE AS data
    FOR EACH STATEMENT EXECUTE FUNCTION notify_items_change_func()
;
