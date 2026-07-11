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
feat(home): add frosted glass navigation bar
fix(home): clip circle avatar with backgroundImage
chore(config): configure FVM for Flutter version management
refactor(player): extract playback logic into PlayerController
docs: document commit convention in CLAUDE.md
```

### Règles

- Un commit = un changement logique cohérent.
- Le message de commit est rédigé en anglais, à l'impératif présent (« add », « fix », pas « added »/« adding »).
- Pas de majuscule en début de description, pas de point final.
- Pour un changement cassant, ajouter `!` après le scope : `feat(player)!: change playTrack signature`.
- Ne pas mentionner Claude dans les messages de commit (pas de trailer `Co-Authored-By: Claude`, pas de mention d'outil).
