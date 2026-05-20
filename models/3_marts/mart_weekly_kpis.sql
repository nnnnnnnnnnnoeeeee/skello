-- Mart : KPIs hebdomadaires de l'équipe Support (meeting du lundi de Lorette).
-- Grain : 1 ligne par semaine ISO (lundi → dimanche).
-- Périmètre : conversations assignées à l'équipe Support uniquement.
--
-- Utilisé pour :
--   - Les 4 KPI cards du header du dashboard
--   - Les courbes d'évolution sur 4 semaines

CREATE OR REPLACE TABLE mart_weekly_kpis AS

WITH support_conversations AS (
    SELECT *
    FROM int_conversation_metrics
    WHERE is_support_team_conversation
)

SELECT
    week_start,

    -- ── Volume ──────────────────────────────────────────────────────────────
    COUNT(*)                                                                       AS total_conversations,
    COUNT(CASE WHEN state = 'closed' THEN 1 END)                                 AS closed_conversations,
    COUNT(CASE WHEN is_open         THEN 1 END)                                  AS open_conversations,

    -- ── CSAT ────────────────────────────────────────────────────────────────
    COUNT(CASE WHEN has_csat THEN 1 END)                                         AS rated_conversations,
    ROUND(AVG(csat_rating), 2)                                                    AS avg_csat,             -- sur 5
    ROUND(
        100.0 * COUNT(CASE WHEN has_csat THEN 1 END)
              / NULLIF(COUNT(*), 0),
        1
    )                                                                              AS csat_response_rate_pct,

    -- ── SLA : première réponse < 5 min ──────────────────────────────────────
    -- Dénominateur = conversations ayant reçu au moins une réponse admin
    -- (exclut les conversations sans réponse pour ne pas pénaliser le ratio)
    COUNT(CASE WHEN sla_met THEN 1 END)                                          AS conversations_sla_met,
    ROUND(
        100.0 * COUNT(CASE WHEN sla_met                      THEN 1 END)
              / NULLIF(COUNT(CASE WHEN has_admin_reply THEN 1 END), 0),
        1
    )                                                                              AS pct_sla_met,

    -- ── Temps de première réponse ────────────────────────────────────────────
    ROUND(MEDIAN(first_response_minutes), 1)                                      AS median_first_response_min,
    ROUND(AVG(first_response_minutes),    1)                                      AS avg_first_response_min

FROM support_conversations
GROUP BY week_start
ORDER BY week_start DESC;
