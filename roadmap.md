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

### 5.1 Modèle de données synchronisable

- [ ] Chaque enregistrement (paroles par `SongKey`, like, playlist) porte une
      date de modification et un marqueur de suppression (tombstone).
- [ ] Résolution des conflits : la dernière écriture gagne, enregistrement par
      enregistrement.
- [ ] Journal des changements avec curseur, pour des échanges incrémentaux.

### 5.2 Serveur (desktop)

- [ ] Serveur HTTP sur le réseau local, endpoints pull/push des changements et
      transfert de fichiers.
- [ ] Annonce mDNS (`nsd`) pour être découvert par le mobile.
- [ ] Écran Synchronisation : état du serveur, appareils appairés, révocation.

### 5.3 Appairage

- [ ] Le desktop affiche un QR code (adresse + jeton secret).
- [ ] Le mobile le scanne une fois (`mobile_scanner`) et stocke le jeton.
- [ ] Toutes les requêtes portent le jeton.

### 5.4 Client (mobile)

- [ ] Bouton « Synchroniser maintenant ».
- [ ] Synchro automatique à l'ouverture de l'app quand le PC appairé est
      découvert.
- [ ] Indicateur d'état et de dernière synchro.

### 5.5 Fichiers audio

- [ ] Échange des manifestes (`SongKey`, taille, empreinte) entre les appareils.
- [ ] Transfert à la demande des fichiers manquants, avec reprise après
      coupure.
- [ ] Choix de ce qui est transféré (tout, seulement les téléchargements, ou
      sélection manuelle).

### Sécurité

La première version passe en HTTP sur le réseau local, protégée par le jeton
mais sans TLS : acceptable pour un réseau domestique, pas pour un Wi-Fi public.
Piste d'évolution : TLS avec certificat auto-signé épinglé lors de l'appairage.

---

## Plus tard

- Contrôles média Windows (SMTC) et raccourcis multimédia du clavier.
- Versions macOS et Linux.
- Synchronisation des réglages et de la file de lecture.
