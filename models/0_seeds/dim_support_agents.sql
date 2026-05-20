-- Table de référence : membres de l'équipe Support de Lorette.
-- Source : fournie dans le contexte métier (IDs Intercom).
-- À mettre à jour manuellement en cas de changement d'équipe.

CREATE OR REPLACE TABLE dim_support_agents (
    agent_id    INTEGER      NOT NULL,
    agent_name  VARCHAR(100) NOT NULL,
    CONSTRAINT pk_dim_support_agents PRIMARY KEY (agent_id)
) AS
SELECT * FROM (VALUES
    (5217337, 'Héloise'),
    (5391224, 'Justine'),
    (5440474, 'Patrick'),
    (5300290, 'Raphael')
) AS t (agent_id, agent_name);
