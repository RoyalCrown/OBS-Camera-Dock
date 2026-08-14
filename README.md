# OBS Camera Dock pro macOS

Ovládací dok pro jednu USB UVC kameru, primárně Razer Kiyo V2 X. Projekt používá UVC vrstvu z open-source aplikace CameraController a běží lokálně bez přístupu k internetu.

## Co obsahuje

- menu-bar helper pro macOS 14 a novější,
- lokální ovládací stránku na `http://127.0.0.1:24680/`,
- dynamické zobrazení pouze těch ovladačů, které kamera skutečně podporuje,
- focus, expozici, gain/ISO, white balance, jas, kontrast, saturaci, ostrost a zoom,
- obnovení kamery a návrat k výchozím UVC hodnotám.

Helper neotevírá video stream. Obraz kamery proto může dál používat OBS.

## Instalace a spuštění

1. Spusťte `OBS Camera Dock Helper.app`. V horní liště macOS se objeví ikona kamery.
2. V OBS otevřete **Docks → Custom Browser Docks…**.
3. Zadejte název `Camera` a URL `http://127.0.0.1:24680/`.
4. Potvrďte a umístěte dok do požadované části OBS.

Helper musí běžet po dobu používání doku. Z menu ikony lze otevřít ovládání v prohlížeči, zkopírovat URL nebo znovu vyhledat kameru.

Při aktualizaci nejprve ukončete běžící helper přes jeho ikonu v horní liště, potom nahraďte starou aplikaci novou verzí.

## Vlastní sestavení

Vyžaduje Swift toolchain z Xcode Command Line Tools.

```sh
./scripts/build-app.sh
```

Výsledná aplikace bude v `dist/OBS Camera Dock Helper.app`.

## Poznámky

- UVC standard používá místo fotografického ISO parametr `gain`; v rozhraní je proto označený **Gain / ISO**.
- Rozsah a dostupnost ovladačů určuje firmware kamery.
- Pokud CameraController současně přepisuje hodnoty, ukončete jej a nechte nastavení spravovat pouze helper.
- Aplikace naslouchá výhradně na lokální adrese `127.0.0.1`.

## Změny ve verzi 0.1.1

- opraveno zpracování kompozitních USB descriptorů Razer Kiyo V2 X,
- odstraněno zamrznutí po stisku **Vyhledat kameru**,
- přidána bezpečnostní kontrola délky každého USB descriptoru,
- přidán kompatibilní fallback pro UVC control requesty na novějších verzích macOS.

## Licence a původ

Projekt je licencován pod GNU GPL v3, protože obsahuje upravené části UVC implementace z [Itaybre/CameraController](https://github.com/itaybre/CameraController), Copyright © Itay Brenner / Itaysoft. Úplné znění je v souboru `LICENSE`.
