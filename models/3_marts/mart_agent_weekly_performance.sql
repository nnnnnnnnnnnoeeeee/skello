-- Mart : performance hebdomadaire par agent Support.
-- Grain : 1 ligne par (agent, semaine ISO).
-- Périmètre : conversations assignées à l'équipe Support uniquement.
--
-- Utilisé pour :
--   - Le tableau "Performance par agent" dans le dashboard

CREATE OR REPLACE TABLE mart_agent_weekly_performance AS

SELECT
    week_start,
    assignee_id,
    agent_name,

    -- ── Volume ──────────────────────────────────────────────────────────────
    COUNT(*)                                                                       AS total_conversations,
    COUNT(CASE WHEN state = 'closed' THEN 1 END)                                 AS closed_conversations,

    -- ── CSAT ────────────────────────────────────────────────────────────────
    COUNT(CASE WHEN has_csat THEN 1 END)                                         AS rated_conversations,
    ROUND(AVG(csat_rating), 2)                                                    AS avg_csat,
    ROUND(
        100.0 * COUNT(CASE WHEN has_csat THEN 1 END)
              / NULLIF(COUNT(*), 0),
        1
    )                                                                              AS csat_response_rate_pct,

    -- ── SLA ──────────────────────────────────────────────────────────────────
    COUNT(CASE WHEN sla_met THEN 1 END)                                          AS conversations_sla_met,
    ROUND(
        100.0 * COUNT(CASE WHEN sla_met                      THEN 1 END)
              / NULLIF(COUNT(CASE WHEN has_admin_reply THEN 1 END), 0),
        1
    )                                                                              AS pct_sla_met,

    -- ── Temps de première réponse ────────────────────────────────────────────
    ROUND(MEDIAN(first_response_minutes), 1)                                      AS median_first_response_min,
    ROUND(AVG(first_response_minutes),    1)                                      AS avg_first_response_min

FROM int_conversation_metrics
WHERE is_support_team_conversation
GROUP BY week_start, assignee_id, agent_name
ORDER BY week_start DESC, agent_name ASC;
