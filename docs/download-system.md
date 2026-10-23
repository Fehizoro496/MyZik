# Système de téléchargement — conception

État : proposition. `DiscoverScreen` possède désormais une première version
autonome : recherche YouTube avec `youtube_explode_dart`, lecture immédiate du
meilleur flux audio avec `just_audio`, et téléchargement pour l'écoute hors ligne
(`downloadsProvider`). Cette version écrit dans le dossier privé de l'app, sans
MediaStore ni écriture de tags : les titres téléchargés sont fusionnés dans
`libraryProvider` par l'app elle-même. Le présent document décrit toujours le
système complet visé (sources multiples, `Music/` public, tags, paroles).

## 1. Périmètre

Objectif : depuis l'app, trouver un morceau, le télécharger dans la meilleure
qualité disponible, l'obtenir correctement tagué dans la bibliothèque locale, avec
ses paroles.

Le système doit rester agnostique de la source. Chaque source est une
implémentation de `TrackSearchRepository` ; en ajouter une ne touche aucun autre
fichier. C'est le même parti pris que `MusicRepository` pour la lecture locale.

Hors périmètre : toute source exigeant de contourner un chiffrement, un DRM ou
les CGU d'un service de streaming. Ces catalogues ne servent pas de fichiers, et
une app qui les extrait est refusée par les stores.

## 2. Flux utilisateur

Trois entrées possibles, un seul pipeline derrière :

1. **Recherche libre** — c'est ce que la maquette montre déjà : un champ, une liste
   de résultats, un bouton de téléchargement par ligne.
2. **Lien collé** — l'utilisateur colle une URL de playlist ou d'album
   (Spotify, Deezer, Apple Music). L'app lit la *liste des titres* via l'API
   officielle du service, puis résout chaque titre auprès des sources autorisées
   et de la bibliothèque locale. C'est l'ergonomie « je pars de ma playlist » sans
   toucher à l'audio du service.
3. **Import local** — un dossier, un partage WebDAV, un NAS. Pas de réseau tiers.

Puis, pour chaque piste : choix de la qualité → mise en file → progression →
écriture du fichier → tags → apparition dans « My Music ».

## 3. Modèles (`lib/models.dart`)

```dart
/// Une piste trouvée sur une source distante. Ne devient un `Song` qu'après
/// insertion en bibliothèque : `Song.id` est un id MediaStore, attribué à
/// l'écriture, alors qu'une source distante a un id textuel.
class RemoteTrack {
  final String sourceId;       // identifiant de la source ('archive', 'jamendo')
  final String id;             // id chez la source
  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final List<TrackQuality> qualities;
  final String? artworkUrl;
  final String license;        // affiché avant téléchargement
}

/// Un format disponible pour une piste. `bitrate` est nul pour un format sans
/// perte, où seuls comptent la profondeur et l'échantillonnage.
class TrackQuality {
  final String format;         // 'flac', 'mp3', 'ogg'
  final int? bitrate;          // kbps, si avec perte
  final int? sampleRate;       // Hz
  final int? bytes;            // taille annoncée, pour l'estimation
  final Uri url;
  bool get isLossless => format == 'flac' || format == 'alac';
}

/// Paroles, synchronisées ou non. `lines` est vide quand seul le texte brut
/// existe ; `plain` est toujours renseigné.
class Lyrics {
  final String plain;
  final List<LyricLine> lines; // (Duration offset, String text)
  bool get isSynced => lines.isNotEmpty;
}
```

## 4. Couche data (`lib/data/`)

```dart
/// Recherche de pistes sur une source. Une implémentation par source.
abstract class TrackSearchRepository {
  String get sourceId;
  String get displayName;

  /// Vrai si la source est utilisable (clé API présente, réseau, etc.).
  bool get isAvailable;

  Future<List<RemoteTrack>> search(String query, {int limit = 30});

  /// Détail d'une piste, quand la recherche ne renvoie pas tous les formats.
  Future<RemoteTrack> resolve(String id);
}

/// Paroles. L'implémentation réseau est doublée d'un cache disque et de la
/// lecture des `.lrc` posés à côté des fichiers audio.
abstract class LyricsRepository {
  Future<Lyrics?> fetchFor({
    required String title,
    required String artist,
    Duration? duration,
  });
}

/// Écriture du fichier téléchargé et publication en bibliothèque.
abstract class DownloadStore {
  /// Destination effective, selon le réglage public/privé.
  Future<Uri> targetFor(RemoteTrack track, TrackQuality quality);

  /// Insère le fichier dans MediaStore et renvoie l'id attribué, qui devient
  /// le `Song.id`. Renvoie null sur les plateformes sans MediaStore.
  Future<int?> publish(Uri file, RemoteTrack track);
}
```

Implémentations prévues : `ArchiveSearchRepository` (Internet Archive — la seule
source de la liste qui serve du FLAC), `JamendoSearchRepository` (clé gratuite,
MP3/OGG), `LrclibLyricsRepository` (paroles synchronisées, sans clé),
`LocalLrcLyricsRepository` (fichiers `.lrc` locaux, aucun réseau).

## 5. Pipeline de téléchargement

Une tâche traverse les états `queued → downloading → writingTags → publishing →
done`, avec `failed` et `canceled` en sortie possible à chaque étape.

1. **Résolution** — la qualité choisie donne une URL directe.
2. **Transfert** — délégué à `background_downloader` : progression, reprise après
   coupure, notification système, poursuite quand l'app passe en arrière-plan.
   À écrire d'abord dans un fichier temporaire, jamais à la destination finale :
   un transfert interrompu ne doit pas laisser un fichier tronqué dans la
   bibliothèque.
3. **Tags** — voir §7.
4. **Publication** — déplacement vers la destination puis insertion MediaStore.
5. **Rafraîchissement** — `ref.invalidate(libraryProvider)`.

L'état de la file est persisté (`shared_preferences` suffit : une liste de tâches
sérialisées), sinon un redémarrage pendant un téléchargement perd la trace du
fichier temporaire.

## 6. Stockage — le point délicat sur Android

Deux destinations possibles, avec des conséquences visibles pour l'utilisateur :

| | `Music/` public (MediaStore) | Dossier privé de l'app |
|---|---|---|
| Visible par les autres apps | oui | non |
| Survit à la désinstallation | oui | non |
| Écriture | via MediaStore (`RELATIVE_PATH` + `insert`) | chemin direct |
| Permission | aucune sur API 29+ | aucune |
| Repris par `on_audio_query` | oui, automatiquement | non |

Sur API 29+, écrire dans `Music/` par un chemin direct ne fonctionne pas : il faut
passer par MediaStore. C'est aussi ce qui fait apparaître le morceau dans
`on_audio_query`, donc dans « My Music », la recherche et les playlists — sans
aucun code supplémentaire. **Destination recommandée : `Music/MyZik/`.**

À nettoyer au passage : `requestLegacyExternalStorage="true"` dans
`AndroidManifest.xml` n'a plus d'effet depuis API 30.

## 7. Métadonnées et pochettes

MediaStore accepte les valeurs fournies à l'insertion, mais un rescan relit les
tags du *fichier*. Sans tags écrits dans le fichier, un morceau correctement
affiché aujourd'hui redevient « Unknown » après un rescan.

Il faut donc écrire les tags (ID3v2 pour MP3, Vorbis comments pour FLAC) : titre,
artiste, album, numéro de piste, pochette intégrée. Peu de packages Dart le font
correctement en *écriture* — c'est un point à valider tôt, quitte à passer par un
canal de plateforme. À vérifier avant de s'engager sur le reste.

## 8. Paroles

`LrclibLyricsRepository` interroge LRCLIB par titre + artiste + durée (la durée
lève la plupart des ambiguïtés entre versions). Réponse en LRC synchronisé quand
elle existe, texte brut sinon.

Côté affichage, `_lyrics()` dans `now_playing_screen.dart` montre aujourd'hui
quatre lignes figées. Avec des paroles synchronisées, la ligne courante se déduit
de `playback.position` — déjà exposée par `playbackProvider` — et la mise en forme
existante (ligne centrale en évidence, voisines atténuées) fonctionne telle quelle.

Un cache disque est nécessaire : les paroles ne changent pas, et une requête à
chaque ouverture de l'écran est inutile. À stocker à côté du fichier audio en
`.lrc`, ce qui les rend lisibles par les autres lecteurs.

Note : les paroles restent sous droit d'auteur indépendamment de la licence de
l'enregistrement. Pour un usage personnel c'est sans enjeu ; pour une publication
sur un store, la source doit être licenciée.

## 9. Providers (`lib/providers/`)

```
downloadProvider     file d'attente + progression ; expose Map<String, DownloadTask>
searchSourceProvider source active + disponibilité
remoteSearchProvider résultats de recherche (family sur la requête, debouncé)
lyricsProvider       paroles du morceau courant (family sur Song)
```

`DiscoverScreen` perd `_catalog`, `_OnlineTrack` et son `Future.delayed`, et lit
`remoteSearchProvider` / `downloadProvider`. Sa structure visuelle est conservée :
`_downloadButton` a déjà les trois états `idle` / `downloading` / `done`, il ne lui
manque qu'une progression réelle en pourcentage.

## 10. Permissions et manifest

`INTERNET` n'est déclarée que dans `android/app/src/debug/AndroidManifest.xml`,
où le tooling Flutter l'a mise pour le hot reload. **Elle est absente du manifest
`main/`** : sans l'y ajouter, tout fonctionne en debug et échoue en release.

`background_downloader` demande `POST_NOTIFICATIONS` pour ses notifications de
progression (API 33+), à solliciter au premier téléchargement et non au démarrage.

Attention aussi au foreground service : `audio_service` en occupe déjà un de type
`mediaPlayback`. Le téléchargement doit garder le sien, distinct.

## 11. Dépendances à ajouter

```yaml
http: ^1.2.0                  # appels API
background_downloader: ^8.5.0 # transfert, reprise, progression, notifications
path_provider: ^2.1.4         # dossiers temporaires et privés
```

Plus, selon la validation du §7, un mécanisme d'écriture de tags.

## 12. Tests

La suite actuelle (21 tests) n'utilise aucun réseau, et ça doit rester vrai :
`TrackSearchRepository` et `LyricsRepository` sont injectés par override Riverpod,
comme `MusicRepository` l'est déjà.

À couvrir : parsing des réponses de chaque source ; sélection de la meilleure
qualité (dont le cas sans format sans perte) ; parsing LRC, y compris horodatages
malformés et lignes vides ; transitions d'états d'une tâche, avec échec et
annulation ; absence de fichier tronqué publié après interruption.

## 13. Ordre de mise en œuvre

1. **Paroles** — LRCLIB + affichage synchronisé. Autonome, sans clé API, sans
   écriture de fichier : le gain visible le plus rapide, et ça ne dépend d'aucune
   décision sur la source audio.
2. **Validation de l'écriture de tags** (§7). Point de risque : à lever avant
   d'écrire le reste.
3. **`DownloadStore` + MediaStore**, avec une URL de test en dur. Valide le
   maillon délicat, sans recherche.
4. **Pipeline et file d'attente**, branchés sur `DiscoverScreen`.
5. **Première source réelle** (Internet Archive), puis les suivantes.
6. **Import par lien de playlist** (§2.2).

Les étapes 1 à 4 sont indépendantes de la source : elles peuvent être écrites et
testées avant toute décision à ce sujet.
