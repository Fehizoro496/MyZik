# Roadmap — version desktop et synchronisation

Objectif : une app Windows complète (lecteur + studio de paroles) pour éditer et
synchroniser les paroles plus confortablement qu'au téléphone, et une
synchronisation des données entre le desktop et le mobile sur le réseau local.

Décisions prises :

- **Plateforme desktop** : Windows (macOS/Linux possibles plus tard, même code).
- **Périmètre desktop** : lecteur complet + studio de paroles.
- **Transport de la synchro** : réseau local Wi-Fi, sans compte ni cloud.
- **Données synchronisées** : paroles, likes, playlists et fichiers audio.

Chaque phase se termine par `fvm flutter analyze` propre, des tests, et un ou
plusieurs commits au format Conventional Commits.

---

## Phase 0 — Faire tourner l'app sur Windows

Aujourd'hui le desktop affiche l'app mobile dans un cadre de téléphone
(`PlayerShell`) avec une bibliothèque d'exemple.

- [x] Backend audio Windows : ajouter `just_audio_media_kit` (just_audio n'a pas
      d'implémentation Windows).
- [x] N'initialiser `AudioService` que sur Android/iOS ; handler no-op sur
      desktop (les contrôles média de l'OS viendront plus tard).
- [x] Taille et titre de fenêtre par défaut, taille minimale.
- [x] Vérifier `background_downloader` et `youtube_explode_dart` sous Windows
      (recherche, streaming, téléchargement).
- [x] Vérifier le cache des paroles et Whisper (`Song.filePath`) sous Windows.

La compilation Windows et la suite de tests passent ; la compatibilité Windows
des deux plugins est confirmée. Les appels YouTube réels n'ont pas été testés
contre le service en ligne.

## Phase 1 — Identité stable des morceaux

Prérequis de toute la synchro : les likes, playlists et paroles sont indexés par
`Song.id`, un id MediaStore propre à chaque appareil.

- [x] Introduire `SongKey` :
  - `yt:<videoId>` pour les morceaux YouTube (streamés ou téléchargés) ;
  - `fp:<hash>` pour les fichiers locaux — taille + SHA-1 des premiers et
    derniers 64 Ko, rapide et identique pour un fichier copié tel quel.
- [x] Correspondance de secours artiste + titre + durée (normalisés) pour
      retrouver des paroles quand les fichiers diffèrent.
- [x] Calcul et cache des empreintes (ne pas relire les fichiers à chaque
      lancement).
- [x] Migration automatique : likes, playlists et cache des paroles passent
      de `Song.id` à `SongKey`.
  - `Song.songKey` (`yt:`, `fp:` ou `meta:`) est la clé lue partout par
    l'interface ; `LikedNotifier` et `Playlist.songKeys` ne stockent plus que
    des clés.
  - La bibliothèque s'affiche tout de suite avec les clés retenues au
    lancement précédent, puis les empreintes sont vérifiées en arrière-plan :
    une lecture et au plus une écriture du cache, aucune si rien n'a changé.
  - Les anciens ids sans morceau correspondant restent en attente et migrent
    quand le morceau réapparaît.
  - Les paroles migrées gardent leurs métadonnées ; la recherche de secours
    tolère ±2 s d'écart de durée.
- [x] Tests de migration et de calcul d'empreinte.

## Phase 2 — Bibliothèque desktop

- [x] `DesktopMusicRepository` (`lib/data/desktop_music_repository.dart`)
      derrière `MusicRepository` : un ou plusieurs dossiers musique, scan
      récursif dans un isolate (dossiers imbriqués et illisibles gérés).
- [x] Lecture des tags et pochettes (`audio_metadata_reader`) : mp3, flac,
      m4a, ogg, opus, wav, aiff. Sans tags : titre tiré du nom de fichier,
      « Unknown artist ». Pochettes lues à la demande.
- [x] Persistance des dossiers choisis (`libraryFoldersProvider`), rescan
      manuel et index sur disque (`library_index.json`) : seuls les fichiers
      nouveaux ou modifiés (taille, date) sont relus.
  - Dialogue « Music folders » (icône dossier à côté de LIBRARY dans la
    barre latérale) : ajouter, retirer, rescanner.
  - Premier lancement sans dossier : écran « Add your music ».
- [x] Brancher dans `createMusicRepository` : Windows, macOS et Linux
      utilisent `DesktopMusicRepository` ; `SampleMusicRepository` ne sert
      plus qu'au web et aux tests.

## Phase 3 — Interface desktop

Le mobile reste inchangé ; le desktop a son propre shell qui réutilise les
providers existants.

- [x] `DesktopShell` (`lib/desktop/`) : barre latérale (Accueil, Découvrir,
      Morceaux, Albums, Artistes, Likes, Playlists), barre du haut (historique
      précédent/suivant, recherche dans la bibliothèque), barre de lecture en
      bas, panneau Paroles / File d'attente à droite.
- [x] Listes denses adaptées à la souris (tri, colonnes, menu contextuel,
      double-clic pour lire).
- [x] Raccourcis globaux : Espace (lecture/pause), Ctrl+←/→ (précédent/suivant),
      Ctrl+F (recherche), Ctrl+L / Ctrl+Q (panneaux), Alt+←/→ et boutons
      latéraux de la souris (historique).
- [x] Choix du shell selon la plateforme dans `main.dart`.
- [x] Now Playing en plein écran (grande pochette et paroles, Échap pour
      sortir).

Le studio de paroles s'ouvre depuis le panneau Paroles et depuis Now Playing en
plein écran ; il n'a pas d'entrée dans la barre latérale. L'entrée
Synchronisation viendra avec la phase 5.

## Phase 4 — Studio de paroles

Réutilise `lyrics_editing`, `lyrics_aligner` et `lyrics_structure`.
Implémenté dans `lib/desktop/lyrics_editor.dart` (`DesktopLyricsEditor`), avec
deux modes : *Edit & time* et *Live sync*.

- [x] Vue texte et timings côte à côte, avec un inspecteur pour les lignes
      sélectionnées et une timeline dont les marqueurs se déplacent à la
      souris.
- [x] Synchronisation au clavier. Raccourcis retenus (différents du plan
      initial) :
  - Espace marque la ligne (*Live sync*) ou lance/met en pause (*Edit &
    time*) ; P lance/met en pause ;
  - Ctrl+Z annule ; B insère une pause instrumentale ;
  - ←/→ recule/avance de 5 s ; `[` / `]` décalent la sélection de ±100 ms ;
  - Entrée cale la ligne sur la position de lecture ; M fusionne ; Suppr
    supprime ; F2 édite ; ↑/↓ déplacent la sélection ;
  - Ctrl+S enregistre ; Échap quitte le champ, le mode ou l'éditeur.
- [x] Vitesse de lecture réglable (0,5×, 0,75×, 1×), restaurée à la fermeture.
- [x] Auto-sync Whisper accessible depuis le studio, avec le score de
      confiance et une vérification avant enregistrement.
- [x] Import/export LRC : menu « ⋯ » de l'éditeur (Import LRC…, Export LRC…,
      Copy as LRC), via `file_selector`. Un fichier sans horodatage est
      importé comme texte.
- [x] (Optionnel) Forme d'onde de la piste, derrière les marqueurs de la
      timeline, plus vive jusqu'à la tête de lecture. Décodée sous Windows par
      Media Foundation (`windows/runner/waveform_channel.cpp`, canal
      `my_zik/waveform`) ; aucune forme d'onde pour les morceaux streamés ni
      sur les autres plateformes. Vérifiée par
      `integration_test/waveform_test.dart` (`fvm flutter drive
      --driver=test_driver/integration_test.dart
      --target=integration_test/waveform_test.dart -d windows --profile`).

## Phase 5 — Synchronisation sur le réseau local

Code dans `lib/sync/` (cœur testable sans Flutter ni réseau réel), providers
dans `lib/providers/sync_providers.dart`, écrans `lib/desktop/sync_page.dart`
et `lib/screens/sync_screen.dart`. Le serveur (desktop) et le client (mobile)
démarrent depuis `main()`, jamais depuis les widgets.

### 5.1 Modèle de données synchronisable

- [x] Chaque enregistrement (`like:<SongKey>`, `playlist:<id>`,
      `lyrics:<SongKey>`) porte une date de modification, l'appareil d'origine
      et un marqueur de suppression (`SyncStore`). Toutes les paroles
      voyagent, timings compris : trouvées en ligne, écrites, éditées ou
      synchronisées à la main.
- [x] Résolution des conflits : ce que l'utilisateur a fait l'emporte sur ce
      que l'app a trouvé (des paroles trouvées en ligne ne remplacent jamais
      des paroles éditées ou synchronisées à la main) ; ensuite la dernière
      écriture gagne, enregistrement par enregistrement (égalité départagée
      par l'appareil d'origine). Les
      données d'avant la synchro sont enregistrées une fois comme les plus
      anciennes, pour être fusionnées et non écrasées.
- [x] Journal des changements avec curseur : chaque changement accepté reçoit
      un numéro de séquence ; les échanges sont incrémentaux dans les deux
      sens.

### 5.2 Serveur (desktop)

- [x] Serveur HTTP (`SyncServer`, port 47815 ou un port libre) : `hello`,
      `pair`, `sync` (envoi + réception en un aller-retour), manifeste des
      fichiers, téléchargement avec `Range`, envoi reprenable.
- [x] Annonce mDNS (`nsd`, service `_myzik._tcp`, identifiant dans le TXT).
- [x] Page « Sync with phone » : état du serveur, appairage, téléphones
      appairés (dernière synchro, désappairage), dernier évènement.

### 5.3 Appairage

- [x] Le desktop affiche un QR code (adresses, port, identifiant, code à
      6 chiffres) ; le code est aussi affiché pour une saisie manuelle.
      Usage unique, 10 minutes, 5 essais.
- [x] Le mobile le scanne (`mobile_scanner`) ou le saisit, et reçoit un jeton
      propre à l'appareil (seul son SHA-256 est gardé sur le desktop).
- [x] Toutes les requêtes portent le jeton ; un téléphone désappairé reçoit
      401 et l'app lui demande de s'appairer à nouveau.

### 5.4 Client (mobile)

- [x] Écran Sync (icône dans l'en-tête de l'accueil) avec « Sync now ».
- [x] Synchro automatique au lancement et au retour au premier plan. Le PC
      est cherché à sa dernière adresse, puis par mDNS, puis aux adresses du
      QR code.
- [x] État affiché : progression, dernière synchro, bilan, erreurs.

### 5.5 Fichiers audio

- [x] Échange des manifestes (`SongKey`, taille, tags) dans les deux sens.
- [x] Transfert des fichiers manquants, reprise après coupure (fichier
      `.part` + `Range` ou décalage d'envoi). Les fichiers reçus gardent leur
      clé d'origine (un téléchargement YouTube reste `yt:`) et rejoignent la
      bibliothèque avec leur pochette (pochette intégrée au fichier ou image
      d'un téléchargement YouTube, transférée à part).
- [x] Choix : aucun, téléchargements YouTube seulement, tout, ou sélection
      manuelle (« Choose files to copy… »).

Limites connues : horloges des appareils supposées à peu près justes (la
dernière écriture gagne) ; Windows demande d'autoriser My Zik sur les réseaux
privés au premier lancement ; non testé sur un vrai téléphone.

### Sécurité

La première version passe en HTTP sur le réseau local, protégée par le jeton
mais sans TLS : acceptable pour un réseau domestique, pas pour un Wi-Fi public.
Piste d'évolution : TLS avec certificat auto-signé épinglé lors de l'appairage.

## Phase 6 — Stockage en base SQLite

Aujourd'hui, les données structurées vivent dans `shared_preferences` (JSON
réécrit en entier à chaque changement) et dans des fichiers JSON (paroles,
index). Objectif : une base SQLite pour les données, des dossiers locaux pour
les seuls fichiers binaires. Le comportement visible ne change pas, la
synchronisation entre appareils comprise.

Choix : `sqflite` sur Android/iOS/macOS, `sqflite_common_ffi` sur
Windows/Linux (même API ; la bibliothèque SQLite native est fournie par sa
dépendance `sqlite3`), sans génération de code.
`drift` écarté pour ne pas introduire `build_runner`.

Répartition visée :

| Base SQLite | Dossiers locaux | `shared_preferences` |
| --- | --- | --- |
| likes, playlists, paroles et timings, journal de synchro, appareils appairés, cache des empreintes, index de la bibliothèque desktop, téléchargements et fichiers reçus (métadonnées) | fichiers audio et pochettes (téléchargés et reçus) | quelques réglages simples : mode de transfert, dernier morceau joué, consentement à l'auto-sync IA |

### 6.1 Socle

- [x] Dépendances et initialisation : `sqflite` sur mobile ;
      `sqflite_common_ffi` sur desktop, initialisés dans `main()`
      (`sqlite3_flutter_libs`, paquet vide en fin de vie, retiré).
- [x] Un fichier de base unique dans le dossier support de l'app, schéma
      versionné avec migrations (`onCreate` / `onUpgrade`).
- [x] Provider de la base, surchargeable par une base en mémoire dans les
      tests.

### 6.2 Données

- [x] Likes (table par `SongKey`) et playlists (table des playlists + table
      ordonnée des morceaux).
- [x] Paroles : une ligne par `SongKey` (texte, timings, source, édité,
      métadonnées normalisées indexées). Remplace le dossier `lyrics/` et
      permet de chercher le même enregistrement par requête.
- [x] Journal de synchronisation (`SyncStore`) et appareils appairés.
- [x] Cache des empreintes et index de la bibliothèque desktop.
- [x] Métadonnées des téléchargements YouTube et des fichiers reçus ; les
      fichiers audio et pochettes restent dans `downloads/` et `received/`.
- [x] Écritures atomiques : appliquer un changement reçu et l'inscrire au
      journal dans une même transaction (`AppDatabase.atomically`, utilisé
      par `SyncEngine.incoming` ; en cas d'échec, rien n'est écrit et l'état
      en mémoire est relu depuis le disque).

### 6.3 Migration

- [x] Au premier lancement, reprise automatique des données existantes
      (`shared_preferences`, `lyrics/*.json`, `library_index.json`,
      `received/index.json`) dans la base, une seule fois et sans perte.
- [x] Suppression des anciennes clés et fichiers une fois la reprise
      réussie ; en cas d'échec, les anciennes données restent en place.
      Les anciens ids encore sans morceau sont gardés pour la migration
      tardive ; les fichiers audio et pochettes reçus restent. Une
      installation déjà migrée par une version précédente est nettoyée une
      fois (`legacy.cleanup.v1`).
- [x] Tests : schéma et migrations, reprise des anciennes données, suite
      existante adaptée à une base en mémoire (`test/support/
      test_database.dart`, une base indépendante par test).

---

## Plus tard

- Contrôles média Windows (SMTC) et raccourcis multimédia du clavier.
- Versions macOS et Linux.
- Synchronisation des réglages et de la file de lecture.
