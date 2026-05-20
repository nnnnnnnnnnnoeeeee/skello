# Guide entretien — Explication du dashboard (5 onglets)

Ce guide explique chaque section du dashboard pour que tu puisses tout présenter à Lorette ou Delphine sans hésiter.

---

## Structure générale

Le dashboard est organisé en **5 onglets** qui répondent chacun à une question précise :

| Onglet | Question |
|---|---|
| **Équipe** | Comment s'est passée la semaine globalement ? |
| **Individuel** | Qui a fait quoi ? Qui progresse, qui décroche ? |
| **Volume & horaires** | Quand est-ce qu'on est le plus sollicité ? |
| **Thèmes** | Sur quels sujets est-ce qu'on reçoit le plus ? |
| **Modèle** | Comment les données sont-elles construites ? |

**Navigation :** boutons `←` `→` ou touches clavier pour changer de semaine. Le dashboard affiche toujours la dernière semaine disponible par défaut.

---

## En-tête — présent sur tous les onglets

### Auto-insights (bandeau coloré)

3 messages générés automatiquement depuis les données. Ils changent chaque semaine.

**Exemples dans la capture :**
- 🔴 *"Volume en hausse de 96% vs S-1 (135 conversations) — prévoir une charge accrue."*
- ✅ *"Excellent CSAT à 86% — au-dessus des 70% d'objectif. Bonne semaine qualité."*
- 🟠 *"Seulement 25% des conversations traitées en < 5 min — FRT médian de 12.9 min."*

**Comment ils sont calculés :**
- Volume : si variation > +10% vs semaine précédente → alerte charge
- CSAT : si ≥ 78% → message positif / si < 68% → alerte
- FRT : si < 38% de SLA respectée → alerte prioritaire

**Ce que tu dis à l'oral :**
> *"Ces insights sont générés automatiquement. Lorette n'a pas à chercher ce qui s'est passé — le dashboard lui dit directement ce qui mérite son attention avant le meeting."*

---

## Onglet 1 — ÉQUIPE

### Section : KPIs de la semaine (5 cartes)

**Carte 1 — Conversations**
- Valeur : nombre total de conversations assignées à l'équipe cette semaine
- Sous-titre : "dont X prioritaires" (PRIORITY = 'priority' dans les données)
- Δ : variation vs semaine précédente en nombre absolu

**Carte 2 — CSAT positif %**
- Valeur : % de notes ≥ 4 sur 5 parmi les conversations évaluées
- Sous-titre : "sur X évaluées" (rappel : seulement 35% des clients notent)
- Couleur : vert si ≥ 75%, orange si ≥ 65%, rouge sinon
- Barre de progression sous le chiffre

**Carte 3 — FRT < 5 min**
- Valeur : % de conversations avec première réponse humaine en moins de 5 minutes
- Dénominateur = conversations ayant reçu une réponse (pas toutes)
- Couleur : vert si ≥ 45%, orange si ≥ 35%, rouge sinon
- Barre de progression sous le chiffre

**Carte 4 — Score CSAT moyen**
- Valeur : moyenne des notes sur 5
- Affiché avec des étoiles (★★★★☆ = 4/5)
- Couleur : vert si ≥ 4.2, orange si ≥ 3.9, rouge sinon

**Carte 5 — Taux d'évaluation CSAT**
- Valeur : % de conversations qui ont reçu une note
- Sous-titre : "X / Y convs"
- **Pourquoi cette carte ?** Si ce taux tombe à 10%, les résultats CSAT ne sont plus fiables statistiquement. C'est un indicateur de fiabilité du reporting lui-même.

**Ce que tu dis à l'oral :**
> *"J'ai ajouté le taux d'évaluation CSAT parce que 83% de satisfaction calculé sur 10% des conversations n'a pas la même valeur que sur 50%. C'est un indicateur de confiance dans les autres métriques."*

---

### Section : Points d'attention

Alertes contextuelles qui se déclenchent selon des seuils :

| Condition | Message |
|---|---|
| CSAT positif < 70% | ⚠️ "En dessous de l'objectif de 70% — identifier les 1 et 2 étoiles" |
| FRT < 5min < 40% | ⏱️ "En dessous de l'objectif de 40% — FRT médian de X min" |
| FRT médian > 8 min | 🐢 "FRT médian élevé : X min. Cible < 5 min" |
| Conversations prio > 18 | 🔴 "X conversations prioritaires — vérifier leur prise en charge" |
| Tout est bon | ✅ "Tous les indicateurs dans les normes cette semaine" |

**Ce que tu dis à l'oral :**
> *"Les points d'attention sont ce que Lorette annonce en ouverture de meeting. En 30 secondes, elle sait quoi adresser avec son équipe."*

---

### Section : Distribution CSAT & Évolution FRT

**Graphique gauche — Distribution des notes CSAT (barres)**
- 5 barres de couleur : rouge (1★), orange (2★), gris (3★), vert (4★), violet (5★)
- Hauteur proportionnelle au nombre de notes
- % affiché sous chaque barre
- Badge "X% positives" en haut à droite
- Légende : "X notes positives (≥ 4★) sur Y · score moyen : Z/5"

**Pourquoi cette vue ?**
> *"Le CSAT positif % est une moyenne. Mais 80% de positif avec beaucoup de 4★ n'est pas pareil qu'avec beaucoup de 5★. La distribution montre si les clients sont 'satisfaits' ou 'enchantés'."*

**Graphique droit — FRT médian (courbe)**
- Courbe violette = FRT médian en minutes sur les 8 dernières semaines
- Ligne rouge pointillée = objectif 5 min
- Point plus gros sur la semaine courante
- Permet de voir si le FRT s'améliore ou se dégrade dans le temps

---

### Section : Évolution sur 8 semaines

**Graphique gauche — Volume de conversations**
- Courbe violette, 8 dernières semaines
- Permet de détecter la saisonnalité (ex : chute à Noël visible dans les données)

**Graphique droit — CSAT positif %**
- Courbe verte + ligne orange pointillée à 70% (objectif)
- Permet de voir si la qualité se maintient quand le volume monte

**Ce que tu dis à l'oral :**
> *"Ces deux graphiques ensemble permettent de voir si la hausse de volume impacte la qualité. Si les deux montent en même temps, l'équipe performe bien. Si le CSAT baisse quand le volume monte, c'est un signal de tension."*

---

## Onglet 2 — INDIVIDUEL

### Tableau agents (Performance par agent — semaine vs S-1)

Colonnes : Agent · Conv. · Δ · CSAT pos. · Δ · Score · Δ · FRT <5min · Δ · FRT méd.

**Les Δ (deltas)** : variation vs semaine précédente
- Vert = amélioration
- Rouge = dégradation
- `=` = stable (variation < 0.5)

**Les badges colorés** (CSAT pos. et FRT <5min) :
- Vert si au-dessus du seuil bon
- Orange si dans la zone de vigilance
- Rouge si en dessous du seuil d'alerte

**Les `—`** : agent sans données cette semaine (données absentes dans le dataset, pas une mauvaise performance). La ligne est grisée à 45% d'opacité pour le signaler visuellement.

**Ce que tu dis à l'oral :**
> *"Le dataset fourni montre que Justine n'a aucune conversation. J'ai choisi d'afficher `—` plutôt que 0% pour ne pas laisser croire à une mauvaise performance — c'est une donnée manquante, pas un résultat nul. En production, j'aurais vérifié avec Lorette si ces agents sont bien configurés dans Intercom."*

---

### Graphique — Conversations traitées par agent (barres)

Barres colorées par agent (violet, vert, orange, rouge).
Permet de voir en un coup d'œil la répartition de charge.

---

### Graphique — FRT médian par agent (barres + ligne objectif)

Barres colorées selon le FRT :
- Vert si FRT ≤ 5 min
- Orange si FRT entre 5 et 8 min
- Rouge si FRT > 8 min

Ligne rouge pointillée = objectif 5 min.

**Ce que tu dis à l'oral :**
> *"Ce graphique permet à Lorette d'identifier rapidement quel agent a des difficultés à répondre rapidement — et d'aller voir avec lui ce qui se passe."*

---

## Onglet 3 — VOLUME & HORAIRES

### Graphique — Volume par jour de semaine (barres)

Agrégé sur toutes les semaines du dataset.
- Barres violettes = jours de semaine
- Barres gris clair = samedi et dimanche

Répond à la question : *"Quel est le jour le plus chargé ?"*

---

### Heatmap — Heure d'arrivée des conversations

Grille **7 jours × 12 heures** (7h à 18h).
Couleur = volume relatif de conversations (du violet très clair = peu, au violet foncé = beaucoup).

- Légende de couleur en bas
- Valeur numérique dans chaque cellule
- Tooltip au survol : "Lundi 9h : 94 conversations"
- Pic calculé dynamiquement depuis les vraies données

**Ce que tu dis à l'oral :**
> *"C'est l'outil de planning de Lorette. Si le pic est lundi 9h–11h, elle s'assure que toute l'équipe est disponible à ce moment. Si une personne est en congé ce créneau, elle peut anticiper et réorganiser."*

**Note technique à mentionner si on te demande :**
> *"Les timestamps sont en UTC. En production, il faudrait convertir en heure de Paris avec `CONVERT_TIMEZONE('Europe/Paris', ...)` pour que les horaires reflètent la réalité vécue par l'équipe."*

---

## Onglet 4 — THÈMES

### Liste — Top 5 tags de la semaine

Chaque tag affiché avec :
- Nom du tag (ex : Badgeuse, Équipes, Permissions...)
- Nombre de conversations tagguées cette semaine
- Δ vs semaine précédente (ex : +12, -3)
- Barre de proportion visuelle

**D'où viennent les tags ?**
Le champ `TAGS` dans `CONVERSATIONS` est un JSON : `[{"name": "Badgeuse"}, {"name": "Équipes"}]`. On l'a dénormalisé (LATERAL FLATTEN en SQL) pour avoir une ligne par tag.

**Ce que tu dis à l'oral :**
> *"Les tags sont posés automatiquement par Intercom lors du routage. Ils permettent à Lorette de savoir sur quels sujets son équipe est la plus sollicitée. Si 'Badgeuse' explose cette semaine, c'est peut-être qu'il y a un bug produit ou une communication à faire."*

---

### Graphique — Évolution des 3 principaux thèmes (courbes)

3 courbes sur 8 semaines, une par tag dominant.
Permet de voir si un sujet monte, descend ou reste stable dans le temps.

---

## Onglet 5 — MODÈLE

Onglet de transparence sur la construction des données. Contient :

### Architecture SQL
- Couche Staging (STG_CONVERSATIONS, STG_CONVERSATION_PARTS, STG_CONVERSATION_TAGS)
- Couche Marts (FACT_CONVERSATIONS, AGG_WEEKLY_TEAM, AGG_WEEKLY_AGENT, AGG_HOURLY_VOLUME, AGG_TAGS_WEEKLY, AGG_CSAT_DISTRIBUTION)

### Choix de modélisation
- **FRT** = 1er message client → 1re réponse admin humaine (bots exclus)
- **CSAT positif** = note ≥ 4 sur 5
- **Déduplication ETL** via QUALIFY ROW_NUMBER
- **Dénominateur SLA** = conversations avec réponse

### Questions pour Lorette
6 questions ouvertes listées directement dans le dashboard.

**Ce que tu dis à l'oral :**
> *"J'ai ajouté cet onglet pour être transparent sur les choix que j'ai faits. Lorette peut voir exactement comment les métriques sont calculées et valider ou corriger mes hypothèses. C'est important pour qu'elle fasse confiance aux chiffres."*

---

## Résumé — Ce que tu retiens pour présenter le dashboard

### L'accroche en 30 secondes

> *"Le dashboard est organisé pour le meeting du lundi matin de Lorette. L'onglet Équipe lui donne les KPIs globaux avec les alertes automatiques — elle sait en 30 secondes quoi adresser. L'onglet Individuel lui permet de voir qui a eu une bonne ou mauvaise semaine avec le delta vs S-1. L'onglet Volume lui sert pour le planning. Les Thèmes pour identifier les sujets récurrents. Et l'onglet Modèle pour montrer comment c'est construit et quelles questions restent ouvertes."*

### Les 5 choix de design à justifier

| Choix | Justification |
|---|---|
| Auto-insights générés automatiquement | Lorette ne doit pas chercher — le dashboard lui dit quoi regarder |
| 5 KPIs et pas 15 | Un meeting de 30 min ne peut pas couvrir 15 métriques |
| Δ vs S-1 partout | La valeur absolue ne suffit pas — la tendance est ce qui compte |
| Badges verts/orange/rouge | Lecture en 5 secondes sans calculer |
| Onglet Modèle | Transparence sur les choix — Lorette doit faire confiance aux chiffres |
