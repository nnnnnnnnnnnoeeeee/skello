# Comprendre le CSAT — Guide de référence

## Définition

Le **CSAT (Customer Satisfaction Score)** mesure la satisfaction d'un client après une interaction précise : un appel au support, la résolution d'un ticket, l'utilisation d'une fonctionnalité.

> Dans le projet Skello : c'est la note laissée par un client à la fin d'une conversation Intercom avec l'équipe Support.

---

## Comment ça fonctionne

On pose une question directe après l'interaction :

> *"Comment évaluez-vous votre satisfaction concernant cette conversation ?"*

Le client répond sur une échelle de **1 à 5** :

| Note | Signification |
|------|--------------|
| 1 | Très insatisfait |
| 2 | Insatisfait |
| 3 | Neutre |
| 4 | Satisfait |
| 5 | Très satisfait |

---

## Le calcul

Le CSAT positif % ne compte que les notes **4 et 5** (les "Top Box") — les notes 1 à 3 sont exclues du numérateur.

```
CSAT positif % = (Nombre de notes 4 ou 5 / Nombre total de réponses) × 100
```

**Exemple :** 75 notes ≥ 4 sur 100 réponses → CSAT = **75%**

Dans le dashboard Skello, l'objectif est fixé à **70%**. En dessous → badge orange/rouge.

---

## Ce que le projet calcule exactement

Deux métriques CSAT distinctes apparaissent dans le dashboard :

### 1. CSAT positif % (carte KPI + tableau agents)
```sql
100.0 * COUNT(CASE WHEN csat_rating >= 4 THEN 1 END)
      / COUNT(csat_rating)
```
→ Pourcentage de conversations notées 4 ou 5 parmi celles qui ont reçu une note.

### 2. Score CSAT moyen (carte KPI + tableau agents)
```sql
AVG(csat_rating)
```
→ Moyenne arithmétique de toutes les notes reçues (de 1 à 5). Affiché avec les étoiles ★.

> **Pourquoi les deux ?** Le pourcentage positif est l'objectif opérationnel (passer le seuil de 70%). La moyenne donne plus de nuance : 80% de positif avec beaucoup de 4★ n'est pas pareil qu'avec beaucoup de 5★.

---

## Taux d'évaluation — le piège à éviter

Toutes les conversations ne reçoivent pas de note. Dans les données Skello, le taux d'évaluation tourne autour de **30 à 40%** selon les semaines.

Le dashboard l'affiche dans la carte "Taux d'éval. CSAT". Si ce taux est faible (< 15%), les résultats CSAT sont à interpréter avec prudence — une alerte automatique le signale.

**Dénominateur correct :**
```sql
-- ✅ Sur les conversations évaluées uniquement
COUNT(CASE WHEN csat_rating >= 4 THEN 1 END) / COUNT(csat_rating)

-- ❌ Sur toutes les conversations (fausserait le score à la baisse)
COUNT(CASE WHEN csat_rating >= 4 THEN 1 END) / COUNT(*)
```

---

## Avantages et limites

**Avantages**
- Indicateur instantané, facile à comprendre et à communiquer
- Détecte immédiatement si une semaine ou un agent a eu des difficultés
- Granularité par agent → permet d'identifier qui a besoin d'accompagnement

**Limites**
- Mesure une réaction à court terme sur une interaction précise
- Un client peut être satisfait du support mais insatisfait du produit — le CSAT ne le verra pas
- Biais de sélection : les clients très satisfaits ou très mécontents répondent plus souvent
- Non comparable entre entreprises (les seuils culturels varient)

---

## CSAT vs NPS — quelle différence ?

| | CSAT | NPS |
|---|---|---|
| Question | "Êtes-vous satisfait de cette interaction ?" | "Recommanderiez-vous ce produit à quelqu'un ?" |
| Échelle | 1 à 5 | 0 à 10 |
| Ce que ça mesure | Satisfaction immédiate, ponctuelle | Fidélité et intention de recommandation à long terme |
| Fréquence | Après chaque interaction | Périodique (tous les trimestres) |
| Limite | Court terme | Ne capte pas les frictions spécifiques |

> Dans un entretien : *"Le CSAT mesure comment s'est passé l'interaction. Le NPS mesure si le client reste et en parle autour de lui. Les deux sont complémentaires."*

---

## Ce que tu peux dire en entretien

**Si on te demande pourquoi tu as choisi CSAT positif % plutôt que la moyenne brute :**
> *"La moyenne brute est sensible aux notes extrêmes. Un 1★ sur 10 réponses tire la moyenne vers le bas de manière disproportionnée. Le pourcentage positif est plus stable et plus actionnable : l'objectif 70% est clair pour Lorette, pas besoin d'interpréter si 4.1 est bien ou pas."*

**Si on te demande pourquoi l'objectif est à 70% :**
> *"C'est un seuil courant dans le SaaS B2B. Je l'ai posé comme hypothèse de travail — en production, Lorette le calibrerait sur ses données historiques et les benchmarks secteur."*

**Si on te demande comment améliorer le taux de réponse CSAT :**
> *"En déclenchant la demande d'évaluation au bon moment (juste après la résolution), en simplifiant le formulaire, et en formant les agents à clôturer les conversations de manière à encourager la note."*
