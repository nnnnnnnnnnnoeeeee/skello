# Dashboard Support — Meeting hebdomadaire de Lorette

> **Outil recommandé** : Metabase, Looker, ou Google Looker Studio  
> **Fréquence de rafraîchissement** : quotidienne (données J-1)  
> **Audience** : Lorette + les 4 membres de l'équipe Support  
> **Usage** : support du meeting du lundi matin (~20-30 min)

---

## Mise en page

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║  SUPPORT SKELLO — Semaine du [lundi] au [dimanche]          ◄ Semaine  Semaine ►║
╠══════════════════════════════════════════════════════════════════════════════════╣
║                                                                                  ║
║  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌───────────────┐ ║
║  │    142          │ │    4,2 / 5      │ │     78 %        │ │   3 min 20 s  │ ║
║  │  Conversations  │ │      CSAT       │ │  SLA < 5 min    │ │ 1ère réponse  │ ║
║  │  ▲ +12 % vs S-1 │ │  ▼ -0,3 vs S-1 │ │  ▲ +5 % vs S-1  │ │ ▼ -45s vs S-1│ ║
║  └─────────────────┘ └─────────────────┘ └─────────────────┘ └───────────────┘ ║
║                                                                                  ║
╠═════════════════════════════════╦════════════════════════════════════════════════╣
║                                 ║                                                ║
║  QUAND ÊTES-VOUS SOLLICITÉ(E)S ?║  PERFORMANCE PAR AGENT                        ║
║  (heatmap — semaine glissante)  ║                                                ║
║                                 ║  Agent     Conv  CSAT  SLA %  Tps méd.        ║
║  Heure  8  9 10 11 12 13 14 15 16 17 18    ║  ────────────────────────────────── ║
║  Lundi  █  ▓  ░  ░  ░  ▓  ▓  ░  ░  ░  ░   ║  Héloise    28   4,5   85 %   2m30  ║
║  Mardi  ▓  █  █  ▓  ░  ▓  ▓  ▓  ░  ░  ░   ║  Justine    31   4,1   72 %   4m10  ║
║  Merci  ▓  █  █  █  ▓  ▓  ▓  ░  ░  ░  ░   ║  Patrick    35   4,3   80 %   3m05  ║
║  Jeudi  ▓  █  ▓  ░  ░  ▓  ▓  ▓  ░  ░  ░   ║  Raphael    29   4,0   75 %   3m50  ║
║  Vendre ░  ▓  ▓  ▓  ░  ░  ░  ░  ░  ░  ░   ║                                     ║
║                                 ║  ░ faible  ▓ moyen  █ fort                    ║
║                                 ║                                                ║
╠═════════════════════════════════╩════════════════════════════════════════════════╣
║                                                                                  ║
║  ÉVOLUTION SUR 8 SEMAINES                                                        ║
║                                                                                  ║
║  Conversations   160 ┤              ●                           ●               ║
║                  140 ┤     ●    ●       ●      ●    ●      ●       ●            ║
║                  120 ┤                                                           ║
║                  100 ┤                                                           ║
║                      S-8  S-7  S-6  S-5  S-4  S-3  S-2  S-1  Sem. courante    ║
║                                                                                  ║
║  CSAT moyen       5,0 ┤                                                          ║
║                   4,5 ┤     ●    ●    ●    ●    ●    ●    ●    ●                ║
║                   4,0 ┤                                                          ║
║                       S-8  S-7  S-6  S-5  S-4  S-3  S-2  S-1  Sem. courante   ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## Détail des sections

### Section 1 — KPIs de la semaine (header)

Quatre cartes côte à côte. Chaque carte affiche la valeur de la semaine N-1 et la variation vs N-2.

| Métrique | Définition | Source SQL | Interprétation |
|---|---|---|---|
| **Volume de conversations** | Nb de conversations créées cette semaine | `mart_weekly_kpis.total_conversations` | Mesure la charge globale |
| **CSAT** | Note moyenne sur 5 (conversations ayant reçu une évaluation) | `mart_weekly_kpis.avg_csat` | Qualité perçue par les clients |
| **SLA < 5 min** | % conversations avec 1ère réponse humaine < 5 min | `mart_weekly_kpis.pct_sla_met` | Réactivité de l'équipe |
| **Tps 1ère réponse (médiane)** | Médiane du délai entre ouverture et 1ère réponse admin | `mart_weekly_kpis.median_first_response_min` | Expérience client typique |

> **Choix médiane vs moyenne** : la médiane est plus robuste aux conversations avec des délais très longs (nuits, week-ends) et représente mieux l'expérience du client "typique".

---

### Section 2 — Heatmap "Quand êtes-vous le plus sollicité(e)s ?"

**Visualisation** : heatmap (grille jour × heure), couleur = intensité du volume.  
**Source SQL** : `mart_volume_heatmap` — agréger sur les 4 dernières semaines pour lisser les variations.  
**Axes** :
- Y : lundi → vendredi (ou lundi → dimanche si l'équipe travaille le week-end)
- X : heures de 8h à 19h

**Pourquoi** : permet à Lorette d'**anticiper les plannings** et de mieux répartir la charge. Si le pic est le mardi matin de 9h à 11h, elle peut s'assurer que toute l'équipe est disponible.

---

### Section 3 — Performance par agent

**Visualisation** : tableau trié par agent (ordre alphabétique par défaut, triable par colonne).  
**Source SQL** : `mart_agent_weekly_performance` filtré sur la semaine sélectionnée.

| Colonne | Description |
|---|---|
| Agent | Prénom |
| Conversations | Total assignées dans la semaine |
| CSAT | Moyenne des notes reçues |
| SLA % | % de 1ères réponses < 5 min |
| Tps médian | Médiane du délai de 1ère réponse |

**Alerte** : mettre en rouge les cellules SLA < 70 % et CSAT < 4,0 pour un repérage rapide.

> **Question pour Lorette** : y a-t-il des agents qui font aussi du support asynchrone (email, tickets différés) ? Si oui, leur ratio SLA serait mécaniquement défavorable sur ces canaux.

---

### Section 4 — Évolution sur 8 semaines

Deux graphes en ligne superposés, partageant le même axe X (semaines).

1. **Volume de conversations** — permet de détecter des tendances (croissance, saisonnalité).
2. **CSAT moyen** — permet de corréler la qualité avec la charge.

**Source SQL** : `mart_weekly_kpis` avec les 8 dernières semaines.

---

## Questions que je poserais à Lorette

1. **Fuseau horaire** : les timestamps Intercom sont en UTC. Ton équipe travaille-t-elle en heure de Paris (UTC+1/UTC+2) ? Il faudrait convertir avec `CONVERT_TIMEZONE('Europe/Paris', ...)` pour que le heatmap reflète les vraies heures locales.

2. **Périmètre du SLA** : le seuil de 5 min s'applique-t-il uniquement pendant les **heures ouvrées** (ex. lun-ven 9h-18h) ? Une conversation ouverte à 23h ne peut pas être traitée en 5 min. Si oui, je calculerai le délai hors horaires en ajoutant une table de calendrier.

3. **Réassignation** : si une conversation est d'abord assignée à Héloise, puis à Patrick, à qui est-elle créditée ? Ce modèle utilise l'**assignee final**. Si tu veux attribuer la performance à chaque agent ayant traité la conv, il faudra exploiter les `conversation_parts` de type `assignment`.

4. **Bots** : les bots Intercom envoient parfois une réponse automatique instantanée. Doit-on compter cette réponse dans le SLA, ou seulement la **première réponse humaine** ? J'ai choisi de les exclure pour mesurer la réactivité humaine réelle.

5. **Conversations "prioritaires"** : le champ `PRIORITY = 'priority'` existe. Y a-t-il un SLA différent (ex. < 2 min) pour ces conversations ? Si oui, on peut ajouter une ligne dédiée dans le header.

6. **Échelle CSAT** : Intercom propose des émojis (Awful=1 … Amazing=5). Est-ce bien l'échelle utilisée chez Skello, ou s'agit-il d'un pouce haut/bas (binaire) ? La réponse change l'interprétation de la moyenne.

7. **Conversations sans réponse** : certaines conversations peuvent être fermées sans jamais avoir reçu de réponse admin (ex. client qui se répond lui-même). Faut-il les inclure dans le SLA comme des "échecs" ou les écarter ?
