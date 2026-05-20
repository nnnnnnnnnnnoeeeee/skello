-- Intermédiaire : une ligne enrichie par conversation.
-- C'est la table centrale du modèle : elle joint toutes les dimensions
-- et sert de base à toutes les tables de mart.
--
-- Grain : 1 ligne par conversation.
--
-- Note sur le périmètre :
--   Le flag `is_support_team_conversation` vaut TRUE si l'assignee courant
--   fait partie de l'équipe de Lorette. Les conversations non assignées ou
--   assignées à d'autres équipes sont conservées pour permettre des analyses
--   croisées, mais exclues des KPIs de reporting via ce flag.
--
-- Question ouverte pour Lorette :
--   Une conversation peut être réassignée en cours de route.
--   Ce modèle utilise l'assignee final (CONVERSATIONS.ASSIGNEE).
--   Si le besoin est de mesurer la charge par agent à chaque étape,
--   il faudrait s'appuyer sur les parts de type 'assignment' dans
--   CONVERSATION_PARTS.

CREATE OR REPLACE VIEW int_conversation_metrics AS

SELECT
    c.conversation_id,
    c.created_at,
    c.updated_at,
    c.state,
    c.is_open,
    c.priority,
    c.week_start,
    c.day_of_week_iso,
    c.hour_of_day,

    -- CSAT
    c.csat_rating,
    c.csat_remark,
    (c.csat_rating IS NOT NULL)                                                   AS has_csat,

    -- Agent assigné
    c.assignee_id,
    a.agent_name,
    (a.agent_id IS NOT NULL)                                                       AS is_support_team_conversation,

    -- Métriques de première réponse
    r.first_response_at,
    r.first_response_seconds,
    r.first_response_minutes,
    r.sla_met,
    (r.conversation_id IS NOT NULL)                                                AS has_admin_reply

FROM stg_conversations            c
LEFT JOIN dim_support_agents      a ON a.agent_id       = c.assignee_id
LEFT JOIN int_first_responses     r ON r.conversation_id = c.conversation_id;
