# Analys av macOS HOME-kataloger (.* mappar)

**Status:** Slutgiltig analys av 6 mappar som ligger i HOME
**Datum:** 2026-02-06
**Resultat:** 4 MÅSTE stanna, 2 kan migreras, 1 redan migrerad

---

## Sammanfattning

| Katalog | Storlek | Filer | Status | Åtgärd | Priority |
|---------|---------|-------|--------|--------|----------|
| **.cups** | 4K | 1 | ✅ KEEP | Ingenting | — |
| **.data** | 660K | 3 | ✅ MIGRATABLE | Flytta till ~/.local/share/homebox/ | Låg |
| **.local** | 4.2G | 71k | ✅ KEEP | Ingenting | — |
| **.mg** | 293B | 1 | ✅ MIGRATABLE | Flytta till ~/.config/mg/ | Låg |
| **.npm** | 34M | Tomma | ⚠️ ALREADY MIGRATED | Kan tas bort | Låg |
| **.vscode** | 1.1G | 38k | ✅ KEEP | Ingenting | — |

---

## Detaljerad analys

### 1. **.cups** — ✅ KEEP (Måste stanna i HOME)

**Storlek:** 4K
**Innehål:** 1 fil (`lpoptions` — CUPS-skrivarkonfiguration)
**Senast ändrad:** 2025-05-05

**Varför KEEP:**
- CUPS (Common Unix Printing System) läser hårdkodat från `~/.cups/lpoptions`
- Skrivarkonfiguration för macOS print system
- Kan inte migreras utan att bryta utskrifter

**Åtgärd:** Ingenting. Lämna som det är.

---

### 2. **.data** — ✅ MIGRATABLE (kan flytta)

**Storlek:** 660K
**Innehål:**
- `homebox.db` — SQLite-databas (4K)
- `homebox.db-shm` — Shared memory file (32K)
- `homebox.db-wal` — Write-ahead log (624K)

**Senast ändrad:** 2025-07-14
**App:** Homebox (hembibliotek/inventoriesystem)

**Varför kan migreras:**
- Homebox är ett tredjepartsapp, inte en systemprocess
- SQLite-databas kan flyttas helt enkelt
- Kan sätta XDG_DATA_HOME eller app-specifik miljövariabel

**Rekommendation:**
```bash
# Flytta till XDG-standard plats
mkdir -p ~/.local/share/homebox
mv ~/.data/homebox.db* ~/.local/share/homebox/

# Sätt miljövariabel i ~/.zshenv (om Homebox stöder det)
export HOMEBOX_DATA_HOME="$HOME/.local/share/homebox"
```

**Priority:** Låg (app fungerar fint där den är idag)

---

### 3. **.local** — ✅ KEEP (Redan rätt plats)

**Storlek:** 4.2G
**Innehål:** 71,203 filer (diverse appdata)
**Senast ändrad:** 2026-02-02

**Varför KEEP:**
- **Redan** XDG-standard plats för `$XDG_DATA_HOME`
- Detta är den RÄTTA platsen för applikationsdata
- Inte något problem här

**Åtgärd:** Ingenting. Detta är redan rätt organiserat.

---

### 4. **.mg** — ✅ MIGRATABLE (kan flytta)

**Storlek:** 293 bytes
**Innehål:** `mg.authrecord.json` — Microsoft Graph authentication

**Format:**
```json
{
  "username": "o365admin@Wemo.onmicrosoft.com",
  "authority": "login.microsoftonline.com",
  "homeAccountId": "...",
  "tenantId": "...",
  "clientId": "14d82eec-204b-4c2f-b7e8-296a70dab67e",
  "version": "1.0"
}
```

**Varför kan migreras:**
- Enkel JSON-fil, ingen systemberoende
- Microsoft Graph CLI kan använda miljövariabler
- Kan flytta till `.config/mg/`

**Rekommendation:**
```bash
# Flytta till XDG-standard plats
mkdir -p ~/.config/mg
mv ~/.mg/mg.authrecord.json ~/.config/mg/

# Skapa symlink för bakåtkompatibilitet (om CLI letar i HOME)
ln -s ~/.config/mg/mg.authrecord.json ~/.mg.authrecord.json

# Sätt miljövariabel i ~/.zshenv (om CLI stöder det)
export MG_AUTH_HOME="$HOME/.config/mg"
```

**Priority:** Låg (enkelt och app-specifikt)

---

### 5. **.npm** — ⚠️ REDAN MIGRERAD (kan tas bort)

**Status:** `~/.npm` är TOMMA (nästan)
**Innehål:** Bara tomma cachefiler (_cacache, _logs)
**Aktuell cache:** Ligger redan i `~/.cache/npm` (34M)

**Evidence:**
```bash
$ echo $NPM_CONFIG_CACHE
/Users/brandel/.cache/npm

$ ls ~/.npm/
_cacache/
_logs/
_update-notifier-last-checked
```

**Varför kan tas bort:**
- npm är redan konfigurerat att använda `$NPM_CONFIG_CACHE`
- Faktisk cache ligger redan i `.cache/npm`
- `~/.npm` är bara gamla rester

**Åtgärd:** Kan säkert ta bort

```bash
# Säkerhetskopiera först (för säkerhet)
cp -r ~/.npm ~/.npm.backup.20260206

# Ta bort
rm -rf ~/.npm
```

**Priority:** Låg (redan migrerat, tar bara mindre utrymme)

---

### 6. **.vscode** — ✅ KEEP (Hårdkodad av VS Code)

**Storlek:** 1.1G
**Innehål:** 38,845 filer (extensions, settings, cache)
**Senast ändrad:** 2025-03-28

**Varför KEEP:**
- VS Code är hårdkodat att läsa från `~/.vscode/`
- Kan inte migreras utan att VS Code slutar fungera
- Extensions-installationer och inställningar lagras här

**Åtgärd:** Ingenting. Lämna som det är.

---

## Sammanfattning och rekommendation

### MÅSTE STANNA I HOME (totalt 1.1G + overhead)
1. `.cups` — Systemkonfiguration för utskrift
2. `.local` — Redan rätt XDG-plats
3. `.vscode` — Hårdkodat av applikation

### KAN MIGRERAS (totalt 660K, mycket liten)
1. `.data` → `~/.local/share/homebox/` (660K)
2. `.mg` → `~/.config/mg/` (293B)

### KAN RADERAS (redan migrerat)
1. `.npm` (tomma, bara cacheavfall)

### Rekommendation

**Enkelt:** Gör ingenting. Systemet fungerar bra redan.

**Lite mer städat:** Migrera `.data` och `.mg` när du har tid:
- Båda är mycket små (660K totalt)
- Låg risk, enkla migreringar
- Sparar praktiskt taget ingen diskutrymme men är "snäppare" organiserat

**Maximum städning:** Radera även `.npm`:
- Redan migrerat till `.cache/npm`
- Kan tas bort utan risk

---

## Migration-script (om du vill)

Se filen `migrate-data-and-mg.sh` i samma katalog för ett helt script som hanterar båda migrationerna.

