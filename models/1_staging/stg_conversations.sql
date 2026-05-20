-- Staging : table CONVERSATIONS (source Intercom via ETL).
-- Responsabilités de cette couche :
--   - Parser les champs JSON (CONVERSATION_RATING, ASSIGNEE)
--   - Normaliser les types (timestamps, booleans)
--   - Ajouter les helpers temporels (semaine ISO, jour, heure)
-- Aucun filtre métier ici : toutes les conversations sont conservées.
--
-- Hypothèses :
--   - Les timestamps source sont en UTC.
--   - CONVERSATION_RATING est stocké en JSON string : {"rating": 5, "remark": "..."}.
--     Si le type Snowflake est déjà VARIANT, supprimer les TRY_PARSE_JSON().
--   - ASSIGNEE est stocké en JSON string : {"id": 5217337, "type": "admin"}.
--     Si la colonne contient directement l'ID entier, simplifier le COALESCE.
--   - L'échelle CSAT est numérique de 1 à 5 (Intercom : 1=Awful … 5=Amazing).

CREATE OR REPLACE VIEW stg_conversations AS

SELECT
    id::VARCHAR                                                                    AS conversation_id,
    created_at::TIMESTAMP_NTZ                                                     AS created_at,
    updated_at::TIMESTAMP_NTZ                                                     AS updated_at,
    waiting_since::TIMESTAMP_NTZ                                                  AS waiting_since,
    state,                                                                         -- 'open' | 'closed' | 'snoozed'
    open::BOOLEAN                                                                  AS is_open,
    priority,                                                                      -- 'priority' | 'not_priority'
    read::BOOLEAN                                                                  AS is_read,

    -- CSAT : extraction depuis l'objet JSON CONVERSATION_RATING
    TRY_CAST(
        TRY_PARSE_JSON(conversation_rating):rating::VARCHAR AS INTEGER
    )                                                                              AS csat_rating,   -- 1-5 ou NULL si non noté
    TRY_PARSE_JSON(conversation_rating):remark::VARCHAR                           AS csat_remark,

    -- Assignee : on extrait l'ID numérique depuis le JSON ou directement si déjà un entier
    TRY_CAST(
        COALESCE(
            TRY_PARSE_JSON(assignee):id::VARCHAR,
            assignee::VARCHAR
        ) AS INTEGER
    )                                                                              AS assignee_id,

    -- Helpers temporels — ISO week (lundi = début de semaine)
    -- Formule : DAYOFWEEK retourne 0=Dim, 1=Lun … 6=Sam
    TO_DATE(
        DATEADD(day, -(MOD(DAYOFWEEK(created_at::TIMESTAMP_NTZ) + 6, 7)),
                created_at::TIMESTAMP_NTZ)
    )                                                                              AS week_start,        -- lundi de la semaine ISO

    DATE_PART('dayofweekiso', created_at::TIMESTAMP_NTZ)                         AS day_of_week_iso,   -- 1=Lun … 7=Dim
    HOUR(created_at::TIMESTAMP_NTZ)                                               AS hour_of_day        -- 0-23

FROM conversations
WHERE id IS NOT NULL;
