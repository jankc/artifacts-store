# mp-temp × lnd-artifacts

Podklad k týmové diskusi · 1. 9. 2026 · verze 2

Vyhodnocení dvou existujících řešení správy projektových artefaktů proti dokumentu
„Požadavky na správu AI a projektových artefaktů" (17 požadavků: R0a/R0b + R1–R15),
souhrn silných stránek obou a návrh dalšího postupu. Auditované stavy: mp-temp
@ `4279b83` (30. 8. 2026), lnd-artifacts @ `743eff9`.

## Souhrn

mp-temp plní **8 ze 17 požadavků plně, 4 částečně a 5 neplní** — z toho tři
(konfigurovatelné typy, univerzálnost, izolace klientů) jsou důsledkem záměrných
architektonických rozhodnutí zaznamenaných v jeho vlastních OpenSpec dokumentech,
a vratnost (R14) chybí zcela. lnd-artifacts plní **12 plně, 5 částečně, žádný
neporušuje**; hlavní mezery jsou secret scan, CI a automatika synchronizace.

**Rámování:** nejde o dvě implementace téhož. mp-temp je sdílený firemní znalostní
pool s governance a harvestingem, jehož součástí je transport; lnd-artifacts je pouze
transport. Největší pokrytí požadavků dává kombinace obou: transport lnd-artifacts,
guardy a testovací disciplína mp-temp, harvesting jako vrstva nad tím.

## 1 · Co se srovnává

**mp-temp (lnd-meta-core)**

- Transport je částí pluginu `lnd-meta-core`, vedle governance, sign-offů
  a harvestingu (celkem 14 pluginů).
- Engine `lnd-spec-sync.sh`: 4 510 řádků bashe (verze 114), povinná závislost na
  Pythonu.
- Store: jeden sdílený klon pro všechny projekty na stroji (`~/.lnd/stores/…`),
  dělený cestami `specs-store/<area>/<plugin>/<slug>`.
- Sync automatický: SessionStart pull, Stop hook auto-commit + auto-push, za tty
  potvrzovací bránou.
- Spravuje pevný seznam: openspec, .specify, specs, lnd-doc, grafy. CLAUDE.md,
  .claude/, MEMORY.md, .mcp.json nespravuje.

**lnd-artifacts**

- Jediný účel: transport artefaktů. Bez governance a harvestingu — záměrně.
- Engine: 1 282 řádků POSIX sh, závislost jen git + coreutils; vendoruje se do
  `.git/`, funguje i bez pluginu a agenta.
- Store: 1 privátní repo = 1 klientský projekt, klon v `.git/lundegaard`
  (git common dir → sdílení mezi worktrees, strukturálně necommitovatelné).
- Sync: heal automatický (SessionStart), publish explicitní — Stop hook jen varuje.
- Spravuje libovolnou cestu (`adopt`): první úroveň store rootu = manifest.

## 2 · Scorecard proti požadavkům

✓ splňuje · ◐ částečně · ✗ nesplňuje — evidence = cesty v příslušném repu.

| Požadavek | mp-temp | lnd-artifacts | Poznámka |
|---|---|---|---|
| R0a Konfigurovatelné typy | ✗ | ✓ | mp-temp: seznam natvrdo na 3 místech enginu (`lnd-bootstrap.sh:143`, `lnd-spec-sync.sh:3725, :3287`); nový typ = zásah do enginu. lnd-artifacts: `adopt <cesta>` na cokoli. |
| R0b Nulový overhead | ✓ (po potvrzení) | ◐ (záměrně) | mp-temp po jednorázovém tty potvrzení plně automatický. lnd-artifacts: heal automatický, publish = 1 příkaz, Stop hook připomíná (Z4). |
| R1 Univerzálnost (cesty, ne kategorie) | ✗ (záměrně) | ✓ | mp-temp proposal: „No visible store folder, no user-facing adopt." Generický mechanismus uvnitř existuje, uživatel se k němu nedostane. |
| R2 Kompatibilita (konvenční cesty) | ✓ | ✓ | Oba linkují artefakty do rootu checkoutu pod nativními jmény, bez konfigurace nástrojů. |
| R3 Vlastnictví (žádná stopa v klientském repu) | ✓ | ✓ | Oba: pouze `.git/info/exclude`, nic committovaného. lnd-artifacts navíc: obsah storu je uvnitř `.git/`, tedy strukturálně necommitovatelný. |
| R4 Oprávnění na úrovni projektu | ✗ | ✓ (topologií) | Přístup se přiděluje na úrovni projektu (skupina s více repozitáři); store má být jedním z repozitářů projektu. mp-temp: jeden store pro všechny projekty nemůže patřit do žádné projektové skupiny; per-caller scoping jen jako nenasazený prototyp (`tools/store-gateway`: „working prototype, never deployed"). lnd-artifacts: store 1 : 1 se do projektové skupiny zařadit dá a oprávnění zdědí. Není to ale prostá kopie oprávnění repa a má to konsekvence — viz T1. |
| R5 Izolace klientů (hranice úložiště) | ✗ (default sdílený) | ✓ (konstrukcí) | mp-temp: izolace je opt-in (`declare-store <url>`); default je sdílený pool dělený jen adresářovou strukturou — přesně to, co R5 zakazuje (Z2). |
| R6 Ochrana proti úniku | ◐ | ◐ | mp-temp: silná vrstva 1 + otestovaný secret scan a brzda hromadného mazání; ale doctor exclude blok nekontroluje a grafy se stagují `git add -A`. lnd-artifacts: silná strukturální ochrana (store v `.git/`, karanténa, odmítání tracked cest), ale chybí secret scan před pushem. |
| R7 Explicitní souhlas, min. konfigurace | ✓ | ✓ | Oba: nic bez explicitní inicializace, jediný parametr = URL storu. Kredit mp-temp: tty brána + retroaktivní revokace potvrzení. |
| R8 Minimální tření, worktrees | ◐ | ✓ | mp-temp řeší worktree exclude správně (common dir, pokryto testem), ale potvrzení storu je per-worktree a onboarding má 2–3 kroky vč. reálného terminálu. lnd-artifacts: worktrees jsou důvod celého designu; nový worktree = SessionStart heal, bez agenta 1 vendorovaný příkaz. |
| R9 Fail-soft | ✓ | ✓ | mp-temp bohatší (per-file parking konfliktů, retry na dalším Stopu). lnd-artifacts: lock, konflikt se ohlásí a nechá k ručnímu řešení, nic se neztrácí. |
| R10 Jedno vlastnictví transportu | ✓ | ✓ | mp-temp: 1 engine + shimy, self-install; přiznaná 4× duplikace secret patternů. lnd-artifacts: 1 skript; vendorovaná kopie je verzovaná cache obnovovaná healem. |
| R11 Přenositelnost | ◐ | ◐ | mp-temp: +Windows (junctions „UNVERIFIED"), −povinný Python. lnd-artifacts: POSIX sh + git, Claude i Codex ověřeny end-to-end, −Windows. |
| R12 Pozorovatelnost | ◐ | ◐ | mp-temp doctor (775 ř.) kontroluje hodně, ale ne exclude blok — invariant č. 1. lnd-artifacts `status` je užší, pokrývá store/linky/engine; heal exclude přepisuje idempotentně. |
| R13 Testovatelnost (e2e v CI) | ✓ | ◐ | mp-temp vede: 23 suit (~5 500 ř.), 5 CI jobů. lnd-artifacts: 834řádkový e2e smoke, ale zatím žádná pipeline. |
| R14 Migrace a vratnost | ✗ | ✓ | mp-temp nemá uninstall/teardown; `declare-store off` nechá symlinky do `~/.lnd/stores` žít (brána končí před unlinkem, `:1336`), exclude blok se neodstraňuje. lnd-artifacts: `detach` ↔ `heal` round-trip je specifikovaný a testovaný. |
| R15 Vytěžitelnost | ✓ (pohodlněji) | ✓ (věrněji vůči ACL) | mp-temp: 1 klon = celý pool. lnd-artifacts: standardní struktura per projekt; harvester enumeruje repa přes naming konvenci — čte přes stejná ACL jako lidé, jak R15 výslovně požaduje. |

**Součet:** mp-temp 8 ✓ · 4 ◐ · 5 ✗ — lnd-artifacts 12 ✓ · 5 ◐ · 0 ✗. Tři z pěti ✗
u mp-temp nejsou bugy, ale zaznamenaná designová rozhodnutí — nezmizí opravou, jen
změnou architektury.

## 3 · Klíčová zjištění

### Z1 — Požadavky R0a a R1 jsou v mp-temp odmítnuty designovým rozhodnutím

> „Synced set stays a fixed, curated whitelist (engine-defined: `openspec/`,
> `.specify/`, `specs/`, plus `lnd-doc/`). No visible store folder, no user-facing
> `adopt`. A new shareable artifact type is added by a deliberate, reviewed engine
> change."
> — mp-temp: `openspec/changes/store-topology-and-linked/proposal.md`

Důsledek proti kapitole „Co jsou artefakty": mp-temp nespravuje CLAUDE.md, .claude/,
MEMORY.md, .mcp.json, .superset/ ani orca.yaml — první dvě kategorie z definice.
Dokument přitom říká „množina artefaktů není uzavřená"; v mp-temp každé rozšíření
znamená zásah do enginu na třech místech.

### Z2 — Sdílený store je v rozporu s R4 + R5 a rizika se už materializovala

Default je jeden firemní store pro všechny projekty, oddělené jen adresáři; vynucení
hranic je podle vlastní dokumentace sociální („…informed socially by the area
leaders — there is no central enforcement"). Incident, který R5 předjímá, se už stal:

> „11 Aug: 94 files and 10 007 lines of a client's specifications left the store in
> one such push." … blocked-clients.json: „Empty on 2026-08-18: the one entry (Ceska
> posta) came from an afternoon when 94 files of a client's specifications had just
> left the store."
> — mp-temp: `lnd-spec-sync.sh:3487` · `governance/blocked-clients.json`

Mitigace: aktuálně prázdný blocklist, tty prompt (vlastními slovy „a speed bump, not
a lock") a nenasazená gateway. Model 1 repo = 1 klient tuto třídu selhání ruší
konstrukcí — hranice transportu = hranice úložiště s vlastními ACL, což je doslovná
formulace R5. Per-klientské story ostatně předjímá i samotný požadavkový dokument
(úkol „naming conventions pro artefakt stores repa / per client").

### Z3 — Vratnost (R14) v mp-temp neexistuje

V `lnd-meta-core` není uninstall ani teardown. `declare-store off` vypne sync před
jakýmkoli unlinkem — projektové artefakty zůstanou symlinky do `~/.lnd/stores/…`,
které se už nesynchronizují; `rm -rf ~/.lnd` pak zničí jedinou kopii. Exclude blok se
při odchodu neodstraňuje. lnd-artifacts má `detach` ↔ `heal` round-trip jako
specifikovaný a testovaný požadavek. R14 přitom zní: „odstranění systému nezanechá
stopy v klientském repu ani neztratí artefakty."

### Z4 — Automatika vs. explicitní publish: incidenty vs. overhead

Oba zaznamenané incidenty mp-temp způsobil automatický push bez člověka v cestě: únik
94 souborů (Z2) a částečně pushnutý Azure klíč („a 235 KB diff with the hit at 37 KB
pushed a partial Azure key"). mp-temp na to reaguje přidáváním brzd za automat;
lnd-artifacts automat u nevratného kroku nemá — heal (bezpečný, lokální) je
automatický, publish (ven) explicitní, s připomínkou na Stop hooku. Je to rozdílný
výklad dvojice požadavků R0b (automatika) × R7 (explicitní souhlas) — téma T2.

### Z5 — Poměr složitosti a pokrytí

Transport mp-temp: 4 510 ř. bash + ~20 helperů + povinný Python, engine ve verzi
114. lnd-artifacts: 1 282 ř. POSIX sh, git + coreutils, obě runtime ověřené.
Jednodušší řešení pokrývá víc požadavků dokumentu; složitost mp-temp platí za
governance a sdílený pool — vlastnosti, které dokument nepožaduje.

## 4 · Silné stránky mp-temp k převzetí

- **Secret scan před pushem** (`has_secret` + `_secret_scan.py`) — kalený dvěma
  reálnými incidenty, fail-closed. Pokrývá část R6, kterou lnd-artifacts nemá.
- **Brzda hromadného mazání** (≥10 delecí, 0 adicí → abort) — levná, ověřená.
- **Testovací disciplína a CI** — 23 suit, 5 jobů, grill testy, poctivě přiznané
  limity („Green here is not green there.").
- **Šířka doctoru** — SSH reachability vs. přístup k repu, upstream tracking, stale
  lock; inspirace pro rozšíření `status`.
- **Parking konfliktů per soubor** — přívětivější než holé „rebase se zastavil".
- **Windows know-how** (junctions, git-bash, Store-alias past) a provozní zkušenost
  zapsaná v komentářích.

## 5 · Očekávaná témata diskuse

### T1 — Model oprávnění: store jako repo projektu

- **Cílový model:** přístup vývojářů se přiděluje na úrovni projektu (GitLab skupina
  s více repozitáři) — artefaktový store jako další repo skupiny oprávnění přirozeně
  zdědí.
- **Není to prostá kopie oprávnění jednoho repa.** K dořešení: kdo smí story
  zakládat, přístup lidí mimo projekt (harvesting, cíle 3–4), vazba na ISO úrovně.
- **Napětí R4/R5 × R15** jmenuje i samotný požadavkový dokument v „Bodech
  k dořešení".
- **Podpora:** sdílený store mp-temp tento model nepodporuje vůbec; model 1 : 1
  ano — infra proces je ale potřeba definovat (v dokumentu už zadáno).
  Proveditelnost v mp-temp rozebírá T6.

### T2 — Automatická vs. explicitní synchronizace

- **Jádro sporu:** R0b žádá nulový overhead, R7 explicitní souhlas — dva výklady
  téže dvojice.
- **mp-temp:** „potvrdit jednou, pak plný automat" — cenu ukazují oba zaznamenané
  incidenty (Z4).
- **lnd-artifacts:** „automatické vše bezpečné, explicitní jediný nevratný krok" —
  cena: jeden příkaz navíc, připomínaný Stop hookem.
- **Možný kompromis:** default explicitní, opt-in auto-sync per projekt s guardy
  (secret scan, brzda mazání).

### T3 — Sdílený pool vs. izolované story

- **Hodnota poolu** („připojíš se k projektu, máš specs domény") je ve *čtení*
  napříč projekty — tu lze postavit i nad izolovanými story: enumerace rep dle
  naming konvence, případně server-side mirror (směr, kam míří prototyp
  store-gateway).
- **Opačný směr nefunguje:** do sdíleného poolu se izolace, per-klient ACL
  a vratnost zpětně dostavět nedají.
- **Ani multi-repo projekty pool nevyžadují** (v Javě běžné — repo per service):
  jedno artefakt-repo projektu, větev per hostitelské repo + společná větev
  `common`, bez změny enginu — podrobně „Umístění artefaktového storu", kap. 6.

### T4 — Kurátorovaný whitelist vs. adopt-anything

- **Motivace whitelistu je legitimní** — kontra-návrh „synchronizovat jen schválené
  artefakty" je i v požadavkovém dokumentu.
- **Mechanismus × politika se nevylučují:** univerzální mechanismus (cesty)
  + kurátorovaná politika (schválený seznam spravovaný správcem — přesně R0a).
- **Rozdíl je v ceně změny:** nad univerzálním mechanismem je politika levný doplněk
  (seznam ve skillu, review store repa); nad mechanismem zadrátovaným v enginu se
  politika bez zásahu do kódu změnit nedá.

### T5 — Provozní zralost

- **mp-temp:** nasazený, testy podložený. **lnd-artifacts:** novější, v produkci
  neověřený.
- **Ale:** většina oprav v historii mp-temp řeší důsledky vlastní architektury —
  sdílený store, auto-push, per-spec mirroring (např. vlastní drafted bug report na
  openspec CLI přeskakující symlinkované změny).
- **lnd-artifacts tyto třídy chyb odstraňuje konstrukcí;** co mu chybí (CI, secret
  scan), je přenositelné z mp-temp.

### T6 — Dá se R4/R5 v mp-temp dodělat? (showstopper, nebo ne)

Izolaci klientských dat zajistit jde, ale ne při zachování modelu. Per-cestu read
ACL git ani GitLab neumí, takže existují jen tyto cesty:

- **Cesta 1 — překlopit default na per-klientské story.** Mechanismus existuje
  (`declare-store` restricted store), technicky ~týden včetně testů. Ale zmizí
  sdílený pool („This shared pool IS the value"), harvest skilly mají cesty poolu
  zadrátované — a z transportu zbyde dražší reimplementace topologie 1 : 1.
  Whitelist typů (R0a/R1) a vratnost (R14) zůstávají samostatnou prací.
- **Varianta cesty 1 — story per skupina projektů se shodnými oprávněními.** Literu
  R4 na čtecí straně splní, ale třídy shodných oprávnění nejsou stabilní v čase
  (týmy rotují, projekty se předávají do správy) — rozchod tříd = migrace projektu
  do jiného storu, neprovedená migrace = tichý drift přístupů. Kvůli R5 skupina
  nesmí překročit jednoho klienta, takže i tahle varianta kolabuje na „store per
  klientský projekt". Pool mp-temp je navíc dělený podle area, ne podle tříd
  oprávnění — byla by to jeho přestavba.
- **Cesta 2 — zachovat pool a předřadit gateway** (per-caller scoping, prototyp
  `tools/store-gateway`). Jediná cesta, jak mít pool i R4 zároveň. Cena: měsíce
  práce + provoz služby, transport přestane být git (ztráta offline/fail-soft
  vlastností lokálního klonu), vznikne centrální bod s daty všech klientů a všemi
  tokeny. Dnes „working prototype, never deployed".
- **Cesta 3 — šifrování per klient v jednom repu.** Nefunkční: revokace klíčů
  zpětně nejde, šifrované bloby rozbijí diff/merge (celý parking konfliktů)
  i vytěžování.

**Závěr:** R4/R5 není nedodělek, ale designové rozhodnutí — pro roli transportu
klientských artefaktů diskvalifikující, dokud požadavky platí v dnešním znění.
Zmírnění (např. pool jen pro neklientský obsah) je bezpečnostní rozhodnutí
vyžadující explicitní podpis (NDA/ISO), ne inženýrská volba. mp-temp sám s tím
zachází jako s nevyřešeným: `RETURN-MAP.md` podmiňuje návrat transportu security
modelem „pending legal", knowhow kanál má „No poznatek is pushed anywhere until
this comes back". Pro znalostní vrstvu (harvesting, governance) showstopper není —
funguje i nad izolovanými story.

## 6 · Návrh dalšího postupu

- **Transport = lnd-artifacts.** Per-projektový store v git common dir,
  adopt/heal/sync/detach, dual-runtime. Pokrývá R1–R8 a R14 konstrukcí.
- **Guardy = z mp-temp.** Secret scan před pushem a brzda hromadného mazání portovat
  do `sync`.
- **Kvalita = disciplína mp-temp.** CI pipeline nad smoke suitou; postupné rozšíření
  `status` o doctor-checks včetně exclude bloku.
- **Harvesting a grafy = vrstva nad transportem.** Harvest skilly a multirepo-graph
  čtou per-projektová repa dle naming konvence; store-gateway je vhodný tvar pro
  budoucí company-wide čtecí přístup (server-side, per-caller scoping).
- **Automatika = otevřené rozhodnutí** (T2): default explicitní, opt-in automat
  s guardy jako možný kompromis.

Kombinace pokrývá všech 17 požadavků a zachovává z obou řešení to nejsilnější:
topologii a transport lnd-artifacts, guardy, testovací kulturu a znalostní vrstvu
mp-temp.

## 7 · Známé mezery lnd-artifacts

- **Secret scan před pushem** (R6) — nejvážnější mezera; plán: převzít z mp-temp.
- **CI** (R13) — e2e smoke existuje, pipeline chybí; plán: přidat.
- **Automatika synchronizace** (R0b) — záměr, viz Z4/T2.
- **Windows** (R11) — vědomý scope cut; know-how existuje v mp-temp i ailienu.
- **status užší než doctor** (R12) — rozšiřovat postupně.

## 8 · Doplňující fakta

- V mp-temp (poslední commit 30. 8. 2026) není žádná stopa po požadavkovém dokumentu
  (grep „hostitelsk*", „požadav*", číslování R1–R15: 0 zásahů) — toto je první
  ověření proti jeho textu.
- `RETURN-MAP.md` označuje mp-temp za „temporary pilot clone" čekající na
  architektonické a bezpečnostní rozhodnutí — tedy na tuto diskusi.
- Doctor nekontroluje `.git/info/exclude`; `has_secret` čte `PIPESTATUS[1]` místo
  `[0]` (selhání `git diff` projde jako čistý sken); grafy se stagují `git add -A`
  bez extension whitelistu.
- Potvrzení sdíleného storu vyžaduje reálné tty — v čistě agentním/CI prostředí se
  defaultní store nedá zapnout (bypass env proměnnou je zdokumentovaný).

---

Zdroje: DLVR-Požadavky na správu AI a projektových artefaktů (1. 9. 2026) ·
`/Users/jank/dev/work/lunde/mp-temp` @ `4279b83` · `/Users/jank/dev/work/lunde/lnd-artifacts`
@ `743eff9` · hloubkový audit obou repozitářů, 1. 9. 2026. Hodnocení se týká výhradně
vrstvy správy artefaktů (lnd-meta-core transport); governance, sales a FE pluginy
mp-temp nebyly předmětem srovnání. Webová verze:
https://claude.ai/code/artifact/2d582e93-a5d0-48f3-9906-3ddac885dfe8
