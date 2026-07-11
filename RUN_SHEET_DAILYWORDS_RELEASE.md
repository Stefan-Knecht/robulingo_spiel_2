# DailyWords Release Run Sheet

Ziel: Lokale Aenderungen an der Flutter-Web-App kontrolliert als aktualisiertes
DailyWords/RobuLingo Paket auf Firebase Hosting ausrollen. Der oeffentliche
Zugriff laeuft u.a. ueber `dailywords-project.org` und die Firebase-Site
`dailywords-635c5.web.app`.

## 0. Scope

Dieses Run Sheet gilt fuer:

- Flutter-App: `Flutter_apps/robulingo_spiel`
- DailyWords Hosting Target: `dailywords`
- RobuLingo Hosting Target: `robulingo`
- Firebase Projekt: `robulingo-635c5`
- Kanonisches Deploy-Skript: `tools/deploy_firebase_hosting.sh`

Autoritaetsregel:

- Massgeblich ist
  `/Users/knecht/Knecht x/_P_Kopie/__Meerbusch/Programme/Cloudflare/RealTalk_Modular`.
- RobuLingo/Flutter ist hier Legacy-Namensraum bzw. nachgelagertes
  2AFC-Trainingstarget, nicht die fachliche Referenz.
- Die lokale Einstiegs-App fuer aktuelle Modulauswahl/Dialog-Arbeit ist
  `Cloudflare/RealTalk_Modular` mit `npm run dev:web`.
- Direkte Flutter-DailyWords-Starts muessen
  `--dart-define=APP_FLAVOR=dailywords` verwenden.

Nicht kanonisch:

- `deploy_firebase_hosting.sh` im Projekt-Root. Das Skript ist aelter und baut
  nicht den in `DEPLOY_WEB.md` beschriebenen Zwei-Flavour-Pfad.

## 1. Release-Entscheidung

Vor dem Build kurz festhalten:

- Was wird geaendert?
- Welche Links oder Workflows muessen danach weiter funktionieren?
- Betrifft es nur DailyWords oder auch RobuLingo?
- Gibt es neue Assets, Curricula, Scene Packs oder nur Code?
- Muss ein bestehender Cloudflare/Firebase Link unveraendert weiterlaufen?

Minimaler Akzeptanzsatz fuer die aktuelle Menue-Aenderung:

- 2AFC-Direktlinks mit `direct=1`, `resume=0`, `skip_resume=1` starten weiter.
- Das Burger-Menue in 2AFC/Resume nutzt dieselbe Seitenpanel-Logik wie
  Modulauswahl/Dialog-Domaenen.
- L1/L2, Modulwechsel, Trainingstiefe, Verlauf und Home-Aktion sind im Menue
  erreichbar.
- Bestehende `return_to` Parameter werden nicht entfernt.

## 2. Lokaler Preflight

Arbeitsverzeichnis:

```bash
cd "/Users/knecht/Knecht x/_P_Kopie/__Meerbusch/Programme/Flutter_apps/robulingo_spiel"
```

Status pruefen:

```bash
git status --short
```

Wichtig:

- Unbekannte oder fremde lokale Aenderungen nicht ueberschreiben.
- Nur deployen, wenn klar ist, welche lokalen Aenderungen Bestandteil des
  Releases sind.
- Falls ein Commit gewuenscht ist, vorher Diff pruefen und bewusst committen.

## 3. Lokale Qualitaetspruefung

Gezielte Analyse fuer geaenderte Dateien:

```bash
dart analyze lib/ui/session/session_widgets.dart lib/app/robulingo_app.dart
```

Schlanker Compile-Test:

```bash
flutter test test/app_compile_test.dart
```

Optional breiter:

```bash
flutter test
```

Hinweis: Wenn `flutter test` an bekannten, nicht releasebezogenen Tests
scheitert, Fehler konkret notieren und nicht still ignorieren.

## 4. Lokaler Smoke-Test

Aktuelle DailyWords/RealTalk_Modular-Einstiegsoberflaeche starten:

```bash
cd "/Users/knecht/Knecht x/_P_Kopie/__Meerbusch/Programme/Cloudflare/RealTalk_Modular"
npm run dev:web
```

Bevorzugte URL ist `http://127.0.0.1:8092`; wenn der Port belegt ist, nutzt Vite
den naechsten freien Port.

Flutter nur fuer das DailyWords-2AFC-Trainingstarget direkt starten:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8095 --dart-define=APP_FLAVOR=dailywords
```

Testlink fuer Therapeutin/DailyWords 2AFC:

```text
http://127.0.0.1:8095/?lang=el&source=realtalk&pack=therapeutin&mode=2afc&audio=1&autoplay=1&start_audio=1&direct=1&resume=0&skip_resume=1&repetitions=1&repeat_count=1&intensity=default&training_depth=default&return_to=http%3A%2F%2F127.0.0.1%3A8092%2F&app_flavor=dailywords&learner_id=u1840f15d319fb4ca8c30979065c1ff7b&user_id=u1840f15d319fb4ca8c30979065c1ff7b&progress_code=DW-43HV-99ZY&start=start_curriculum_a.json&module=start_curriculum_a.json&curriculum=start_curriculum_a.json&l1=de&l2=el&l1_locale=de-DE&l2_locale=el-GR&input_language=l2
```

Abhaken:

- App laedt ohne Blank Screen.
- 2AFC startet direkt.
- Audio blockiert die UI nicht.
- Burger-Menue oeffnet links als Seitenpanel.
- Menue laesst sich per Overlay und Schliessen-Button schliessen.
- L1/L2 Dropdowns zeigen Deutsch -> Griechisch.
- Modulauswahl-Aktion fuehrt zur Matrix.
- Verlauf/Home-Aktionen sind sichtbar.
- Mobile Breite testen, falls moeglich.

## 5. Preview Deploy

Preview-Channel eindeutig benennen, z.B. Datum oder Branch:

```bash
tools/deploy_firebase_hosting.sh preview dailywords-menu-20260523
```

Das Skript:

- verwendet standardmaessig lokalen Git-Ref `HEAD`
- baut `APP_FLAVOR=robulingo`
- deployt Target `robulingo`
- baut `APP_FLAVOR=dailywords`
- deployt Target `dailywords`

Optional remote Ref erzwingen:

```bash
FETCH_FROM_ORIGIN=1 SOURCE_REF=origin/main tools/deploy_firebase_hosting.sh preview dailywords-menu-20260523
```

Preview-Ergebnis dokumentieren:

- Preview URL robulingo:
- Preview URL dailywords:
- Build-Zeit:
- getesteter Commit/Ref:

## 6. Preview Smoke-Test

Auf der Preview-URL testen:

- Startseite/Modulauswahl laedt.
- DailyWords Direktlink mit echten Parametern laedt.
- 2AFC Burger-Menue ist neues Seitenpanel.
- Dialog-Domaenen/Modulauswahl-Menue unveraendert plausibel.
- Browser hart neu laden.
- In DevTools pruefen, ob `index.html` und `flutter_service_worker.js` nicht
  aus altem Cache kommen.

Minimaler Direktlink-Test:

```text
<PREVIEW_DAILYWORDS_URL>/?lang=el&source=realtalk&pack=therapeutin&mode=2afc&direct=1&resume=0&skip_resume=1&start=start_curriculum_a.json&module=start_curriculum_a.json&curriculum=start_curriculum_a.json&l1=de&l2=el&input_language=l2
```

## 7. Produktionsfreigabe

Nur deployen, wenn:

- lokale Checks bestanden oder bekannte Altprobleme dokumentiert sind
- Preview Smoke-Test bestanden ist
- Rollback-Pfad bekannt ist
- keine unerklaerten lokalen Aenderungen in `git status --short` stehen

Produktionsdeploy:

```bash
tools/deploy_firebase_hosting.sh prod
```

Produktionsdeploy aus Remote-Ref nur bewusst:

```bash
FETCH_FROM_ORIGIN=1 SOURCE_REF=origin/main tools/deploy_firebase_hosting.sh prod
```

## 8. Produktions-Smoke-Test

Sofort nach Deploy pruefen:

- `https://dailywords-635c5.web.app/`
- `https://dailywords-635c5.web.app/?lang=el&source=realtalk&pack=therapeutin&mode=2afc&direct=1&resume=0&skip_resume=1&start=start_curriculum_a.json&module=start_curriculum_a.json&curriculum=start_curriculum_a.json&l1=de&l2=el&input_language=l2`
- Einstieg ueber `dailywords-project.org`, falls diese Domain auf das Paket
  verweist oder Links dorthin ausgibt.

Abhaken:

- App laedt nach hartem Reload.
- 2AFC startet direkt.
- Burger-Menue ist neues Seitenpanel.
- Modulauswahl erreichbar.
- Ruecksprung/`return_to` funktioniert in einem realistischen Link.
- Kein alter Service Worker haelt sichtbar alte UI.

## 9. Cache- und Service-Worker-Hinweise

`firebase.json` setzt bereits `no-cache, no-store, must-revalidate` fuer:

- `/index.html`
- `/flutter_service_worker.js`
- `/version.json`

Trotzdem bei Problemen:

- Browser hard reload.
- DevTools Application > Service Workers > unregister.
- DevTools Application > Storage > Clear site data.
- In Inkognito/privatem Fenster gegentesten.

## 10. Rollback

Firebase Hosting kann normalerweise auf ein vorheriges Release zurueckgesetzt
werden. Optionen:

1. Firebase Console: Hosting > Release History > vorheriges Release
   wiederherstellen.
2. Vorherigen Git-Ref deployen:

```bash
SOURCE_REF=<GOOD_COMMIT_SHA> tools/deploy_firebase_hosting.sh prod
```

Rollback danach ebenfalls smoke-testen:

- Startseite
- 2AFC Direktlink
- Modulauswahl

## 11. Release-Protokoll

Bei jedem Release ausfuellen:

```text
Datum/Zeit:
Operator:
Ziel:
SOURCE_REF:
Preview Channel:
Preview URL:
Produktionsdeploy ja/nein:
Firebase Release IDs:
Gepruefte Links:
Bekannte Restrisiken:
Rollback-Ref:
```

## 12. Stop-Kriterien

Nicht deployen oder sofort rollbacken, wenn:

- Blank Screen auf DailyWords.
- Direktlinks mit `direct=1` starten nicht.
- Audio oder Curricula laden nicht.
- Menue-Aktionen fuehren in falsche App/Domain.
- Service Worker liefert trotz Reload reproduzierbar altes Paket.
- RobuLingo Target ist sichtbar regressiv, obwohl nur DailyWords geplant war.
