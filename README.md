# Dashboard Support Skello — Reporting hebdomadaire Lorette

Analyse des performances de l'équipe Support Skello à partir des données Intercom exportées dans Snowflake. Deux livrables : un **modèle de données SQL en couches** et un **dashboard interactif** pour le meeting hebdomadaire de Lorette.

> **Live demo** → déployé sur Streamlit Cloud *(lien dans les settings du repo GitHub)*

---

## Lancer en local

```bash
pip install -r requirements.txt
streamlit run app.py
```

`CONVERSATIONS.csv` et `CONVERSATION_PARTS.csv` doivent être présents à la racine. `app.py` charge les données réelles, calcule tous les KPIs et injecte les résultats dans le dashboard HTML au démarrage.

---

## Structure du projet

```
├── app.py                                     # Streamlit : charge CSV → calcule KPIs → sert le dashboard
├── skello_support_dashboard_lorette.html      # Dashboard interactif (HTML + Chart.js, 5 onglets)
├── skello_support_data_model.sql              # Modèle SQL complet — version fichier unique (pour la présentation)
├── models/                                    # Même modèle en structure dbt-like (pour un vrai projet Snowflake)
│   ├── 0_seeds/dim_support_agents.sql
│   ├── 1_staging/
│   ├── 2_intermediate/
│   └── 3_marts/
└── requirements.txt
```

**Deux versions SQL** : `skello_support_data_model.sql` est lisible d'un seul coup d'œil ; `models/` montre la structure à adopter dans un vrai projet dbt avec séparation des responsabilités par couche.

---

## Modèle de données

Architecture en 4 couches inspirée de dbt. Staging et intermediate sont des **vues** ; marts sont **matérialisés en tables** pour les performances BI.

```
RAW Snowflake (CONVERSATIONS + CONVERSATION_PARTS)
  │
  ├── 0_seeds        dim_support_agents           IDs Intercom → noms agents (référentiel statique)
  │
  ├── 1_staging      stg_conversations            Parse ASSIGNEE / CSAT / TAGS · déduplique ETL
  │                  stg_conversation_parts       Parse AUTHOR · exclut les bots
  │
  ├── 2_intermediate int_first_responses          1re réponse admin humaine par conv → flag SLA 5 min
  │                  int_conversation_metrics     Vue centrale (1 ligne/conv) : FRT, CSAT, périmètre équipe
  │
  └── 3_marts        mart_weekly_kpis             KPIs hebdo équipe (cartes + tendances 8 semaines)
                     mart_agent_weekly_perf       Performance individuelle semaine × agent
                     mart_volume_heatmap          Volume jour × heure (alimentation heatmap)
```

### Ordre d'exécution sur Snowflake

```sql
-- 1. Référentiel agents
models/0_seeds/dim_support_agents.sql

-- 2. Staging (parallèle)
models/1_staging/stg_conversations.sql
models/1_staging/stg_conversation_parts.sql

-- 3. Intermediate (dépendent du staging)
models/2_intermediate/int_first_responses.sql
models/2_intermediate/int_conversation_metrics.sql   -- dépend aussi de dim_support_agents

-- 4. Marts (dépendent de l'intermediate)
models/3_marts/mart_weekly_kpis.sql
models/3_marts/mart_agent_weekly_performance.sql
models/3_marts/mart_volume_heatmap.sql
```

### Choix de modélisation

| Choix | Décision retenue | Justification |
|---|---|---|
| **FRT** | 1er message client → 1re réponse admin humaine | Mesure la réactivité réelle perçue par le client |
| **CSAT positif** | Note ≥ 4/5 | Convention Intercom (4 = Bon, 5 = Excellent) |
| **Exclusion bots** | `author_type <> 'bot'` dans le staging | Consigne explicite ; le bot ne reflète pas l'effort de l'équipe |
| **Dénominateur SLA** | Conversations ayant reçu une réponse | Évite de pénaliser les conversations abandonnées par le client |
| **Médiane FRT** | Préférée à la moyenne | Moyenne biaisée par les nuits/week-ends (104 min vs médiane 8 min) |
| **Déduplication ETL** | `QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _SDC_EXTRACTED_AT DESC)` | Protection contre les re-loads ETL partiels |
| **Filtre messages** | `PART_GROUP = 'Message'` (pas `part_type`) | La colonne `PART_GROUP` est celle fournie dans le dataset réel |

### Résultats sur les données réelles

| Métrique | Valeur |
|---|---|
| Conversations assignées à la team Support | **2 225** (sur 11 799 total Intercom) |
| Conversations avec au moins une réponse | **2 045 / 2 225** (92 %) |
| SLA FRT < 5 min | **34 %** — levier d'amélioration principal |
| Médiane FRT | **8,1 min** (moyenne : 104 min — fortement biaisée par les nuits) |
| CSAT moyen | **4,19 / 5** |
| Taux d'évaluation CSAT | **35 %** (789 conversations évaluées) |

---

## Dashboard (5 onglets)

| Onglet | Contenu |
|---|---|
| **Équipe** | 5 KPI cards · auto-insights · points d'attention · distribution CSAT · tendances 8 semaines |
| **Individuel** | Tableau par agent avec Δ vs S-1 sur toutes les métriques · graphique FRT comparatif |
| **Volume & horaires** | Bar chart par jour de semaine · heatmap heure × jour (toutes semaines confondues) |
| **Thèmes** | Top 5 tags réels avec Δ vs S-1 · courbe de tendance des 3 principaux |
| **Modèle** | Architecture SQL · choix de modélisation · questions pour Lorette |

Navigation par clic ou touches clavier `←` `→`.

---

## Questions pour Lorette

Hypothèses retenues faute d'information — à valider :

1. **SLA FRT** : fixée à 5 min. Est-ce l'objectif officiel ? S'applique-t-elle hors heures ouvrées ?
2. **Définition de la semaine** : lundi–dimanche (ISO, cohérent avec le meeting du lundi). Préférence différente ?
3. **Conversations réouvertes** : comptées dans la semaine de réouverture. Est-ce le comportement souhaité ?
4. **Conversations prioritaires** : volume suivi, pas de SLA dédiée. Souhait d'un traitement séparé ?
5. **Bot de 1er niveau** : exclu du FRT. Fait-il partie du SLA officiel perçu par le client ?
6. **Timezone** : heatmap en UTC. Faut-il convertir en Europe/Paris ?
