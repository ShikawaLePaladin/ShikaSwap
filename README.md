# ShikaSwap 1.3.0 — échange de libram / idole / totem avant le sort

Addon **WoW 1.12 (Turtle / Sunreach)**, réécriture complète de LibramSwap. Il équipe la bonne relique (emplacement 18) **juste avant** le sort qui en profite, sans jamais bloquer ton sort si quelque chose se passe mal. Les 64 reliques du serveur (librams, idoles, totems) sont dans le catalogue, générées depuis la base du serveur.

**Nouveautés 1.3.0 (audit du 2026-10-28) :** une **trace persistante** de chaque décision d'échange (100 lignes dans `ShikaSwapDB.trace_log`, active une semaine par défaut, lisible dans le fichier SavedVariables sans l'aide du joueur), des **compteurs permanents** (`ShikaSwapDB.counts`) qui disent pourquoi un échange n'a pas eu lieu, l'option `/ssw offgcd` pour Judgement, et deux corrections de file d'attente (voir §11). **Nouveautés 1.2.0 : le profil Necroladin** (4e emplacement, reconnu automatiquement par une « signature » de talents que tu enregistres) et **un menu relooké « sombre et doré »** avec une barre de profils toujours visible, les icônes des sorts et des reliques et l'infobulle d'objet complète. **Depuis la 1.1.0 :** un vrai menu (`/ssw`), un bouton de minimap, un indicateur flottant de relique avec le décompte de la recharge d'échange, une alerte « relique manquante », des profils par spécialité (changement automatique selon les talents), l'export / import par texte et des raccourcis clavier.

> **Statut** : testé hors jeu (**1336 tests** : 322 pour le moteur, 491 pour le menu et les fonctions 1.1.0, 363 pour la 1.2.0, 160 pour la 1.3.0, simulateur 1.12). **Jamais lancé dans le vrai client.** Le menu est validé pour le **Paladin** ; Druide et Chaman gardent les commandes (`/ssw set`) et leurs données, mais leur éditeur de règles n'est pas proposé dans le menu tant qu'il n'a pas été essayé en jeu. La liste de ce qui n'a pas pu être vérifié sans le jeu est au §8.

Fichiers : `ShikaSwap.toc`, `Bindings.xml`, `ShikaSwap_Data.lua` (catalogue, généré), `_Core.lua` (décision, file d'attente, sauvegarde), `_Hooks.lua` (hooks de lancement, évènements), `_Cmd.lua` (commandes, aide EN+FR, import LibramSwap), `_Spec.lua` (talents, profils par spécialité), `_Share.lua` (export / import texte, réinitialisation), `_Display.lua` (minimap, indicateur, alerte), `_Bindings.lua` (raccourcis), `_UI.lua` (le menu). Variable sauvegardée : `ShikaSwapDB` (par compte, schéma version 2).

---

## 1. Guide pas à pas pour le joueur (sans rien taper de technique)

### 1.1 Installer
1. Copie le dossier **`ShikaSwap`** (celui qui contient `ShikaSwap.toc`) dans `World of Warcraft\Interface\AddOns\`.
2. Si tu utilisais **LibramSwap** : lance **une session** avec LibramSwap encore activé, ShikaSwap importe tes réglages et te le dit dans le chat. Ensuite **désactive LibramSwap** et fais `/reload`. (Tant que LibramSwap est chargé, ShikaSwap reste « en veille » pour ne pas échanger deux fois.)
3. Lance le jeu : un message `ShikaSwap v1.3.0 chargé` s'affiche.

### 1.2 Ouvrir le menu
Tape **`/ssw`** (ou `/shikaswap`, ou `/ssw menu`). Tu peux aussi **cliquer sur le bouton de la minimap** (petite icône ronde, clic gauche). `Échap` ferme la fenêtre ; on la déplace en la faisant glisser. `/ssw help` donne l'aide des commandes.

La fenêtre a un style **sombre et doré** (fond sombre translucide, fine bordure dorée, titre doré, accents or et rose paladin ; uniquement des textures du client, aucun fichier ajouté). En haut :
- le titre « ShikaSwap », la version et une **pastille d'état** : **verte** = actif, **rouge** = désactivé, **grise** = en veille (LibramSwap détecté) ;
- la **barre de profils**, toujours visible : **Sacré · Protection · Vindicte · Necroladin**. Un clic charge le profil (le bouton « allumé » en doré avec un liseré rose est le profil en cours, un bouton grisé n'a encore rien d'enregistré). Survole un bouton pour l'explication.

Dessous, **cinq onglets** (l'onglet actif est surligné en doré) : Règles · Réglages & affichage · Profils · Import / Export · Diagnostic.

### 1.3 Choisir quelle relique pour quel sort (onglet « Règles »)
- Chaque ligne = **un sort** (Holy Light, Flash of Light, Consecration…). Par défaut tu vois seulement les sorts de ton livre de sorts ; le bouton **« Sorts : connus / tous »** en bas affiche tout le catalogue.
- **Relique 1** = celle que tu veux en priorité. **Relique 2** = celle à utiliser si la première n'est pas dans tes sacs. Pas de règles par situation : **une ligne par sort**.
- Pour choisir : clique sur les flèches **`<` `>`** à côté de la relique (ou clique sur le nom : clic gauche = suivante, clic droit = précédente). Le menu ne propose **que les reliques qui améliorent vraiment ce sort**. Après la dernière, on revient à « (aucune) » = pas de règle.
- Couleurs et mots à côté du nom : **vert « sacs »** = tu l'as dans tes sacs ; **bleu « équipée »** = elle est déjà équipée ; **rouge « absente »** = tu ne l'as pas.
- La **case à gauche du sort** coupe ou rallume la règle sans la supprimer.
- Chaque ligne montre l'**icône du sort** (celle de ton livre de sorts) et l'**icône de la relique** choisie ; si le jeu ne connaît pas encore une icône, un point d'interrogation s'affiche à la place et tout reste utilisable.
- Survole une relique (nom ou icône) : l'**infobulle d'objet complète** du jeu s'affiche quand l'objet est déjà connu de ton client (sinon la fiche du catalogue : ce qu'elle améliore, effet persistant, condition « cible < 35 % »). Cliquer sur l'icône fait comme cliquer sur le nom.
- Gagner du temps : **« Suggérer auto »** crée toutes les règles évidentes avec les reliques que tu possèdes (celles qui sont ambiguës, comme Libram of Hope qui touche tous les Sceaux, sont laissées à ton choix). **« Importer LibramSwap »** reprend tes anciens réglages.
- Le bouton **« Mode en combat »** change le comportement pendant un combat (voir §4) ; laisse **auto**, c'est le réglage conseillé.

### 1.4 Réglages et affichage (onglet « Réglages & affichage »)
Cases à cocher : addon actif · repli sur une relique équivalente moins bonne · **bouton minimap** · **indicateur flottant** · verrouiller l'indicateur · **alerte relique manquante** (chat) · **alerte : son**. Boutons : mode en combat, langue (auto / français / anglais), relique d'ouverture (équipée automatiquement hors combat), taille de l'indicateur (`-` / `+`), et **« Tout réinitialiser »** (demande un 2e clic pour confirmer ; les profils sont gardés et le bouton Annuler de l'onglet Import / Export ramène tes règles).

### 1.5 Le bouton de la minimap et le menu rapide
- **Clic gauche** : ouvre / ferme le menu. **Clic droit** : menu rapide (activer / désactiver l'addon, changer de mode, charger les règles Sacré / Vindicte / Protection / Necroladin, afficher / masquer l'indicateur, ouvrir le menu). **Glisser** : le déplacer autour de la minimap. Survol : état (actif / désactivé / EN VEILLE), mode, relique équipée, spécialité.
- Le masquer : case dans les Réglages, ou `/ssw minimap off`.

### 1.6 L'indicateur flottant
Une petite icône montre la **relique équipée**. En combat, juste après un échange, elle s'assombrit et affiche le **décompte (1,5 → 0)** de la recharge d'échange imposée par le serveur. Glisse-la où tu veux ; **verrouille-la** pour ne plus la déplacer par erreur ; change sa **taille** dans les Réglages. Hors combat l'échange est gratuit : pas de décompte.

### 1.7 L'alerte « relique manquante »
Quand tu lances un sort qui a une règle mais qu'**aucune** de ses reliques n'est dans tes sacs, un message orange apparaît dans le chat (**une seule fois par sort et par combat**, jamais de spam) et **ton sort part quand même**. Le son est optionnel. `/ssw alert test` montre à quoi ça ressemble.

### 1.8 Profils
- **Par spécialité (Paladin)** : quatre emplacements **Sacré / Protection / Vindicte / Necroladin** (voir §1.8b pour Necroladin). « Sauver » y range tes règles du moment ; « Charger » les remet **en un clic** (un bouton Annuler ramène les anciennes). Coche **« Changer les règles automatiquement quand la spécialité change »** : ShikaSwap lit tes points de talents, range tes règles dans l'ancienne spécialité et charge celles de la nouvelle (jamais en plein combat). Si la nouvelle spécialité n'a pas encore de règles, tes règles actuelles sont conservées. Si les talents sont illisibles (ou à égalité), le bouton **« Spécialité de secours »** décide.
- **Profils nommés** (toutes classes) : écris un nom, « Sauver » ; choisis avec `<` `>`, puis « Charger » ou « Supprimer » (2e clic pour confirmer).

### 1.8b Le profil Necroladin (4e emplacement)
**Necroladin** est un emplacement de profil comme Sacré / Protection / Vindicte, avec un **préréglage** repris de ton ancien profil LibramSwap « necroladin » (rien d'inventé) :
- **Actives** : Holy Shock -> Libram of the Radiant Dawn, Seal of the Crusader -> Libram of Fervor.
- **Présentes mais désactivées** (tu les rallumes d'une case à cocher) : Judgement et Seal of Righteousness -> Libram of Final Judgement, Holy Strike -> Libram of the Eternal Tower, Consecration -> Libram of the Faithful, Holy Light -> Libram of Radiance, Flash of Light -> Libram of Light, Cleanse -> Libram of Grace, Holy Shield -> Libram of the Dreamguard, Hand of Freedom -> Libram of the Resolute.
- **Réglages de l'ancien profil** : `combatSameTickAttempt = false` et délai 0,03. Dans ShikaSwap le mode en combat est un réglage **global** et il n'y a pas de délai fixe (l'attente suit l'état réel de la recharge), donc charger Necroladin **ne change pas ton mode** (il ne force jamais `burst`). Si tu veux le comportement « pas dans la même frame », mets le mode sur `wait` (le mode `auto` y passe tout seul si le jeu refuse le burst). Écart documenté, rien d'inventé.
- Modifiable comme les autres emplacements (« Sauver » range tes règles du moment dedans). Le bouton **« Retour préréglage »** (onglet Profils, 2 clics) ou `/ssw spec necro reset` remet le préréglage dans l'emplacement (tes règles en cours ne sont pas touchées). Le menu affiche « préréglage » ou « modifié ».
- Remarque : « Seal of Righteousness -> Libram of Final Judgement » est repris tel quel de ton profil ; `/ssw check` signalera que cette relique n'améliore pas ce sort d'après les données serveur.

**Reconnaissance automatique : enregistrer ta signature de talents.** ShikaSwap ne connaît pas ta répartition de talents Necroladin, donc :
1. Mets tes talents Necroladin comme tu les joues (ouvre une fois la fenêtre des talents si besoin).
2. Menu > onglet **Profils** > **« Enregistrer mes talents actuels comme Necroladin »** (ou `/ssw spec necro capture`). ShikaSwap mémorise tes points dans les trois arbres (Sacré / Protection / Vindicte) dans `ShikaSwapDB`.
3. Règle la **tolérance** avec `-` / `+` (ou `/ssw spec necro tol 3`) : de combien de points par arbre ta répartition peut s'écarter (**±2 par défaut**, de 0 à 10).
4. Coche **« Changer les règles automatiquement quand la spécialité change »**. Quand ta répartition correspond à la signature (tolérance comprise), ShikaSwap reconnaît **Necroladin, en priorité sur Sacré / Protection / Vindicte** ; hors de la tolérance il revient à la spécialité normale. Jamais de bascule en combat (reportée à la fin du combat).
5. **Tant qu'aucune signature n'est enregistrée**, Necroladin n'est **jamais choisi automatiquement** : le menu affiche « Signature de talents non enregistrée… (choix manuel uniquement) », et si tu le charges à la main (barre de profils ou `/ssw spec load necro`), la bascule automatique ne te l'enlève pas. « Oublier la signature » (`/ssw spec necro clear`) y ramène.

### 1.9 Partager ses règles (onglet « Import / Export »)
- **Exporter** écrit tes règles sur **une seule ligne** de texte (commence par `SSW1;`). Clique dans la boîte, `Ctrl+A`, `Ctrl+C`, colle-la à un ami.
- **Importer** : colle une ligne dans la boîte, clique « Importer » puis re-clique pour confirmer : elle **remplace** tes règles. Un texte abîmé, tronqué, d'une autre version, avec une relique inconnue ou d'une autre classe est **refusé en entier avec un message clair** et ne change rien. **Annuler** ramène les règles d'avant (un seul niveau, qui se rejoue).
- En commandes : `/ssw export`, `/ssw importtext <texte>`, `/ssw undo`.

### 1.10 Raccourcis clavier
`Échap` > **Raccourcis clavier** > section **ShikaSwap** : ouvrir / fermer le menu · activer / désactiver l'addon · changer le mode en combat.

### 1.11 Si quelque chose ne va pas
Onglet **Diagnostic** : « Statut » (hooks installés, compteurs, erreurs), « Vérifier les règles » (relique inconnue, sans effet sur ce sort, d'une autre classe), « Journal » (active d'abord **Enregistrement**, fais un combat, puis clique Journal). Colle le contenu ici si tu demandes de l'aide. Une erreur dans le menu ne bloque jamais un sort : elle s'affiche en rouge dans le chat.

---

## 2. Installation (résumé technique)

1. Dossier `ShikaSwap` dans `World of Warcraft\Interface\AddOns\`.
2. Import de LibramSwap (lecture seule) : voir §1.1.
3. Sans ancien addon : `/ssw` puis « Suggérer auto », ou `/ssw suggest` puis `/ssw auto` / `/ssw set ...`.

---

## 3. Commandes (`/shikaswap` ou `/ssw`)

`/ssw` seul, `/ssw menu`, `/ssw ui`, `/ssw config` : ouvre / ferme le menu. `/ssw status` : l'état (c'était l'ancien comportement de `/ssw` seul).

| Commande | Effet |
|---|---|
| `status` | état, mode, hooks installés, relique en place, compteurs, extensions détectées (SuperWoW/Nampower/UnitXP) |
| `list` | les règles, avec `[equipped]`, `[bags]` ou `[missing]` pour chaque relique |
| `set <sort> = <relique>[, <relique2>...]` | règle : la **première relique disponible** gagne. Ex. `set Holy Light = Libram of Radiance` (le menu écrit exactement la même règle) |
| `clear <sort>` · `disable <sort>` · `enable <sort>` | supprime / coupe / rallume une règle |
| `on` · `off` | active / coupe tout l'addon |
| `bags` | les reliques du catalogue que tu possèdes (sacs + équipée) et les sorts qu'elles améliorent |
| `suggest` | pour chaque sort, les reliques que tu possèdes et qui l'améliorent |
| `auto` | crée les règles **évidentes** seulement (une seule relique possible, ou un groupe équivalent comme Light > Divinity) |
| `check` | vérifie tes règles contre les données serveur |
| `mode auto\|burst\|wait\|skip` | comportement **en combat** (voir §4) |
| `next <sort>` · `opener <sort\|off>` | échange maintenant pour ce sort (macro) · relique équipée hors combat |
| `profile list\|save\|load\|del <nom>` | profils nommés |
| `spec` · `spec save\|load holy\|prot\|ret\|necro` · `spec auto on\|off` · `spec manual holy\|prot\|ret\|necro\|off` · `spec reset <spec>` | profils par spécialité (Paladin) ; `reset necro` = retour au préréglage, les autres emplacements sont vidés |
| `spec necro capture\|clear\|tol <0-10>\|reset` | signature de talents Necroladin : enregistrer les talents actuels, l'oublier, tolérance par arbre (2 par défaut), préréglage |
| `export` · `importtext <texte>` · `undo` | partage par texte ; annule la dernière opération en masse (import, réinitialisation, chargement de profil / spécialité) |
| `minimap [on\|off\|reset]` | bouton de minimap |
| `indicator on\|off\|lock\|unlock\|scale <0.5-2.5>\|reset` | indicateur flottant |
| `alert chat on\|off` · `alert sound on\|off` · `alert test` | alerte relique manquante |
| `trace` · `trace on\|off\|week\|clear` · `tracelog [n]` | trace persistante des échanges : état · active jusqu'à `off` · coupe · re-arme une semaine · efface · affiche les n dernières lignes (25 par défaut) |
| `offgcd swap\|skip` | en combat, échanger (défaut) ou non pour les sorts **sans GCD** (Judgement) |
| `defaults confirm` | remet règles et réglages à zéro (profils gardés) |
| `import [force]` | (ré)importe depuis `LibramSwapDB` si l'ancien addon est chargé |
| `probe` | **hors combat** : mesure si le client met l'emplacement à jour tout de suite et le délai de confirmation (§8) |
| `debug on\|off` · `log` | debug en direct / relecture de l'anneau de 40 décisions en mémoire (rempli quand `trace on`) |
| `fallbacks on\|off` · `lang en\|fr\|auto` · `reset` | repli sur la relique équivalente · langue · remise à zéro des compteurs |

Les **boutons de barre d'action** sont pris en compte (hook `UseAction` + lecture de l'infobulle) ; les macros `/cast` aussi. Les noms de sorts sont insensibles à la casse, avec ou sans rang.

---

## 4. Ce que fait ShikaSwap avec le GCD (règle serveur)

Règle lue dans le code du serveur (`Player.cpp`, copie du 2026-09-29) : **en combat**, changer une relique envoie au client une recharge « Combat Swap » de **1,5 s** sur la catégorie du GCD. **Hors combat, c'est gratuit.** Un 2e échange dans les 1,5 s ne la relance pas. (C'est ce décompte que montre l'indicateur flottant.)

- **Hors combat** : échange immédiat, puis le sort part.
- **En combat** (selon `mode`) :
  - `burst` : échange **et** sort dans la même frame. Si le client l'accepte, l'échange ne coûte **rien**. Pendant un GCD en cours, ShikaSwap **attend sa fin** puis fait échange+sort ensemble (jamais d'extension du GCD).
  - `wait` : échange tout de suite, le sort est mis en file et part dès que la recharge réelle du sort est terminée (≈ 1,5 s + latence). Les appuis répétés sur la même touche sont absorbés ; le **dernier** appui gagne ; un autre sort pressé annule la file.
  - `skip` : aucun échange en combat.
  - `auto` (**défaut**) : `burst`, et **bascule seul sur `wait`** après 2 refus « pas prêt » consécutifs qui suivent directement un burst. L'appui refusé n'est pas perdu : il est rejoué quand le sort devient prêt.
- **Échanger à l'avance** : `/ssw next Holy Light` **après** ton sort dans une macro ; `/ssw opener Flash of Light` prépare la relique de départ hors combat.
- **Jamais d'échange** quand : mort/fantôme, objet sur le curseur, **fenêtre marchand / banque / échange / courrier / hôtel des ventes ouverte**, incantation ou canalisation en cours, case de sac verrouillée, un autre échange en transit, sort en vraie recharge, relique absente des sacs (le sort part quand même, et l'alerte prévient).
- **Fail-open** : toute erreur interne est comptée (`status`) et ton sort part quand même. Même chose pour le menu, la minimap, l'indicateur et l'alerte : chacun est construit sous `pcall`.

---

## 5. Différences avec LibramSwap

| | LibramSwap | ShikaSwap |
|---|---|---|
| Attente avant le sort différé | 0,6 s -> sort refusé pendant la recharge de 1,5 s | basée sur l'**état réel** de la recharge, garde-fou 0,25 s + latence, délai max 3 s |
| Handlers 1.12 | `function(self, event, ...)` : `event` toujours `nil`, évènements morts | variables globales `event`/`arg1`/`this`, testé sans argument |
| SavedVariables | lues au chargement du fichier (trop tôt) | liées à `ADDON_LOADED`/`VARIABLES_LOADED`/`PLAYER_LOGIN`, schéma versionné avec migration |
| Fenêtres de transaction | aucune garde (vente possible) | gardées |
| Barre d'action | non | oui |
| Table des effets | aucune (le README se trompe sur 9 librams) | 64 reliques générées depuis la base serveur |
| Interface | fenêtre de 1832 lignes (fuite de frames au redimensionnement) | menu à 5 onglets construit une seule fois, sous `pcall` ; une ligne par sort ; minimap, indicateur, alerte, profils par spécialité, export / import texte, raccourcis |
| `_G`, `...`, upvalues | `_G` (absent en 1.12), 1 vararg, 25/32 upvalues | aucun `_G`/vararg/`#` ; ≤ 9 upvalues par fonction |
| CPU au repos | `OnUpdate` permanent | frame cachée = aucun `OnUpdate` quand la file est vide ; l'indicateur masqué et la fenêtre fermée n'en ont pas non plus |
| Import | — | lecture seule de `LibramSwapDB` (règles actives, désactivées, profils) |

---

## 6. Menu : résumé technique / Menu overview (EN)

**FR** — Le menu ne contient aucune logique à lui : chaque bouton appelle la fonction de la commande correspondante (`SS.SetRuleCmd` pour `set`, `SS.SetEnabled` pour `enable/disable`, `SS.cmds.mode`, `SS.cmds.profile`, `SS.cmds.spec`, `SS.ImportText`...), puis se redessine depuis la sauvegarde. Il est créé à la première ouverture, jamais au chargement du fichier. Les textes sont tous dans `SS.M.en` / `SS.M.fr` (un test vérifie que chaque clé existe dans les deux langues).

**EN** — *The configuration window (`/ssw`, `/ssw menu`, minimap button, or a key binding) has five tabs. **Rules**: one line per spell, relic 1 (first choice) and relic 2 (fallback) chosen with `<` `>` among the catalogue relics that really improve that spell, coloured by "in bags / equipped / missing", a check box per rule, "Suggest auto" (= `/ssw auto`), "Import LibramSwap", mode button. **Settings & display**: on/off, fallbacks, minimap button, floating indicator (show, lock, size), missing-relic alert (chat, sound), language, opener, reset (asks for a second click). **Profiles**: per-spec rule sets for Paladins (Holy / Protection / Retribution) with one-click load, automatic switch on talent change (never in combat) and a manual fallback spec; named profiles for every class. **Import / Export**: the rules as one line of text (`SSW1;...`, no pipe characters, checksum), strict atomic import (any problem refuses the whole text and changes nothing), Undo. **Diagnostic**: `/ssw status`, `log`, `check`, trace and debug switches, output shown in the window. Every action calls the same function as the slash command; an error in the UI is printed in red and never stops a swap or a cast. The rule editor is validated for Paladins only; other classes keep `/ssw set`.*

Réglages enregistrés dans `ShikaSwapDB` (schéma 3) : `rules`, `off`, `profiles`, `combat`, `fallbacks`, `lang`, `opener`, `enabled`, `autoSpec`, `specProfiles{HOLY,PROT,RET,NECRO}`, `necroSig{HOLY,PROT,RET}` (signature de talents, absente tant qu'elle n'est pas enregistrée), `necroTol` (0 à 10, 2 par défaut), `specManual`, `lastSpec`, `minimap{show,angle}`, `indicator{show,locked,scale,x,y}`, `alert{chat,sound}`, `ui{x,y,tab,all}`, `backup` (un niveau d'annulation). Une sauvegarde de schéma 1 (ShikaSwap 1.0.0) ou 2 (1.1.0) est migrée sans perdre une règle ni un réglage (un test recharge une sauvegarde 1.1.0 complète et vérifie chaque champ) ; l'emplacement Necroladin est créé avec son préréglage, jamais écrasé s'il a déjà été modifié ; toute valeur corrompue est remplacée par sa valeur par défaut.

---

## 7. Limites connues du moteur

1. **Le client accepte-t-il un sort envoyé dans la même frame qu'un échange en combat ?** (hypothèse du mode `burst`). `auto` détecte et corrige tout seul ; `status` affiche `burst sent / refused`.
2. **`UseContainerItem` met-il à jour l'emplacement 18 immédiatement ?** `/ssw probe` répond.
3. **Un échange pendant une incantation l'interrompt-il côté client ?** Inconnu : ShikaSwap n'échange donc jamais pendant une incantation.
4. Le serveur **Turtle officiel** : aucune note de patch trouvée ; la règle vient du code du serveur Sunreach.
5. Effets persistants (`sticky` : Faithful, Farraki Zealot, Ardour, Virtue, Truth…) : ShikaSwap ne remet jamais l'ancienne relique tout seul, mais un sort suivant avec une autre relique l'enlèvera.
6. Les mappings **idole/totem** (Druide/Chaman) sont générés depuis les descriptions du serveur mais **jamais essayés** ; c'est pourquoi le menu ne les propose pas encore.
7. Conflits possibles : un autre addon qui remplace `CastSpellByName`/`UseAction` **sans** appeler l'ancien (`status` : `hooks: ... NONE`), **ItemRack** ou tout addon qui change aussi le slot 18, Nampower, mana insuffisante (l'échange a lieu même si le sort échoue).
8. Ordre de chargement : les addons chargés **après** ShikaSwap enveloppent ses hooks, ce qui est correct.

## 8. Ce qui n'a PAS pu être vérifié sans le jeu (menu et nouveautés 1.1.0 et 1.2.0)

**Spécifique à la 1.2.0 :**
- **Le relooking n'a jamais été vu** : couleurs de la bordure dorée (`SetBackdropBorderColor` sur la bordure d'infobulle), lisibilité du fond translucide, pastille d'état (rectangle de couleur unie `SetTexture(r,g,b,a)`), séparateurs fins, liseré doré des onglets et liseré rose de la barre de profils, alignement des 10 lignes avec les nouvelles icônes (fenêtre élargie à 840 px) et des 4 boutons de la barre. La bordure « UI-DialogBox-Gold-Border » n'a pas été utilisée (existence non garantie en 1.12) : la bordure d'infobulle teintée en or la remplace.
- **Les icônes** : `GetSpellTexture` sur l'index du livre de sorts, `GetItemInfo("item:ID:0:0:0")` (9e valeur = texture) ; un objet que le client n'a jamais vu n'a pas d'icône avant d'être en sac / équipé (repli : texture de la copie en sac ou équipée, sinon point d'interrogation).
- **L'infobulle d'objet complète** : `SetHyperlink("item:ID:0:0:0")` n'est appelé (sous `pcall`) que si `GetItemInfo` connaît déjà l'objet, pour ne provoquer aucune requête au serveur ; le rendu final (fiche du jeu + lignes ShikaSwap) est à regarder.
- **La signature de talents** : on suppose `GetTalentTabInfo` fiable (points dépensés par arbre) quand la fenêtre des talents n'a jamais été ouverte ; la tolérance de ±2 est un choix par défaut, à ajuster. Rien ne dit que ta répartition Necroladin soit assez différente de ta répartition Vindicte pour être distinguée à ±2 : si les deux se ressemblent, réduis la tolérance.
- **Délai 0,03 / « combatSameTickAttempt=false »** de l'ancien profil : pas de réglage équivalent par profil dans ShikaSwap (voir §1.8b).

**Déjà listé pour la 1.1.0 :**

Tout est testé dans un simulateur 1.12 (cadres factices) : la logique, les sauvegardes, les clics simulés, les erreurs. **Rien de visuel n'a été vu.** À regarder en jeu :
1. **Le rendu de la fenêtre** : alignement des 5 onglets, des 10 lignes, longueur des noms de reliques (« Libram of the Farraki Zealot [absente] ») dans les 236 px prévus, lisibilité des couleurs, textes français trop longs sur un bouton.
2. **Les modèles de widgets 1.12** : `UIPanelButtonTemplate` créé sans nom (comme l'ancien LibramSwap), `UICheckButtonTemplate`, `InputBoxTemplate`, `UIPanelCloseButton`, polices `GameFontNormalSmall` / `GameFontHighlightSmall` / `GameFontHighlightLarge`, fonds `Interface\DialogFrame\UI-DialogBox-*`.
3. **Le bouton de minimap** : position sur le rayon (78 px), icône par défaut (`INV_Misc_Book_11`, remplacée par l'icône de la relique équipée), glisser autour de la minimap (formule `atan2` sur `GetCursorPosition`), conflit avec d'autres boutons / minimap carrée.
4. **Le menu rapide** (clic droit) : fermeture à la souris (`MouseIsOver`) et à `Échap`.
5. **L'indicateur** : le décompte est calculé depuis l'heure de l'échange en combat (1,5 s), pas lu sur le cooldown réel ; avec la latence il peut avancer ou retarder d'un instant. Position conservée après changement de taille (conversion des décalages) à vérifier.
6. **Les talents** : `GetNumTalentTabs` / `GetTalentTabInfo` supposés renvoyer (nom, icône, points, fond) dans l'ordre Sacré / Protection / Vindicte sur Turtle ; l'arbre peut ne pas être prêt à la connexion (la vérification est refaite à chaque changement de zone et de talent). En cas de doute, la spécialité de secours s'applique.
7. **Les raccourcis** : `Bindings.xml` (entrées `SHIKASWAP_MENU/TOGGLE/MODE`) et libellés `BINDING_NAME_*` ; le libellé suit la langue du **client** (frFR), pas le réglage `lang`.
8. **Le son** d'alerte (`PlaySound("RaidWarning")`) et les chemins d'icônes.
9. Zone de saisie : copier / coller d'une ligne d'export de plusieurs centaines de caractères dans une `EditBox` 1.12.

## 9. Checklist de test en jeu (20 minutes)

1. `/ssw status` -> `hooks: CastSpellByName, CastSpell, UseAction` et pas « DORMANT ». `/ssw` ouvre la fenêtre ; chaque onglet s'affiche ; `Échap` la ferme.
2. Onglet Règles : « Suggérer auto », puis change une relique avec `<` `>` : la ligne se met à jour, `/ssw list` donne la même règle ; coche / décoche la case.
3. **Hors combat** : lance un sort réglé -> la relique change (regarde l'emplacement relique et l'indicateur) et le sort part du premier coup. `/ssw probe` -> note « immediately: YES/no ».
4. **Marchand** : ouvre un marchand, lance un sort réglé -> **rien** ne doit être vendu ni échangé.
5. **Combat sur mannequin** : mode `burst`, alterne deux sorts de relique différente. Le 2e part-il tout de suite ? L'indicateur compte-t-il 1,5 s ? Sinon `status` (burst sent / refused) puis `/ssw log`.
6. `mode wait`, puis `mode auto` (provoque 2 refus -> message « switching to 'wait' »).
7. **Alerte** : retire une relique des sacs, lance le sort en combat : un seul message par sort et par combat, le sort part.
8. **Minimap** : clic gauche / droit, glisser, survol, masquer / réafficher. **Indicateur** : glisser, verrouiller, changer la taille, `/reload` (position gardée).
9. **Spécialité** : « Sauver » pour la spé actuelle, change de talents (ou de spé) : les règles changent toutes seules ; sinon utilise la spécialité de secours.
10. **Export / import** : exporte, vide les règles, importe la ligne ; essaie d'ajouter une lettre au texte : il doit être refusé.
11. **Raccourcis** : assigne les trois, teste-les.
12. **Necroladin** : onglet Profils, « Enregistrer mes talents actuels comme Necroladin » avec tes vrais talents, active la bascule automatique, change un point de talent (reste reconnu à ±2), puis une répartition très différente (retour à Vindicte / Sacré). Vérifie que Holy Shock et Seal of the Crusader changent bien de relique avec le préréglage.
12b. **Look** : la fenêtre est lisible, la pastille change (désactive l'addon), la barre de profils allume le bon bouton, les icônes s'affichent, l'infobulle d'une relique montre la fiche d'objet.
12c. `/reload` : règles, réglages, position de la fenêtre / indicateur / minimap toujours là.
13. **Import LibramSwap** : première session avec LibramSwap activé -> message d'import ; désactive LibramSwap ; `/reload`.

---

## 11. Audit du 2026-10-28 : « certains librams ne swapent pas bien »

Données lues (lecture seule) : `SavedVariables\ShikaSwap.lua`, `Logs\nampower_debug.log` (3 fichiers, 05:44 -> 07:16), `CustomData\Chronicle_Shikiwa.txt` (journal de combat de ChronicleCompanion, qui contient des instantanés d'équipement `COMBATANT_INFO` avec la relique portée), `item_template` + `Spell.dbc` du serveur. Les scripts sont dans `tools\` (`audit_rules.js`, `check_offgcd.js`, `chron*.js`) et les simulations dans `tests\sim_necro.lua`, `tests\sim_fj.lua`.

**Ce qui est prouvé**
1. **Le journal Nampower ne contient aucun évènement d'équipement** (ni swap, ni `UseContainerItem`). Il montre seulement les lancements ; l'ordre « swap puis sort » ne peut donc pas y être lu. C'est la raison de la trace persistante de la 1.3.0.
2. **Le mode burst fonctionne** : dans le journal Chronicle, 22 instantanés d'équipement tombent **0,03 à 0,06 s autour** d'un Seal of the Crusader / Holy Shock et montrent déjà la bonne relique (exemples : 06:41:07.871 Seal of the Crusader puis instantané Libram of Fervor à +0,037 s ; 06:32:11.862 instantané Radiant Dawn à -0,042 s avant le Holy Shock de 06:32:11.904). Aucun contre-exemple parmi ces 22.
3. **Un échange coûte presque rien quand il part avec un sort à GCD** : l'écart jusqu'au sort à GCD suivant est de **1,60 s en médiane après un lancement accompagné d'un échange** (n = 9) contre **1,52 s** sans échange (n = 195), soit +0,08 s environ (≈ un aller-retour réseau), pas +1,5 s : la recharge « Combat Swap » de 1,5 s recouvre le GCD du sort lancé (hypothèse H1 du §7, première mesure réelle).
4. **Les échecs de lancement ne sont pas plus nombreux pour les sorts échangés** : « pas prêt » (code 60, d'après le contexte : refus juste après un Judgement ou pendant le GCD) par lancement : Holy Shock 43/248 = 0,17, Crusader Strike 27/189 = 0,14, Seal of Righteousness 17/159 = 0,11, **Seal of the Crusader 1/63 = 0,02** (celui qui échange le plus). Les codes 77 / 141 (≈ 1 300 lignes « Cast failed ... ignored code ») sont des refus **côté client Nampower** à la cadence de 100 à 150 ms de la touche unique de la rotation (aucun contact avec le serveur) ; 124 et 42 sont des **refus serveur** répétés (Holy Shock 52 refus 124 de suite à 06:16:18, Exorcism code 42, probablement une cible non éligible) : ce sont des appuis de rotation, sans lien avec un échange.
5. **La file d'attente Nampower** (« Queuing instant cast ... », 263 fois) est utilisée par la rotation (elle appuie quand le GCD finit dans moins de 0,3 s). ShikaSwap ne l'exploite pas pour un lancement avec échange : il attend la **fin réelle** du GCD (jamais d'extension du GCD), puis échange et lance dans la même frame. Coût mesuré en simulation : de 0 à 1 sort sur 100 (`tests\sim_necro.lua`) ; le mode `wait` coûte 12 % de sorts en moins (87 contre 99) : à éviter, et `auto` ne l'utilise que si le jeu refuse le burst.
6. **Cas non prouvable** : des Holy Shock lancés avec Libram of Fervor encore équipé (ex. 06:24:29 -> 06:24:56, 7 Holy Shock sans instantané Radiant Dawn) existent peut-être, mais les instantanés n'accompagnent pas chaque échange ; sans la trace il est impossible de conclure. **La trace de la 1.3.0 tranchera** : chaque échange y écrit `EQUIP` (sort, relique voulue, relique d'avant, case de sac, combat), `CAST`, `CONFIRM` (délai serveur) et `VERIFY-OK/BAD` 0,7 s après le sort ; chaque décision qui bloque un échange y écrit `PASS ... why=...` (casting, swap in transit, window open, spell on cooldown...).

**Règles contre les données serveur** (`node tools\audit_rules.js`) : les 11 librams de ta configuration ont le bon identifiant d'objet et un effet qui agit bien sur le sort mappé, sauf **une règle absurde : Seal of Righteousness -> Libram of Final Judgement** (Final Judgement n'agit que sur Judgement ; elle est désactivée, `/ssw check` la signale). Détails utiles : **Libram of Fervor** (id 23203) augmente le bonus de puissance d'attaque du sceau **et** les dégâts sacrés du Judgement of the Crusader : il doit rester équipé jusqu'au Judgement (vrai dans 73 cas sur 74 d'après le journal ; `/ssw check` avertit si une règle Judgement active l'enlèverait) ; **Libram of the Eternal Tower** (55110) réduit de 0,5 s la recharge de **Holy Strike et Crusader Strike**, or ta règle ne porte que sur Holy Strike alors que la rotation lance Crusader Strike (189 fois) ; **Libram of the Faithful / Farraki Zealot** sont persistants (l'effet doit rester équipé après Consecration) ; **Libram of Final Judgement** (58240) : environ 199 dégâts sacrés par Judgement, seulement sous 35 % de vie.

**Interaction avec ShikiwaRotation (Necroladin)** : chaque cycle Seal of the Crusader -> Judgement -> Seal of Righteousness -> ... -> Holy Shock coûte **deux échanges** (Fervor puis Radiant Dawn), chacun lancé avec un sort à GCD, donc quasi gratuit (point 3). Le Seal of the Crusader revient toutes les 8 à 15 s dans le journal. Mesures possibles, **non activées par défaut** : `/ssw offgcd skip` (ne jamais échanger en combat pour Judgement, qui n'a pas de GCD : l'échange y coûte jusqu'à toute la recharge de 1,5 s ; en simulation, 5 sorts sur 59 perdus pour 12 Judgement avec Final Judgement, soit environ 2 400 dégâts gagnés contre 1 500 à 2 000 perdus : presque à égalité, d'où l'absence de changement par défaut) ; ne pas mettre de règle Judgement avec Fervor ; garder le mode `auto`.

**Corrections de la 1.3.0** (comportement par défaut conservé, sauf ces deux points justifiés)
- **Judgement n'annule plus le Holy Shock mis en attente** (`CancelQueueFor` / « superseded ») : Judgement n'a pas de GCD (Nampower : `BeginCast ... NO Gcd`, Spell.dbc 20271 : 0/0) et la rotation le lance 0,1 à 0,4 s après un sort à GCD, donc pile dans la fenêtre d'attente d'un échange différé ; l'ancienne version abandonnait alors le sort en attente (il fallait que la rotation le relance). Un Judgement qui a besoin de son propre échange remplace toujours la file.
- **`UseAction` / `CastSpell` / `CastSpellByName`** passent le nom du sort à cette vérification (liste `SS.OFFGCD`, établie par `tools\check_offgcd.js` et le journal Nampower).
- Ajouts sans effet sur le jeu : trace persistante, compteurs permanents (`counts` : swapsCombat, swapsFree, `pass: <raison>`...), avertissements `/ssw check` (Fervor + Judgement ; autres sorts améliorés par une relique), option `offgcd`.

**Relire la trace sans le joueur** : après un `/reload` ou une déconnexion, ouvrir `WTF\Account\<compte>\SavedVariables\ShikaSwap.lua`, champs `trace_log` (100 lignes, ordre circulaire : la plus récente est à l'indice `trace_n`), `counts`, `traceUntil` (heure Unix de fin d'armement). Format d'une ligne : `HH:MM:SS g=<GetTime> ÉTIQUETTE texte`. Étiquettes : `SESSION`, `COMBAT start/end`, `PLAN`/`PASS` (décision et raison), `DEFER`/`DEFER-FIRE` (attente de la fin du GCD, durée), `EQUIP`, `CAST`, `CONFIRM`, `VERIFY-OK`/`VERIFY-BAD`, `UNCONFIRMED`, `QCAST`/`QCLEAR`, `BURST-REFUSED`, `UIERR`, `ERROR`. En jeu : `/ssw tracelog 60` ou menu > Diagnostic > « Afficher la trace enregistrée ».

**À vérifier en jeu** : (1) que la trace montre bien `EQUIP` puis `CONFIRM` pour chaque Holy Shock / Seal of the Crusader et aucun `VERIFY-BAD` ; sinon la raison est dans les lignes `PASS why=` juste avant ; (2) le coût réel de l'échange pour Judgement (hypothèse H1 contre H2 : `/ssw probe`) avant de décider de passer `offgcd` sur `skip` ; (3) que `time()` / `date()` existent bien dans ce client (sinon la trace s'écrit sans l'heure et ne s'arme pas pour une semaine).

## 10. Données et tests

Catalogue : `node tools\build_data.js` régénère `ShikaSwap_Data.lua` depuis `item_template.json` et `Spell.dbc` (`C:\Temp\ccx\sim\...`), et **échoue** si un nom de sort n'existe pas dans le DBC.

```
cd C:\Temp\ccx\shikaswap_work
sh run_tests.sh
```

`run_tests.sh` enchaîne : le lint Lua 5.0 et le compte d'upvalues des 9 fichiers Lua (limite 32, mesuré : 11 au maximum), les tests du moteur (attendu : `RESULT: 322 passed, 0 failed`), les tests du menu et des fonctions 1.1.0 (`tests\tests_ui.lua`, attendu : `RESULT: 484 passed, 0 failed`), les tests 1.3.0 (`tests\tests_v13.lua` : trace persistante, anneau de 100 lignes, fusion des lignes identiques, ordre EQUIP / CAST / CONFIRM / VERIFY, VERIFY-BAD et UNCONFIRMED quand l'objet ne change pas, file d'attente et Judgement, option offgcd, avertissements `check`, migration schéma 3 -> 4, compteurs, cycle Necroladin complet avec vérification que chaque Holy Shock et chaque Seal of the Crusader part avec la bonne relique ; attendu : `RESULT: 160 passed, 0 failed`), les tests 1.2.0 (`tests\tests_v12.lua` : préréglage Necroladin comparé au vrai profil LibramSwap de la fixture, capture et tolérance de la signature, bascule avec / sans signature et jamais en combat, barre de profils, icônes et leurs replis, infobulles, thème, migration 1.1.0 -> 1.2.0 ; attendu : `RESULT: 363 passed, 0 failed`) et le rejeu de l'ancien addon dans le monde simulé (`tests\audit_old_output.txt`).

Le harnais retire de Lua tout ce que 1.12/Lua 5.0 n'a pas (`string.match`, `select`, `unpack`, `_G`…), appelle les handlers **sans argument** (en posant seulement les globales `this`, `event`, `arg1`, comme le client), simule les cadres (`CreateFontString`, `SetChecked`, `OnShow`…), la minimap, les talents, les infobulles et lit `Bindings.xml`. Les tests couvrent notamment : ouverture / fermeture / Échap, changement de relique par le menu identique à `/ssw set`, désactivation, rafraîchissement après une commande, profil vide, classe non Paladin, cinq onglets, réinitialisation avec confirmation, profils nommés et par spécialité, détection des talents (égalité, API absente ou qui plante), bascule automatique (pas en combat), export / import (aller-retour, 20 cas de texte invalide, 700 textes aléatoires sans erreur Lua ni modification des règles), annulation, minimap (angle, glisser, clics, menu rapide, infobulle), indicateur (décompte, verrou, échelle), alerte (une fois par sort et par combat, son, erreur contenue), raccourcis, migration de schéma 1 -> 2 et valeurs corrompues, EN / FR complets.
