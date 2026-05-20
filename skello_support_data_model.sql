-- ============================================================
-- SKELLO SUPPORT — MODÈLE DE DONNÉES REPORTING
-- Auteur   : Noé (Data Analyst Intern)
-- Source   : Snowflake — tables CONVERSATIONS et CONVERSATION_PARTS
-- Objectif : Alimenter le dashboard hebdomadaire de Lorette
-- ============================================================
--
-- SCHÉMA DE LECTURE (8 étapes)
--
--   ÉTAPE 1  dim_support_agents      Qui sont les 4 agents de l'équipe ?
--   ÉTAPE 2  stg_conversations       Nettoyer les conversations (parsing JSON)
--   ÉTAPE 3  stg_messages            Garder uniquement les vrais messages
--   ÉTAPE 4  int_premier_msg_client  Quand le client a-t-il écrit pour la 1re fois ?
--   ÉTAPE 5  int_premiere_reponse    Quand l'agent a-t-il répondu pour la 1re fois ?
--   ÉTAPE 6  int_conversations       Vue centrale : 1 ligne par conversation, tout calculé
--   ÉTAPE 7  mart_kpis_hebdo         KPIs de l'équipe, agrégés par semaine
--   ÉTAPE 8  mart_agents_hebdo       Mêmes KPIs, détaillés par agent et par semaine
--   ÉTAPE 9  mart_heatmap_volume     Volume de conversations par jour et par heure
--
-- ============================================================


-- ============================================================
-- ÉTAPE 1 — Référentiel des agents Support
-- ============================================================
-- Pourquoi une table séparée ?
-- Si un agent rejoint ou quitte l'équipe, on met à jour ici
-- et tous les rapports se mettent à jour automatiquement.

CREATE OR REPLACE TABLE dim_support_agents AS
SELECT * FROM (VALUES
    (5217337, 'Héloise'),
    (5391224, 'Justine'),
    (5440474, 'Patrick'),
    (5300290, 'Raphael')
) AS t (agent_id, agent_name);


-- ============================================================
-- ÉTAPE 2 — Nettoyage des conversations
-- ============================================================
-- Problème : ASSIGNEE et CONVERSATION_RATING sont stockés en JSON
-- dans la source Intercom. On les "parse" ici pour avoir des colonnes
-- normales utilisables dans toutes les étapes suivantes.
--
-- QUALIFY ROW_NUMBER() : l'ETL (Stitch/Airbyte) peut re-charger
-- une même ligne en cas d'erreur réseau. Cette ligne garantit
-- qu'on ne garde qu'une seule version par conversation —
-- la plus récente (_SDC_EXTRACTED_AT = timestamp de l'extraction).

CREATE OR REPLACE VIEW stg_conversations AS
SELECT
    ID                                                AS conversation_id,
    TO_TIMESTAMP_NTZ(CREATED_AT)                      AS created_at,

    -- L'assignee est un JSON : {"id": 5217337, "type": "admin"}
    -- On extrait uniquement l'ID numérique
    TRY_PARSE_JSON(ASSIGNEE):id::INTEGER              AS assignee_id,

    -- La note CSAT est un JSON : {"rating": 4, "created_at": ...}
    -- On extrait uniquement la note (1 à 5)
    TRY_PARSE_JSON(CONVERSATION_RATING):rating::INTEGER AS csat_rating,

    -- Les tags sont un JSON : [{"name": "Badgeuse"}, {"name": "Équipes"}]
    -- On garde le JSON brut, on le dénormalisera si besoin
    TAGS                                              AS tags_raw,

    PRIORITY,
    STATE

FROM CONVERSATIONS
QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _SDC_EXTRACTED_AT DESC) = 1;


-- ============================================================
-- ÉTAPE 3 — Nettoyage des messages
-- ============================================================
-- On ne garde que les vrais messages (PART_GROUP = 'Message').
-- Les autres valeurs de PART_GROUP sont des événements système :
--   - 'Assignment' : réassignation à un agent
--   - 'Close'      : fermeture de la conversation
--   - 'Quick Reply': bouton automatique du bot
--
-- On exclut aussi les bots (author_type = 'bot') car ils ne
-- reflètent pas l'effort de l'équipe Support.
--
-- Note : la documentation Intercom parle de "part_type" mais
-- la colonne réelle dans les données s'appelle "PART_GROUP".

CREATE OR REPLACE VIEW stg_messages AS
SELECT
    CONVERSATION_ID                               AS conversation_id,
    TO_TIMESTAMP_NTZ(CREATED_AT)                  AS created_at,

    -- L'auteur est un JSON : {"id": 5217337, "type": "admin"}
    -- On extrait le type pour distinguer client / agent / bot
    TRY_PARSE_JSON(AUTHOR):type::VARCHAR          AS author_type

FROM CONVERSATION_PARTS
WHERE PART_GROUP = 'Message'                      -- uniquement les vrais messages
  AND TRY_PARSE_JSON(AUTHOR):type::VARCHAR <> 'bot' -- on exclut les bots
QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _SDC_EXTRACTED_AT DESC) = 1;


-- ============================================================
-- ÉTAPE 4 — Premier message du client par conversation
-- ============================================================
-- On cherche la date du premier message envoyé par le client
-- (author_type = 'user'). C'est le moment où le chronomètre
-- du FRT commence : le client attend une réponse à partir de là.

CREATE OR REPLACE VIEW int_premier_msg_client AS
SELECT
    conversation_id,
    MIN(created_at) AS premier_msg_client_at
FROM stg_messages
WHERE author_type = 'user'
GROUP BY conversation_id;


-- ============================================================
-- ÉTAPE 5 — Première réponse de l'agent par conversation
-- ============================================================
-- On cherche la date de la première réponse d'un agent humain
-- (author_type = 'admin'). Les bots sont déjà exclus depuis
-- l'étape 3, donc tous les 'admin' ici sont des humains.
-- C'est le moment où le chronomètre du FRT s'arrête.

CREATE OR REPLACE VIEW int_premiere_reponse AS
SELECT
    conversation_id,
    MIN(created_at) AS premiere_reponse_at
FROM stg_messages
WHERE author_type = 'admin'
GROUP BY conversation_id;


-- ============================================================
-- ÉTAPE 6 — Vue centrale : une ligne par conversation
-- ============================================================
-- On assemble tout : conversation + FRT calculé + flags métier.
-- C'est la table de référence de tout le reporting.
--
-- Calcul du FRT (First Response Time) :
--   FRT = premiere_reponse_at - premier_msg_client_at
--   On utilise les étapes 4 et 5, pas CREATED_AT.
--   Pourquoi ? CREATED_AT = quand la conv est ouverte (souvent
--   par le bot). Le client commence à attendre quand IL écrit,
--   pas quand la conversation est créée techniquement.
--
-- SLA = FRT inférieur à 5 minutes (= 300 secondes).
--   Hypothèse retenue faute d'information officielle.
--   Question à poser à Lorette : "Est-ce bien 5 min ?"

CREATE OR REPLACE VIEW int_conversations AS
SELECT
    c.conversation_id,
    c.created_at,
    c.assignee_id,
    c.csat_rating,
    c.priority,
    c.state,

    -- Dates de référence pour le FRT
    m_client.premier_msg_client_at,
    m_admin.premiere_reponse_at,

    -- FRT en secondes (NULL si pas de réponse ou pas de message client)
    DATEDIFF('second',
        m_client.premier_msg_client_at,
        m_admin.premiere_reponse_at
    ) AS frt_secondes,

    -- FRT en minutes, plus lisible pour les dashboards
    ROUND(
        DATEDIFF('second',
            m_client.premier_msg_client_at,
            m_admin.premiere_reponse_at
        ) / 60.0,
        1
    ) AS frt_minutes,

    -- La conversation a-t-elle reçu une réponse humaine ?
    CASE WHEN m_admin.premiere_reponse_at IS NOT NULL
         THEN TRUE ELSE FALSE
    END AS a_recu_une_reponse,

    -- La SLA est-elle respectée ? (FRT < 5 minutes = 300 secondes)
    CASE WHEN DATEDIFF('second',
                m_client.premier_msg_client_at,
                m_admin.premiere_reponse_at) <= 300
         THEN TRUE ELSE FALSE
    END AS sla_respectee,

    -- La note CSAT est-elle positive ? (4 ou 5 étoiles sur 5)
    -- Convention Intercom : 4 = Bon, 5 = Excellent
    CASE WHEN c.csat_rating >= 4 THEN TRUE
         WHEN c.csat_rating IS NOT NULL THEN FALSE
         ELSE NULL
    END AS csat_positif,

    -- Cette conversation est-elle traitée par l'équipe Support de Lorette ?
    CASE WHEN c.assignee_id IN (5217337, 5391224, 5440474, 5300290)
         THEN TRUE ELSE FALSE
    END AS est_equipe_support,

    -- Dimension temporelle : semaine ISO (lundi au dimanche)
    DATE_TRUNC('week', c.created_at) AS semaine,
    DAYOFWEEK(c.created_at)          AS jour_semaine,  -- 0 = dim, 1 = lun, ...
    HOUR(c.created_at)               AS heure

FROM stg_conversations          c
LEFT JOIN int_premier_msg_client m_client ON c.conversation_id = m_client.conversation_id
LEFT JOIN int_premiere_reponse   m_admin  ON c.conversation_id = m_admin.conversation_id;
-- LEFT JOIN et non INNER JOIN : on garde toutes les conversations,
-- même celles sans réponse (elles comptent dans le volume total).


-- ============================================================
-- ÉTAPE 7 — KPIs hebdomadaires de l'équipe
-- ============================================================
-- Une ligne par semaine. C'est ce qui alimente les cartes KPI
-- et les graphiques de tendance dans le dashboard de Lorette.
--
-- Dénominateur du FRT <5min = conversations ayant reçu une réponse.
-- Pourquoi pas le total ? Pour ne pas pénaliser l'équipe pour
-- les conversations abandonnées par le client avant toute réponse.

CREATE OR REPLACE TABLE mart_kpis_hebdo AS
SELECT
    semaine,

    -- Volume
    COUNT(*)                                                        AS nb_conversations,
    SUM(CASE WHEN est_equipe_support THEN 1 ELSE 0 END)            AS nb_conversations_support,
    SUM(CASE WHEN priority = 'priority' THEN 1 ELSE 0 END)         AS nb_prioritaires,

    -- CSAT
    COUNT(CASE WHEN csat_rating IS NOT NULL THEN 1 END)             AS nb_evaluees,
    ROUND(AVG(csat_rating), 2)                                      AS score_csat_moyen,
    ROUND(
        100.0
        * COUNT(CASE WHEN csat_positif = TRUE THEN 1 END)
        / NULLIF(COUNT(CASE WHEN csat_rating IS NOT NULL THEN 1 END), 0)
    , 1)                                                            AS taux_csat_positif_pct,
    -- NULLIF(..., 0) évite une division par zéro si aucune conv n'est évaluée

    -- FRT
    ROUND(MEDIAN(CASE WHEN frt_secondes > 0 THEN frt_minutes END), 1) AS frt_median_min,
    -- Médiane et non moyenne : la moyenne est biaisée par les conversations
    -- ouvertes la nuit (ex : FRT de 8h = 480 min). La médiane représente
    -- l'expérience client typique.

    ROUND(
        100.0
        * COUNT(CASE WHEN sla_respectee = TRUE AND frt_secondes > 0 THEN 1 END)
        / NULLIF(COUNT(CASE WHEN a_recu_une_reponse = TRUE THEN 1 END), 0)
    , 1)                                                            AS taux_sla_respectee_pct

FROM int_conversations
WHERE est_equipe_support = TRUE
GROUP BY semaine
ORDER BY semaine DESC;


-- ============================================================
-- ÉTAPE 8 — Performance par agent et par semaine
-- ============================================================
-- Mêmes métriques que l'étape 7, mais déclinées par agent.
-- JOIN INNER sur dim_support_agents : seuls les agents connus
-- de l'équipe apparaissent ici.

CREATE OR REPLACE TABLE mart_agents_hebdo AS
SELECT
    conv.semaine,
    agents.agent_name,

    -- Volume
    COUNT(*)                                                        AS nb_conversations,
    COUNT(CASE WHEN conv.priority = 'priority' THEN 1 END)         AS nb_prioritaires,

    -- CSAT
    COUNT(CASE WHEN conv.csat_rating IS NOT NULL THEN 1 END)        AS nb_evaluees,
    ROUND(AVG(conv.csat_rating), 2)                                 AS score_csat_moyen,
    ROUND(
        100.0
        * COUNT(CASE WHEN conv.csat_positif = TRUE THEN 1 END)
        / NULLIF(COUNT(CASE WHEN conv.csat_rating IS NOT NULL THEN 1 END), 0)
    , 1)                                                            AS taux_csat_positif_pct,

    -- FRT
    ROUND(MEDIAN(CASE WHEN conv.frt_secondes > 0 THEN conv.frt_minutes END), 1)
                                                                    AS frt_median_min,
    ROUND(
        100.0
        * COUNT(CASE WHEN conv.sla_respectee = TRUE AND conv.frt_secondes > 0 THEN 1 END)
        / NULLIF(COUNT(CASE WHEN conv.a_recu_une_reponse = TRUE THEN 1 END), 0)
    , 1)                                                            AS taux_sla_respectee_pct

FROM int_conversations      conv
INNER JOIN dim_support_agents agents ON conv.assignee_id = agents.agent_id
-- INNER JOIN : on ne garde que les conversations assignées à un agent
-- connu de l'équipe (les autres sont filtrées naturellement)

GROUP BY conv.semaine, agents.agent_name
ORDER BY conv.semaine DESC, nb_conversations DESC;


-- ============================================================
-- ÉTAPE 9 — Volume par jour et par heure (heatmap)
-- ============================================================
-- Répond à la question de Lorette : "À quels moments notre équipe
-- est-elle le plus sollicitée dans la semaine ?"
-- Utile pour organiser les plannings et anticiper les pics.
--
-- Note : les timestamps sont en UTC. Si Lorette préfère voir
-- les horaires en heure de Paris, ajouter :
--   CONVERT_TIMEZONE('UTC', 'Europe/Paris', created_at)

CREATE OR REPLACE TABLE mart_heatmap_volume AS
SELECT
    jour_semaine,
    heure,
    COUNT(*)  AS nb_conversations
FROM int_conversations
WHERE est_equipe_support = TRUE
GROUP BY jour_semaine, heure
ORDER BY jour_semaine, heure;
