# Pitch de présentation — Entretien Skello

> Ce document suit exactement les 5 critères d'évaluation de la consigne.
> Pour chaque critère : ce que tu montres, ce que tu dis, ce qu'on peut te demander.

---

## 0. Ouverture (30 secondes)

> *"Avant de montrer le dashboard, je veux expliquer comment j'ai abordé le sujet.*
>
> *La consigne dit que Lorette n'a pas de visibilité sur ses métriques et qu'elle anime un meeting le lundi matin. J'ai pris ça comme contrainte principale : le dashboard n'est pas fait pour faire de l'analyse — il est fait pour préparer un meeting de 30 minutes. Ça change complètement ce qu'on met dedans et ce qu'on ne met pas."*

---

## Critère 1 — Rigueur du SQL

**Ce que tu montres** : le fichier `skello_support_data_model.sql` avec ses 9 étapes commentées.

> *"Le modèle est organisé en 9 étapes dans un seul fichier lisible, avec des commentaires qui expliquent le POURQUOI de chaque décision — pas juste le QUOI.*
>
> *Trois points techniques que je veux mettre en avant :*
>
> *Premier point : j'utilise `TRY_PARSE_JSON` partout. Sans le `TRY_`, une seule ligne avec un JSON corrompu fait planter toute la requête. Avec le `TRY_`, la ligne retourne NULL et le reste continue — c'est une protection de robustesse pour un pipeline en production.*
>
> *Deuxième point : le `QUALIFY ROW_NUMBER() OVER (PARTITION BY ID ORDER BY _SDC_EXTRACTED_AT DESC) = 1`. L'ETL — Stitch ou Airbyte — peut re-charger une même conversation en cas d'erreur réseau. Sans cette ligne, on aurait des doublons silencieux qui faussent tous les comptages. J'ai vu dans les colonnes `_SDC_EXTRACTED_AT` que c'était un chargement ETL et j'ai anticipé ce cas.*
>
> *Troisième point : le dénominateur du SLA. Pour calculer le % de FRT < 5 minutes, j'aurais pu diviser par le nombre total de conversations. Ce serait faux — ça pénaliserait l'équipe pour les conversations abandonnées par le client avant toute réponse. Je divise par le nombre de conversations qui ont reçu une réponse."*

**Si on te demande pourquoi tu as fait des vues et pas des tables en staging :**
> *"Le staging n'a pas besoin d'être stocké — c'est juste du nettoyage technique. Une vue est recalculée à la demande. Les marts en revanche sont des tables matérialisées, parce que le BI tool doit lire des données précalculées sans recalculer toute la chaîne à chaque ouverture."*

**Si on te demande pourquoi MEDIAN et pas AVG :**
> *"Sur les vraies données du dataset : médiane 7,4 minutes, moyenne environ 100 minutes. La moyenne est inutilisable — elle est biaisée par les conversations ouvertes la nuit restées sans réponse pendant des heures. La médiane représente l'expérience client typique."*

---

## Critère 2 — Rigueur de la démarche

**Ce que tu montres** : l'architecture en couches, le fait que tu as exploré les données avant de modéliser.

> *"J'ai structuré le modèle en 4 couches inspirées de dbt — seeds, staging, intermediate, marts — parce que chaque couche a une seule responsabilité.*
>
> *Si le périmètre de l'équipe change — un agent arrive ou part — je touche uniquement la table `dim_support_agents`. Tous les marts se mettent à jour automatiquement à la prochaine exécution.*
>
> *Si la définition du FRT change — par exemple si Lorette veut mesurer depuis `CREATED_AT` plutôt que depuis le premier message client — je touche uniquement la couche intermediate. Les KPIs agrégés s'adaptent sans modification.*
>
> *J'ai aussi découvert un écart entre la documentation et les données réelles : la doc Intercom parle de `part_type`, mais la vraie colonne dans les données s'appelle `PART_GROUP`. J'ai vérifié en explorant les CSV avant de coder. Sans ça, tous mes filtres sur les messages auraient retourné zéro résultat."*

**Si on te demande comment tu as validé ton modèle :**
> *"J'ai branché le modèle SQL sur les vrais CSV via Python et Streamlit pour vérifier que les chiffres sortants ont du sens. Par exemple : 2 232 conversations support sur 19 semaines, CSAT moyen à 83%, FRT médian à 7,4 minutes. Ces ordres de grandeur sont cohérents avec ce qu'on attend d'une équipe support SaaS B2B."*

---

## Critère 3 — Sens des enjeux business

**Ce que tu montres** : le dashboard lui-même, onglet par onglet.

> *"Lorette a un meeting de 30 minutes le lundi matin. Son problème n'est pas d'avoir des données — son problème est de savoir quoi dire à son équipe en 5 minutes.*
>
> *J'ai organisé le dashboard pour suivre l'ordre naturel de ce meeting.*
>
> *L'onglet Équipe répond à : 'est-ce que la semaine s'est bien passée globalement ?' — avec trois insights générés automatiquement en haut de page. Lorette n'a pas à chercher : le dashboard lui dit directement ce qui mérite son attention.*
>
> *L'onglet Individuel répond à : 'qui a eu une bonne ou mauvaise semaine ?' — avec les deltas vs S-1 pour voir les tendances, pas juste les valeurs absolues.*
>
> *L'onglet Volume répond à : 'quand est-ce qu'on est le plus sollicité ?' — la heatmap est son outil de planning.*
>
> *L'onglet Thèmes répond à : 'sur quels sujets est-ce qu'on reçoit le plus ?' — si 'Badgeuse' explose, c'est peut-être un bug produit à remonter.*
>
> *Et l'onglet Modèle montre comment tout est construit — pour que Lorette fasse confiance aux chiffres."*

**Si on te demande pourquoi seulement 5 KPIs :**
> *"Un meeting de 30 minutes ne peut pas couvrir 15 métriques. J'ai choisi les 5 qui répondent aux questions que Lorette se pose le lundi matin : est-ce qu'on a eu beaucoup de volume ? Est-ce que les clients sont satisfaits ? Est-ce qu'on répond vite ? Le score moyen est-il bon ? Et est-ce que le taux d'évaluation est assez haut pour que les chiffres CSAT soient fiables ?"*

**Si on te demande pourquoi tu as ajouté le taux d'évaluation CSAT :**
> *"83% de satisfaction calculé sur 10% des conversations n'a pas la même valeur que sur 50%. J'ai ajouté ce KPI parce que c'est un indicateur de confiance dans les autres métriques — si le taux tombe, il faut interpréter le CSAT avec prudence."*

---

## Critère 4 — Dashboard actionnable et clair

**Ce que tu montres** : la navigation semaine par semaine, les alertes contextuelles, les deltas.

> *"Trois choix de design que je veux justifier.*
>
> *Les deltas partout : la valeur absolue ne suffit pas. 80% de CSAT, c'est bien ou c'est mal ? On ne sait pas sans contexte. Le delta vs S-1 donne la tendance — et la tendance, c'est ce qui se discute en meeting.*
>
> *Les badges verts, orange, rouges : Lorette doit pouvoir lire le tableau des agents en 5 secondes, sans calculer. Le code couleur fait ça.*
>
> *Les insights automatiques en haut : Lorette n'a pas à parcourir tout le dashboard pour trouver ce qui s'est passé. Le dashboard lui dit lui-même les trois points importants de la semaine.*
>
> *Et j'ai affiché `—` pour les agents sans données plutôt que 0% — parce que 0% peut laisser croire à une mauvaise performance alors que c'est juste une donnée absente."*

---

## Critère 5 — Prise d'initiative

**Ce que tu montres** : tout ce qui n'était pas demandé explicitement.

> *"La consigne listait quatre métriques. J'en ai ajouté plusieurs qui me semblaient utiles sans être demandées.*
>
> *Le taux d'évaluation CSAT — pour mesurer la fiabilité statistique des résultats.*
>
> *La distribution CSAT barre par barre — parce que 80% de positif avec des 4 étoiles n'est pas pareil qu'avec des 5 étoiles.*
>
> *Les insights automatiques — pour que Lorette n'ait pas à analyser : le dashboard analyse pour elle.*
>
> *L'onglet Modèle avec les questions ouvertes — pour être transparent sur mes hypothèses et montrer que je sais ce que je ne sais pas.*
>
> *J'ai aussi branché le modèle sur les vraies données via Streamlit plutôt que de livrer juste du SQL — pour que le rendu soit concret et testable."*

---

## Si on te demande ce que tu ferais différemment en production

> *"Quatre choses.*
>
> *Un : connecter directement à Snowflake — plus besoin de CSV, les données sont en temps réel.*
>
> *Deux : convertir les timestamps UTC en heure de Paris avec `CONVERT_TIMEZONE('UTC', 'Europe/Paris', created_at)` — là les horaires dans la heatmap ne reflètent pas la réalité vécue par l'équipe.*
>
> *Trois : valider les seuils SLA avec Lorette avant de les fixer dans le code. J'ai utilisé 5 minutes parce que c'est mentionné dans la consigne, mais est-ce que ça s'applique hors heures ouvrées ? Est-ce qu'il y a une SLA différente pour les conversations prioritaires ?*
>
> *Quatre : ajouter une couche dbt pour gérer les dépendances entre modèles et automatiser les tests de qualité — par exemple vérifier qu'il n'y a pas de FRT négatif ou de CSAT en dehors de la plage 1–5."*

---

## Questions à poser à la fin

Ces questions montrent que tu penses comme un Data Analyst, pas juste comme quelqu'un qui exécute une consigne :

1. *"Est-ce que la SLA de 5 minutes est officiellement définie quelque part, ou c'est une hypothèse de l'équipe ?"*
2. *"Justine et Patrick ont très peu de conversations dans le dataset — est-ce un problème de configuration Intercom ou c'est représentatif ?"*
3. *"Est-ce que les conversations réouvertes doivent être comptées dans la semaine de réouverture ou la semaine d'origine ?"*
4. *"Lorette préfère comparer vs la semaine précédente ou vs un objectif fixe sur l'année ?"*

---

## Les 4 chiffres à savoir par cœur

| Métrique | Valeur réelle |
|---|---|
| Conversations support analysées | **2 232** sur 19 semaines |
| CSAT positif moyen | **83,3%** |
| FRT médian | **7,4 min** (moyenne : ~100 min — inutilisable) |
| SLA respectée (< 5 min) | **35%** |
