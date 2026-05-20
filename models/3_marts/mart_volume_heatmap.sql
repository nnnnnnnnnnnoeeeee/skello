-- Mart : volume de conversations par jour de semaine × heure.
-- Grain : 1 ligne par (semaine, jour ISO, heure).
-- Périmètre : conversations assignées à l'équipe Support uniquement.
--
-- Utilisé pour :
--   - Le heatmap "Quand êtes-vous le plus sollicité(e)s ?" dans le dashboard
--
-- Conseil d'utilisation dans le BI tool :
--   - Pour un heatmap global (pattern stable), agréger sur toutes les semaines.
--   - Pour voir l'évolution semaine par semaine, filtrer sur week_start.

CREATE OR REPLACE TABLE mart_volume_heatmap AS

SELECT
    week_start,
    day_of_week_iso,
    CASE day_of_week_iso
        WHEN 1 THEN 'Lundi'
        WHEN 2 THEN 'Mardi'
        WHEN 3 THEN 'Mercredi'
        WHEN 4 THEN 'Jeudi'
        WHEN 5 THEN 'Vendredi'
        WHEN 6 THEN 'Samedi'
        WHEN 7 THEN 'Dimanche'
    END                                                                            AS day_label,
    hour_of_day,
    COUNT(*)                                                                       AS conversation_count

FROM int_conversation_metrics
WHERE is_support_team_conversation
GROUP BY week_start, day_of_week_iso, day_label, hour_of_day
ORDER BY week_start DESC, day_of_week_iso ASC, hour_of_day ASC;
