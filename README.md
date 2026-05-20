# Modèle de données — Reporting Support Skello

Réponse au challenge technique : modèle de données et template de dashboard  
pour le reporting hebdomadaire de l'équipe Support (Lorette).

---

## Architecture du modèle

Les tables sont organisées en 3 couches, inspirées de la convention dbt :

```
RAW (Snowflake existant)
├── CONVERSATIONS
└── CONVERSATION_PARTS
         │
         ▼
0_seeds/ — référentiels statiques
└── dim_support_agents          Membres de l'équipe Support (seed manuel)
         │
         ▼
1_staging/ — parsing, typage, aucun filtre métier
├── stg_conversations           Parse JSON (CSAT, assignee), helpers temporels
└── stg_conversation_parts      Parse JSON (author), typage
         │
         ▼
2_intermediate/ — logique métier, jointures
├── int_first_responses         1ère réponse humaine par conversation + SLA flag
└── int_conversation_metrics    Vue centrale enrichie (1 ligne / conversation)
         │
         ▼
3_marts/ — tables finales exposées au BI tool
├── mart_weekly_kpis            KPIs agrégés par semaine (header du dashboard)
├── mart_agent_weekly_performance  Performance par agent et par semaine
└── mart_volume_heatmap         Volume par jour × heure (heatmap)
```

**Staging et intermédiaire** : implémentés en `VIEW` (pas de stockage redondant).  
**Marts** : implémentés en `TABLE` pour des performances optimales dans le BI tool.

---

## Ordre d'exécution

```sql
-- 1. Référentiel agents
models/0_seeds/dim_support_agents.sql

-- 2. Vues staging (indépendantes, exécutables en parallèle)
models/1_staging/stg_conversations.sql
models/1_staging/stg_conversation_parts.sql

-- 3. Vues intermédiaires (dépendent des staging)
models/2_intermediate/int_first_responses.sql
models/2_intermediate/int_conversation_metrics.sql   -- dépend aussi de dim_support_agents

-- 4. Tables de mart (dépendent des intermédiaires)
models/3_marts/mart_weekly_kpis.sql
models/3_marts/mart_agent_weekly_performance.sql
models/3_marts/mart_volume_heatmap.sql
```

---

## Hypothèses et choix de modélisation

| Sujet | Choix retenu | Raison |
|---|---|---|
| Exclusion des bots | `author_type = 'admin'` uniquement | Consigne explicite du contexte |
| Messages retenus | `part_type = 'comment'` | Seuls les vrais messages (pas les events système) |
| Assignee | Assignee **final** de la conversation | Données disponibles dans CONVERSATIONS ; voir question 3 ci-dessous |
| Métrique de tendance | **Médiane** du temps de réponse | Plus robuste que la moyenne face aux outliers (nuit, week-end) |
| Semaine ISO | Lundi → dimanche | Cohérent avec le meeting du lundi matin de Lorette |
| Dénominateur SLA | Conversations **ayant reçu au moins une réponse** | Évite de pénaliser les conversations abandonnées par le client |
| Timestamps | UTC (non convertis) | À ajuster selon le fuseau horaire de l'équipe (voir questions) |

---

## Métriques couvertes

| Métrique | Table source | Détail |
|---|---|---|
| CSAT | `mart_weekly_kpis.avg_csat` | Moyenne des notes 1-5 (conversations évaluées) |
| % SLA < 5 min | `mart_weekly_kpis.pct_sla_met` | 1ère réponse humaine en < 300 secondes |
| Volume de conversations | `mart_weekly_kpis.total_conversations` | Conversations créées dans la semaine |
| Temps de réponse médian | `mart_weekly_kpis.median_first_response_min` | En minutes |
| Détail par agent | `mart_agent_weekly_performance` | Toutes les métriques ci-dessus par agent |
| Heatmap jour × heure | `mart_volume_heatmap` | Intensité horaire des sollicitations |

---

## Validation sur les données réelles

Le modèle a été exécuté en Python sur les CSV source pour vérifier la cohérence des résultats.

| Métrique | Valeur observée | Interprétation |
|---|---|---|
| Conversations assignées à la team | **2 225** (sur 11 799 au total) | 19 % du volume total Intercom |
| Conversations avec 1ère réponse admin | **2 045 / 2 225** | 92 % des conversations ont eu une réponse |
| **SLA < 5 min** | **34,3 %** | Levier d'amélioration majeur pour l'équipe |
| Médiane délai 1ère réponse | **8,1 min** | Au-dessus de l'objectif — confirme le SLA à 34 % |
| Moyenne délai 1ère réponse | **104,5 min** | Très distordue par les conversations ouvertes la nuit/week-end |
| **CSAT moyen** | **4,19 / 5** | Bon score client global |
| Taux de réponse CSAT | **35,5 %** (789 / 2 225) | Peu de clients évaluent — à surveiller |

> La forte divergence médiane (8 min) vs moyenne (104 min) illustre l'importance d'utiliser la **médiane** comme KPI : les conversations nocturnes font exploser la moyenne sans refléter l'expérience client typique.

---

## Nota bene : écart de schéma ETL / documentation

La documentation liste les colonnes `PART_TYPE` et `BODY` dans `CONVERSATION_PARTS`,
mais ces colonnes **ne sont pas présentes** dans le dataset fourni.

La colonne fonctionnellement équivalente est **`PART_GROUP`**, dont les valeurs observées sont :

| PART_GROUP | author_type | Volume | Usage dans le modèle |
|---|---|---|---|
| `Message` | user | 72 331 | Messages clients ✓ |
| `Message` | admin | 53 049 | Messages agents ✓ → base du SLA |
| `Message` | bot | 47 799 | Messages bots ✗ (exclus) |
| `Assignment` | admin / bot | 39 834 | Événements système ✗ |
| `Close` | admin / bot | 16 057 | Événements système ✗ |
| `Quick Reply` | bot | 9 409 | Boutons auto ✗ |

Le SQL a été adapté en conséquence.

---

## Questions à poser à Lorette

1. **Fuseau horaire** : faut-il convertir les timestamps UTC en heure de Paris ?
2. **SLA hors heures ouvrées** : le seuil de 5 min s'applique-t-il 24h/24 ou seulement lun-ven ?
3. **Réassignation** : on mesure l'assignee final — est-ce suffisant ou faut-il un suivi par étape ?
4. **Bots** : une réponse bot doit-elle compter dans le SLA ou seulement la première réponse humaine ?
5. **CSAT** : l'échelle est-elle bien 1-5 (émojis) ou thumbs up/down (binaire) ?
6. **Priorité** : un SLA différent pour les conversations `PRIORITY = 'priority'` ?
7. **Conversations sans réponse** : les compter comme échecs SLA ou les exclure ?

---

## Template dashboard

Voir `dashboard/dashboard_template.md` pour le maquette complète et les justifications  
de chaque section du reporting hebdomadaire.
