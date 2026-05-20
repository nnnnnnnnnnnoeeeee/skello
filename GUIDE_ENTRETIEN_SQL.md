# Guide entretien — Explication du modèle SQL ligne par ligne

Ce guide explique chaque fichier SQL du dossier `models/` pour que tu puisses tout expliquer à l'oral sans hésiter.

---

## Vue d'ensemble : pourquoi 4 couches ?

```
CONVERSATIONS + CONVERSATION_PARTS   ← données brutes Intercom
        │
        ▼
0_seeds/        référentiels statiques (qui sont les agents ?)
        │
        ▼
1_staging/      nettoyage technique (parser les JSON, typer les colonnes)
        │
        ▼
2_intermediate/ logique métier (calculer le FRT, enrichir chaque conversation)
        │
        ▼
3_marts/        agrégations pour le dashboard (KPIs par semaine, par agent)
```

**Phrase à retenir pour l'oral :**
> *"Chaque couche a une seule responsabilité. Si le périmètre de l'équipe change, je touche uniquement les seeds. Si la définition du FRT change, je touche uniquement l'intermediate. Les marts se mettent à jour automatiquement."*

---

## ÉTAPE 0 — `0_seeds/dim_support_agents.sql`

### Ce que fait ce fichier

Crée une table avec les 4 agents de l'équipe Support et leurs IDs Intercom.

### Le code

```sql
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
```

### Explication ligne par ligne

| Ligne | Ce que ça fait | Ce que tu dis à l'oral |
|---|---|---|
| `CREATE OR REPLACE TABLE` | Crée ou recrée la table | *"OR REPLACE pour pouvoir relancer sans erreur"* |
| `NOT NULL` | Interdit les valeurs vides | *"Un agent sans ID ou sans nom n'a pas de sens"* |
| `CONSTRAINT pk_... PRIMARY KEY` | Garantit qu'il n'y a pas deux fois le même ID | *"Protection contre les doublons"* |
| `SELECT * FROM (VALUES ...)` | Insère les données directement dans le SQL | *"C'est un seed — données statiques qu'on maintient à la main"* |

### Pourquoi une table séparée ?

Si un agent quitte l'équipe ou si un nouveau rejoint : on modifie **ici uniquement**. Tous les marts qui font un JOIN sur cette table se mettent à jour automatiquement à la prochaine exécution.

---

## ÉTAPE 1A — `1_staging/stg_conversations.sql`

### Ce que fait ce fichier

Nettoie la table `CONVERSATIONS` : parse les JSON, normalise les types, ajoute des helpers de date. **Pas de filtre métier** — toutes les conversations passent.

### Les colonnes clés

```sql
-- Avant (dans la source) :
CONVERSATION_RATING = '{"rating": 4, "remark": "Très bien"}'
ASSIGNEE            = '{"id": 5217337, "type": "admin"}'

-- Après (dans la vue stg_conversations) :
csat_rating = 4         ← un entier propre
assignee_id = 5217337   ← un entier propre
```

### Les lignes importantes à expliquer

**Parsing du CSAT :**
```sql
TRY_CAST(
    TRY_PARSE_JSON(conversation_rating):rating::VARCHAR AS INTEGER
) AS csat_rating
```
- `TRY_PARSE_JSON()` : ouvre le JSON. `TRY_` = ne plante pas si le JSON est malformé, retourne NULL
- `:rating` : extrait le champ "rating" du JSON
- `::VARCHAR` puis `TRY_CAST(... AS INTEGER)` : convertit en nombre entier proprement

**Pourquoi `TRY_` partout ?**
> *"Sans TRY_, une seule ligne avec un JSON corrompu fait planter toute la requête. Avec TRY_, la ligne retourne NULL et le reste continue de tourner."*

**Calcul de la semaine ISO (lundi = début) :**
```sql
TO_DATE(
    DATEADD(day, -(MOD(DAYOFWEEK(created_at) + 6, 7)), created_at)
) AS week_start
```
- `DAYOFWEEK()` retourne 0=Dimanche, 1=Lundi, ..., 6=Samedi (convention Snowflake)
- `MOD(... + 6, 7)` : convertit pour que Lundi=0, Mardi=1, ..., Dimanche=6
- `DATEADD(day, -X, ...)` : recule au lundi de la semaine

**Pourquoi c'est une VIEW et pas une TABLE ?**
> *"Le staging n'a pas besoin d'être stocké — c'est juste du nettoyage. Une VIEW est recalculée à la demande, sans coût de stockage."*

---

## ÉTAPE 1B — `1_staging/stg_conversation_parts.sql`

### Ce que fait ce fichier

Nettoie `CONVERSATION_PARTS` : parse l'auteur de chaque message, normalise les types. Conserve toutes les parts — le filtrage est fait en couche intermediate.

### Point important à connaître

**La doc Intercom parle de `PART_TYPE` mais la vraie colonne s'appelle `PART_GROUP`.**
C'est un écart entre la documentation et les données réelles — tu l'as détecté en explorant les CSV.

```
PART_GROUP = 'Message'     → vrais messages (user, admin, bot)
PART_GROUP = 'Assignment'  → événement "assigné à Patrick"
PART_GROUP = 'Close'       → événement "conversation fermée"
PART_GROUP = 'Quick Reply' → bouton automatique du bot
```
On ne garde que `'Message'` pour calculer le FRT.

### La ligne importante

```sql
LOWER(
    COALESCE(TRY_PARSE_JSON(author):type::VARCHAR, 'unknown')
) AS author_type   -- 'admin' | 'user' | 'bot'
```
- `LOWER()` : normalise en minuscules pour éviter les problèmes de casse
- `COALESCE(..., 'unknown')` : si le type est NULL, on met 'unknown' plutôt que NULL

---

## ÉTAPE 2A — `2_intermediate/int_first_responses.sql`

### Ce que fait ce fichier

Calcule la **première réponse admin humaine** pour chaque conversation, et détermine si la SLA de 5 minutes est respectée.

### Le code décomposé

```sql
-- Étape 1 : ne garder que les messages admin (humains, bots déjà exclus)
WITH admin_replies AS (
    SELECT conversation_id, created_at AS reply_at
    FROM stg_conversation_parts
    WHERE part_group  = 'Message'
      AND author_type = 'admin'
),

-- Étape 2 : prendre le plus ancien message admin par conversation
first_reply_per_conv AS (
    SELECT conversation_id, MIN(reply_at) AS first_response_at
    FROM admin_replies
    GROUP BY conversation_id
)

-- Étape 3 : calculer le délai et le flag SLA
SELECT
    f.conversation_id,
    f.first_response_at,
    DATEDIFF('second', c.created_at, f.first_response_at) AS first_response_seconds,
    (DATEDIFF('second', c.created_at, f.first_response_at) <= 300) AS sla_met
FROM first_reply_per_conv f
JOIN stg_conversations c ON c.conversation_id = f.conversation_id;
```

### Ce que tu dois savoir expliquer

**Pourquoi `MIN(reply_at)` ?**
> *"On veut la première réponse, pas toutes. MIN() sur une date retourne la plus ancienne."*

**Pourquoi `DATEDIFF('second', ...)` et pas en minutes directement ?**
> *"En secondes pour être précis. La SLA est 300 secondes = 5 minutes exactement. Si on travaille en minutes, un FRT de 4 min 59 sec serait arrondi à 5 et passerait la SLA de justesse — on perdrait de la précision."*

**Pourquoi `<= 300` et pas `< 300` ?**
> *"Une réponse exactement à 300 secondes respecte la SLA de 5 min. L'égalité doit être incluse."*

**Attention :** dans `skello_support_data_model.sql` (version simplifiée), le FRT est calculé depuis le **premier message client**, pas depuis `created_at`. C'est plus précis — le client commence à attendre quand *il* écrit, pas quand la conversation est ouverte. C'est le choix que tu défends à l'oral.

---

## ÉTAPE 2B — `2_intermediate/int_conversation_metrics.sql`

### Ce que fait ce fichier

La **vue centrale** du modèle. Assemble tout en une seule table : 1 ligne par conversation avec toutes les dimensions et métriques calculées.

### Les JOINs expliqués

```sql
FROM stg_conversations            c
LEFT JOIN dim_support_agents      a ON a.agent_id       = c.assignee_id
LEFT JOIN int_first_responses     r ON r.conversation_id = c.conversation_id
```

| JOIN | Type | Pourquoi ce type |
|---|---|---|
| `dim_support_agents` | LEFT JOIN | Une conversation peut être assignée à quelqu'un hors équipe Support — on veut la garder dans la vue avec `agent_name = NULL` |
| `int_first_responses` | LEFT JOIN | Une conversation peut n'avoir reçu aucune réponse — on veut la garder avec `first_response_at = NULL` |

**Pourquoi LEFT JOIN et pas INNER JOIN partout ?**
> *"Un INNER JOIN ferait disparaître les conversations sans réponse et les conversations hors équipe Support. Avec LEFT JOIN, on les garde toutes — le flag `is_support_team_conversation` permet de filtrer ensuite dans les marts selon le besoin."*

### Le flag clé

```sql
(a.agent_id IS NOT NULL) AS is_support_team_conversation
```
Vaut TRUE si le JOIN avec `dim_support_agents` a trouvé une correspondance (= l'assignee est dans l'équipe). Vaut FALSE sinon. Utilisé dans tous les marts pour filtrer le périmètre.

---

## ÉTAPE 3A — `3_marts/mart_weekly_kpis.sql`

### Ce que fait ce fichier

Agrège toutes les conversations Support par semaine. Produit les KPIs qui alimentent les cartes du dashboard.

### Le CTE d'entrée

```sql
WITH support_conversations AS (
    SELECT * FROM int_conversation_metrics
    WHERE is_support_team_conversation
)
```
Filtre une fois pour toutes en début de requête. Toutes les agrégations ci-dessous travaillent sur ce sous-ensemble.

### Les calculs à savoir expliquer

**CSAT positif % :**
```sql
-- (pas dans ce fichier mais dans skello_support_data_model.sql)
100.0 * COUNT(CASE WHEN csat_rating >= 4 THEN 1 END)
      / NULLIF(COUNT(CASE WHEN has_csat THEN 1 END), 0)
```
- `COUNT(CASE WHEN ... THEN 1 END)` : compte uniquement les lignes qui vérifient la condition
- `NULLIF(..., 0)` : si le dénominateur est 0 (aucune note), retourne NULL au lieu de faire une division par zéro

**SLA % :**
```sql
100.0 * COUNT(CASE WHEN sla_met THEN 1 END)
      / NULLIF(COUNT(CASE WHEN has_admin_reply THEN 1 END), 0)
```
**Dénominateur = conversations avec réponse**, pas le total.
> *"On ne pénalise pas l'équipe pour les conversations abandonnées par le client. Une conv où le client repart sans attendre de réponse n'a pas de FRT — l'inclure au dénominateur ferait baisser artificiellement le SLA%."*

**Médiane du FRT :**
```sql
ROUND(MEDIAN(first_response_minutes), 1) AS median_first_response_min
```
> *"On utilise MEDIAN() et non AVG() car la moyenne est fortement biaisée par les conversations ouvertes la nuit (FRT de plusieurs heures). Sur les données réelles : médiane = 7.4 min, moyenne = 100 min. La médiane représente l'expérience client typique."*

**Pourquoi c'est une TABLE et pas une VIEW ?**
> *"Les marts sont matérialisés en TABLE pour que le BI tool (Looker) lise des données précalculées, sans recalculer toute la chaîne à chaque fois qu'un utilisateur ouvre le dashboard."*

---

## ÉTAPE 3B — `3_marts/mart_agent_weekly_performance.sql`

### Ce que fait ce fichier

Exactement les mêmes KPIs que `mart_weekly_kpis`, mais groupés par agent ET par semaine.

### La différence clé avec mart_weekly_kpis

```sql
GROUP BY week_start, assignee_id, agent_name
```
Au lieu de `GROUP BY week_start` uniquement.

### Pourquoi pas de CTE ici ?

Le filtre est fait directement dans le WHERE :
```sql
WHERE is_support_team_conversation
```
Même résultat, écriture plus directe pour une requête simple.

---

## ÉTAPE 3C — `3_marts/mart_volume_heatmap.sql`

### Ce que fait ce fichier

Compte le volume de conversations par **jour de la semaine** et par **heure**. Alimente la heatmap du dashboard.

### Le code

```sql
SELECT
    week_start,
    day_of_week_iso,
    CASE day_of_week_iso
        WHEN 1 THEN 'Lundi' ... WHEN 7 THEN 'Dimanche'
    END AS day_label,
    hour_of_day,
    COUNT(*) AS conversation_count
FROM int_conversation_metrics
WHERE is_support_team_conversation
GROUP BY week_start, day_of_week_iso, day_label, hour_of_day
```

### Ce que tu dois savoir expliquer

**Pourquoi garder `week_start` dans le GROUP BY ?**
> *"Pour permettre deux usages : agréger sur toutes les semaines (vue globale, pattern stable) ou filtrer sur une semaine précise pour voir si le pic a bougé. Le BI tool choisit comment agréger."*

**Note sur le timezone :**
> *"Les timestamps sont en UTC. Si l'équipe travaille en heure de Paris, il faudrait ajouter `CONVERT_TIMEZONE('UTC', 'Europe/Paris', created_at)` avant d'extraire l'heure. C'est une question ouverte pour Lorette."*

---

## Résumé — Ce que tu retiens pour l'oral

| Question de Delphine | Ta réponse |
|---|---|
| *"Pourquoi des couches ?"* | Chaque couche = une responsabilité. Changement isolé, pas de cascade. |
| *"Pourquoi des vues en staging ?"* | Pas de stockage redondant. Les marts matérialisés suffisent. |
| *"Pourquoi TRY_PARSE_JSON ?"* | Une ligne JSON corrompue ne fait pas planter toute la requête. |
| *"Pourquoi LEFT JOIN ?"* | Garder toutes les conversations, même sans réponse ou hors équipe. |
| *"Pourquoi MEDIAN et pas AVG ?"* | Médiane 7.4 min vs moyenne 100 min — la moyenne est inutilisable. |
| *"Pourquoi NULLIF(..., 0) ?"* | Éviter une division par zéro si une semaine n'a aucune évaluation. |
| *"Pourquoi le dénominateur SLA = convs avec réponse ?"* | Ne pas pénaliser l'équipe pour des convs abandonnées par le client. |
| *"Pourquoi dim_support_agents séparé ?"* | Un agent change → on modifie ici, tout le reste se met à jour. |
