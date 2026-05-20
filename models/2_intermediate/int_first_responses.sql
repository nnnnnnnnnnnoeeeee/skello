-- Intermédiaire : première réponse humaine par conversation.
--
-- Logique :
--   1. Filtrer les parts de type 'comment' (messages échangés, pas les événements système).
--   2. Ne garder que les messages d'admins humains (author_type = 'admin').
--      Les bots sont exclus conformément aux règles d'analyse définies.
--   3. Prendre le message admin le plus ancien par conversation → première réponse.
--   4. Calculer le délai en secondes depuis la création de la conversation.
--
-- Question ouverte pour Lorette :
--   Le SLA "< 5 min" s'applique-t-il uniquement pendant les heures ouvrées ?
--   Si oui, il faudra ajouter une table de calendrier et ne comptabiliser
--   que le temps pendant lequel l'équipe est disponible.

CREATE OR REPLACE VIEW int_first_responses AS

WITH admin_replies AS (
    SELECT
        p.conversation_id,
        p.created_at AS reply_at
    FROM stg_conversation_parts p
    WHERE p.part_group  = 'Message'  -- messages réels uniquement (exclut Assignment, Close, Snooze…)
      AND p.author_type = 'admin'    -- humains uniquement (bots exclus)
),

first_reply_per_conv AS (
    SELECT
        conversation_id,
        MIN(reply_at) AS first_response_at
    FROM admin_replies
    GROUP BY conversation_id
)

SELECT
    f.conversation_id,
    f.first_response_at,
    c.created_at                                                                   AS conversation_created_at,

    DATEDIFF('second', c.created_at, f.first_response_at)                        AS first_response_seconds,
    ROUND(DATEDIFF('second', c.created_at, f.first_response_at) / 60.0, 1)      AS first_response_minutes,

    -- Flag SLA : première réponse en moins de 5 minutes (300 secondes)
    (DATEDIFF('second', c.created_at, f.first_response_at) <= 300)               AS sla_met

FROM first_reply_per_conv f
JOIN stg_conversations    c ON c.conversation_id = f.conversation_id;
