# MyZik

Application Flutter de lecteur musical (design Music Player).

## Convention de commit

Les messages de commit suivent la spécification [Conventional Commits](https://www.conventionalcommits.org/) :

```
<type>(<scope>): <description>
```

- **type** — nature du changement (voir la liste ci-dessous).
- **scope** — zone du code touchée, entre parenthèses (ex. `home`, `player`, `config`). Optionnel mais recommandé.
- **description** — résumé court à l'impératif, en minuscule, sans point final.

### Types autorisés

| Type       | Utilisation                                                        |
| ---------- | ------------------------------------------------------------------ |
| `feat`     | Nouvelle fonctionnalité                                            |
| `fix`      | Correction de bug                                                  |
| `chore`    | Outillage, config, dépendances (rien de fonctionnel ni de code UI) |
| `refactor` | Réécriture sans changement de comportement                        |
| `style`    | Formatage, indentation, whitespace (aucune logique modifiée)      |
| `docs`     | Documentation uniquement                                           |
| `test`     | Ajout ou modification de tests                                     |
| `perf`     | Amélioration des performances                                     |
| `build`    | Système de build ou dépendances externes                          |
| `ci`       | Configuration d'intégration continue                              |

### Exemples

```
feat(home): ajoute la barre de navigation en verre dépoli
fix(home): rogne le circle avatar en cercle avec backgroundImage
chore(config): configure FVM pour la gestion de version Flutter
refactor(player): extrait la logique de lecture dans PlayerController
docs: documente la convention de commit dans CLAUDE.md
```

### Règles

- Un commit = un changement logique cohérent.
- La description est en français, à l'impératif présent (« ajoute », « corrige », pas « ajouté »/« ajoutant »).
- Pas de majuscule en début de description, pas de point final.
- Pour un changement cassant, ajouter `!` après le scope : `feat(player)!: change la signature de playTrack`.
- Ne pas mentionner Claude dans les messages de commit (pas de trailer `Co-Authored-By: Claude`, pas de mention d'outil).
