-- ============================================================
-- SKELLO SUPPORT — MODÈLE DE DONNÉES REPORTING
-- Auteur : Noé (Data Analyst Intern candidate)
-- Base source : Snowflake (tables CONVERSATIONS, CONVERSATION_PARTS)
-- Périmètre : Dashboard hebdomadaire de Lorette (équipe Support)
-- ============================================================

-- ============================================================
-- NOTES DE MODÉLISATION
-- ============================================================
-- 1. Les champs ASSIGNEE, AUTHOR, CONVERSATION_RATING, TAGS
--    sont stockés en JSON dans la source. On les parse à la couche
--    de staging pour exposer des colonnes typées en downstream.
--
-- 2. Le "périmètre équipe Support" est filtré sur les assignee_id
--    connus : Héloise (5217337), Justine (5391224),
--    Patrick (5440474), Raphael (5300290).
--    Les conversations assignées à d'autres IDs sont exclues
--    des métriques individuelles mais conservées pour le volume global.
--
-- 3. Les messages de bots sont exclus de toutes les métriques
--    (conformément à la consigne). Seuls les messages de type
--    author.type IN ('admin', 'user') sont comptabilisés.
--
-- 4. Le FRT (First Response Time) est calculé comme l'écart entre
--    le premier message client (user) et la première réponse admin
--    sur la même conversation, excluant les bots.
--
-- 5. La CSAT est extraite du champ CONVERSATION_RATING.rating
--    (note de 1 à 5). Le taux CSAT positif = % de notes >= 4.
--
-- 6. Questions que j'aurais posées à Lorette :
--    - La "semaine" est-elle calée sur lundi-dimanche ou glissante ?
--    - Y a-t-il une SLA officielle pour le FRT (5 min = la cible) ?
--    - Les conversations réouvertes doivent-elles être recomptées ?
--    - Faut-il suivre les conversations non assignées à l'équipe ?
--    - Le bot de premier niveau fait-il partie du process officiel
--      (impact sur le FRT perçu par le client) ?
-- ============================================================


-- ============================================================
-- LAYER 1 — STAGING (parsing JSON, typage, déduplication)
-- ============================================================

-- STG_CONVERSATIONS
-- Parse les champs JSON, nettoie les timestamps, expose l'assignee_id
CREATE OR REPLACE VIEW STG_CONVERSATIONS AS
SELECT
    ID                                                          AS conversation_id,
    TO_TIMESTAMP_NTZ(CREATED_AT)                                AS created_at,
    TO_TIMESTAMP_NTZ(UPDATED_AT)                                AS updated_at,
    STATE,
    OPEN,
    PRIORITY,
    READ,
    -- Parse JSON ASSIGNEE → id + type
    PARSE_JSON(ASSIGNEE):id::VARCHAR                            AS assignee_id,
    PARSE_JSON(ASSIGNEE):type::VARCHAR                          AS assignee_type,
    -- Parse JSON CONVERSATION_RATING
    PARSE_JSON(CONVERSATION_RATING):rating::INTEGER             AS csat_rating,
    PARSE_JSON(CONVERSATION_RATING):created_at::TIMESTAMP_NTZ  AS csat_rated_at,
    PARSE_JSON(CONVERSATION_RATING):teammate:id::VARCHAR        AS csat_teammate_id,
    -- Indique si la conversation a reçu une note CSAT
    CASE
        WHEN PARSE_JSON(CONVERSATION_RATING):rating IS NOT NULL THEN TRUE
        ELSE FALSE
    END                                                         AS has_csat,
    -- Tags : on garde le JSON brut, il sera dénormalisé dans une table dédiée
    TAGS                                                        AS tags_raw,
    SNOOZED_UNTIL
FROM CONVERSATIONS
-- Déduplication sur la clé primaire (protection contre re-loads ETL)
QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _SDC_EXTRACTED_AT DESC) = 1;


-- STG_CONVERSATION_PARTS
-- Parse AUTHOR, filtre les bots, expose part_group propre
CREATE OR REPLACE VIEW STG_CONVERSATION_PARTS AS
SELECT
    ID                                                          AS part_id,
    CONVERSATION_ID                                             AS conversation_id,
    PART_GROUP                                                  AS part_type,
    -- Parse JSON AUTHOR
    PARSE_JSON(AUTHOR):id::VARCHAR                              AS author_id,
    PARSE_JSON(AUTHOR):type::VARCHAR                            AS author_type,
    -- Parse ASSIGNED_TO (float dans source → varchar)
    ASSIGNED_TO::VARCHAR                                        AS assigned_to_id,
    TO_TIMESTAMP_NTZ(CREATED_AT)                                AS created_at,
    TO_TIMESTAMP_NTZ(UPDATED_AT)                                AS updated_at,
    BODY
FROM CONVERSATION_PARTS
-- Exclusion des bots (consigne explicite)
WHERE PARSE_JSON(AUTHOR):type::VARCHAR <> 'bot'
QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _SDC_EXTRACTED_AT DESC) = 1;


-- STG_CONVERSATION_TAGS (dénormalisation du tableau JSON TAGS)
-- Une ligne par tag par conversation
CREATE OR REPLACE VIEW STG_CONVERSATION_TAGS AS
SELECT
    c.ID                                                        AS conversation_id,
    t.value:id::VARCHAR                                         AS tag_id,
    t.value:name::VARCHAR                                       AS tag_name,
    TO_TIMESTAMP_NTZ(t.value:applied_at::VARCHAR)               AS applied_at
FROM CONVERSATIONS c,
LATERAL FLATTEN(input => TRY_PARSE_JSON(c.TAGS))               AS t
WHERE c.TAGS IS NOT NULL
  AND c.TAGS != '[]';


-- ============================================================
-- LAYER 2 — MARTS (tables agrégées pour le reporting)
-- ============================================================

-- -------------------------------------------------------
-- MART 1 : FACT_CONVERSATIONS
-- Grain : 1 ligne par conversation
-- Usage : volume, CSAT, durée, priorité, FRT
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_FACT_CONVERSATIONS AS

WITH

-- Première réponse admin (non-bot) par conversation
first_admin_response AS (
    SELECT
        conversation_id,
        MIN(created_at)     AS first_admin_response_at
    FROM STG_CONVERSATION_PARTS
    WHERE part_type = 'Message'
      AND author_type = 'admin'
    GROUP BY conversation_id
),

-- Premier message client par conversation
first_user_message AS (
    SELECT
        conversation_id,
        MIN(created_at)     AS first_user_message_at
    FROM STG_CONVERSATION_PARTS
    WHERE part_type = 'Message'
      AND author_type = 'user'
    GROUP BY conversation_id
),

-- Dernier événement par conversation (pour calculer la durée)
last_part AS (
    SELECT
        conversation_id,
        MAX(created_at)     AS last_part_at
    FROM STG_CONVERSATION_PARTS
    GROUP BY conversation_id
),

-- Comptage des messages par conversation
message_counts AS (
    SELECT
        conversation_id,
        COUNT_IF(author_type = 'user')  AS user_message_count,
        COUNT_IF(author_type = 'admin') AS admin_message_count,
        COUNT(*)                         AS total_message_count
    FROM STG_CONVERSATION_PARTS
    WHERE part_type = 'Message'
    GROUP BY conversation_id
)

SELECT
    c.conversation_id,
    c.created_at,
    c.updated_at,
    c.state,
    c.priority,
    c.assignee_id,
    c.assignee_type,

    -- CSAT
    c.csat_rating,
    c.has_csat,
    CASE
        WHEN c.csat_rating >= 4 THEN TRUE
        WHEN c.csat_rating IS NOT NULL THEN FALSE
        ELSE NULL
    END                                                         AS is_csat_positive,

    -- First Response Time (FRT) en secondes
    far.first_admin_response_at,
    fum.first_user_message_at,
    DATEDIFF(
        'second',
        fum.first_user_message_at,
        far.first_admin_response_at
    )                                                           AS frt_seconds,
    CASE
        WHEN DATEDIFF('second', fum.first_user_message_at, far.first_admin_response_at) <= 300
        THEN TRUE
        ELSE FALSE
    END                                                         AS is_frt_under_5min,

    -- Durée totale de la conversation (création → dernier événement)
    lp.last_part_at,
    DATEDIFF('minute', c.created_at, lp.last_part_at)          AS conversation_duration_min,

    -- Volumes de messages
    COALESCE(mc.user_message_count, 0)                          AS user_message_count,
    COALESCE(mc.admin_message_count, 0)                         AS admin_message_count,
    COALESCE(mc.total_message_count, 0)                         AS total_message_count,

    -- Dimensions temporelles (utiles pour les aggrégations hebdomadaires)
    DATE_TRUNC('week', c.created_at)                            AS week_start,
    DAYOFWEEK(c.created_at)                                     AS day_of_week_num,   -- 0=dim, 1=lun, ..., 6=sam
    DAYNAME(c.created_at)                                       AS day_of_week_name,
    HOUR(c.created_at)                                          AS hour_of_day,

    -- Flag : conversation traitée par l'équipe Support de Lorette
    CASE
        WHEN c.assignee_id IN ('5217337','5391224','5440474','5300290')
        THEN TRUE
        ELSE FALSE
    END                                                         AS is_support_team_conversation

FROM STG_CONVERSATIONS                  c
LEFT JOIN first_admin_response          far ON c.conversation_id = far.conversation_id
LEFT JOIN first_user_message            fum ON c.conversation_id = fum.conversation_id
LEFT JOIN last_part                     lp  ON c.conversation_id = lp.conversation_id
LEFT JOIN message_counts                mc  ON c.conversation_id = mc.conversation_id;


-- -------------------------------------------------------
-- MART 2 : DIM_SUPPORT_AGENTS
-- Grain : 1 ligne par agent Support
-- Usage : label lisible pour tous les rapports individuels
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_DIM_SUPPORT_AGENTS AS
SELECT * FROM (VALUES
    ('5217337', 'Héloise'),
    ('5391224', 'Justine'),
    ('5440474', 'Patrick'),
    ('5300290', 'Raphaël')
) AS t(agent_id, agent_name);


-- -------------------------------------------------------
-- MART 3 : AGG_WEEKLY_TEAM
-- Grain : 1 ligne par semaine
-- Usage : KPIs globaux hebdomadaires de l'équipe Support
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_AGG_WEEKLY_TEAM AS
SELECT
    week_start,
    COUNT(*)                                                    AS total_conversations,
    COUNT(CASE WHEN is_support_team_conversation THEN 1 END)    AS support_conversations,
    -- CSAT
    ROUND(
        100.0 * COUNT(CASE WHEN is_csat_positive = TRUE THEN 1 END)
              / NULLIF(COUNT(CASE WHEN has_csat THEN 1 END), 0),
        1
    )                                                           AS csat_positive_rate_pct,
    ROUND(AVG(CASE WHEN csat_rating IS NOT NULL THEN csat_rating END), 2)
                                                                AS avg_csat_score,
    COUNT(CASE WHEN has_csat THEN 1 END)                        AS rated_conversations,
    -- FRT
    ROUND(
        100.0 * COUNT(CASE WHEN is_frt_under_5min AND frt_seconds > 0 THEN 1 END)
              / NULLIF(COUNT(CASE WHEN frt_seconds > 0 THEN 1 END), 0),
        1
    )                                                           AS frt_under_5min_pct,
    ROUND(MEDIAN(CASE WHEN frt_seconds > 0 THEN frt_seconds / 60.0 END), 1)
                                                                AS median_frt_min,
    -- Durée de conversation
    ROUND(MEDIAN(conversation_duration_min), 1)                 AS median_duration_min,
    -- Messages
    SUM(user_message_count)                                     AS total_user_messages,
    SUM(admin_message_count)                                    AS total_admin_messages,
    -- Priorité
    COUNT(CASE WHEN priority = 'priority' THEN 1 END)           AS priority_conversations
FROM MART_FACT_CONVERSATIONS
GROUP BY week_start
ORDER BY week_start DESC;


-- -------------------------------------------------------
-- MART 4 : AGG_WEEKLY_AGENT
-- Grain : 1 ligne par (semaine, agent)
-- Usage : performance individuelle des membres de l'équipe
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_AGG_WEEKLY_AGENT AS
SELECT
    f.week_start,
    f.assignee_id                                               AS agent_id,
    a.agent_name,
    COUNT(*)                                                    AS conversations_handled,
    -- CSAT
    ROUND(
        100.0 * COUNT(CASE WHEN f.is_csat_positive = TRUE THEN 1 END)
              / NULLIF(COUNT(CASE WHEN f.has_csat THEN 1 END), 0),
        1
    )                                                           AS csat_positive_rate_pct,
    ROUND(AVG(CASE WHEN f.csat_rating IS NOT NULL THEN f.csat_rating END), 2)
                                                                AS avg_csat_score,
    COUNT(CASE WHEN f.has_csat THEN 1 END)                      AS rated_conversations,
    -- FRT
    ROUND(
        100.0 * COUNT(CASE WHEN f.is_frt_under_5min AND f.frt_seconds > 0 THEN 1 END)
              / NULLIF(COUNT(CASE WHEN f.frt_seconds > 0 THEN 1 END), 0),
        1
    )                                                           AS frt_under_5min_pct,
    ROUND(MEDIAN(CASE WHEN f.frt_seconds > 0 THEN f.frt_seconds / 60.0 END), 1)
                                                                AS median_frt_min,
    -- Durée & messages
    ROUND(MEDIAN(f.conversation_duration_min), 1)               AS median_duration_min,
    SUM(f.admin_message_count)                                  AS messages_sent,
    -- Priorité
    COUNT(CASE WHEN f.priority = 'priority' THEN 1 END)         AS priority_conversations
FROM MART_FACT_CONVERSATIONS            f
INNER JOIN MART_DIM_SUPPORT_AGENTS      a ON f.assignee_id = a.agent_id
WHERE f.is_support_team_conversation = TRUE
GROUP BY f.week_start, f.assignee_id, a.agent_name
ORDER BY f.week_start DESC, conversations_handled DESC;


-- -------------------------------------------------------
-- MART 5 : AGG_HOURLY_VOLUME
-- Grain : 1 ligne par (jour de semaine, heure)
-- Usage : heatmap de charge — "quand l'équipe est-elle la plus sollicitée ?"
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_AGG_HOURLY_VOLUME AS
SELECT
    day_of_week_num,
    day_of_week_name,
    hour_of_day,
    COUNT(*)                                                    AS conversation_count,
    ROUND(AVG(COUNT(*)) OVER (
        PARTITION BY day_of_week_num, hour_of_day
    ), 1)                                                       AS avg_per_slot
FROM MART_FACT_CONVERSATIONS
GROUP BY day_of_week_num, day_of_week_name, hour_of_day
ORDER BY day_of_week_num, hour_of_day;


-- -------------------------------------------------------
-- MART 6 : AGG_TAGS_WEEKLY
-- Grain : 1 ligne par (semaine, tag)
-- Usage : thèmes récurrents, priorisation des sujets
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_AGG_TAGS_WEEKLY AS
SELECT
    DATE_TRUNC('week', c.created_at)                            AS week_start,
    t.tag_name,
    COUNT(DISTINCT t.conversation_id)                           AS conversation_count
FROM STG_CONVERSATION_TAGS              t
INNER JOIN STG_CONVERSATIONS            c ON t.conversation_id = c.conversation_id
GROUP BY DATE_TRUNC('week', c.created_at), t.tag_name
ORDER BY week_start DESC, conversation_count DESC;


-- -------------------------------------------------------
-- MART 7 : AGG_CSAT_DISTRIBUTION
-- Grain : 1 ligne par (semaine, note CSAT)
-- Usage : distribution des notes pour détecter des dérives
-- -------------------------------------------------------
CREATE OR REPLACE TABLE MART_AGG_CSAT_DISTRIBUTION AS
SELECT
    week_start,
    csat_rating,
    COUNT(*)                                                    AS rating_count,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY week_start),
        1
    )                                                           AS rating_pct
FROM MART_FACT_CONVERSATIONS
WHERE csat_rating IS NOT NULL
GROUP BY week_start, csat_rating
ORDER BY week_start DESC, csat_rating;


-- ============================================================
-- EXEMPLE DE REQUÊTE REPORTING — KPIs semaine en cours
-- (à adapter en paramètre dans l'outil BI)
-- ============================================================

/*
SELECT
    t.week_start,
    t.support_conversations,
    t.csat_positive_rate_pct,
    t.avg_csat_score,
    t.frt_under_5min_pct,
    t.median_frt_min,
    t.median_duration_min,
    t.priority_conversations
FROM MART_AGG_WEEKLY_TEAM t
WHERE t.week_start = DATE_TRUNC('week', CURRENT_DATE)
ORDER BY t.week_start DESC;
*/
