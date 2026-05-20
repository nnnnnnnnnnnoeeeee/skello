-- Staging : table CONVERSATION_PARTS (source Intercom via ETL).
-- Responsabilités de cette couche :
--   - Parser le champ JSON AUTHOR (author_id, author_type)
--   - Normaliser les types
-- Toutes les parts sont conservées — le filtrage métier est fait en couche intermédiaire.
--
-- Note sur le schéma réel (vérifié sur le CSV source) :
--   La colonne PART_TYPE n'est PAS chargée par l'ETL.
--   Le champ équivalent disponible est PART_GROUP, dont les valeurs observées sont :
--     'Message'     → messages réels (user, admin, bot)
--     'Quick Reply' → boutons de réponse rapide (bot uniquement)
--     'Assignment'  → événements de réassignation
--     'Close'       → fermeture de conversation
--     'Snooze'      → mise en veille
--     ''            → parts système non catégorisées
--   La colonne BODY n'est pas non plus chargée par cet ETL.
--
-- Valeurs connues de author_type : 'admin', 'user', 'bot'.
-- Hypothèse : AUTHOR est stocké en JSON string : {"id": "5217337", "type": "admin"}.

CREATE OR REPLACE VIEW stg_conversation_parts AS

SELECT
    id::VARCHAR                                                                    AS part_id,
    conversation_id::VARCHAR                                                       AS conversation_id,
    part_group,                                                                    -- 'Message' | 'Assignment' | 'Close' | 'Quick Reply' | 'Snooze' | ''
    created_at::TIMESTAMP_NTZ                                                     AS created_at,
    assigned_to,

    -- Auteur : extraction depuis le JSON AUTHOR
    TRY_PARSE_JSON(author):id::VARCHAR                                            AS author_id,   -- VARCHAR car les IDs user sont des hex strings
    LOWER(
        COALESCE(
            TRY_PARSE_JSON(author):type::VARCHAR,
            'unknown'
        )
    )                                                                              AS author_type  -- 'admin' | 'user' | 'bot'

FROM conversation_parts
WHERE id IS NOT NULL
  AND conversation_id IS NOT NULL;
