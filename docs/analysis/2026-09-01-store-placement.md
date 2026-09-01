# Umístění artefaktového storu

Podklad k týmové diskusi · 1. 9. 2026 · doplněk ke srovnání mp-temp × lnd-artifacts

Podrobný rozbor tří možností, kde na disku žije lokální klon artefaktového storu:
v git common diru (`.git/lundegaard`), v pracovním stromě (`.lundegaard/`), nebo mimo
repo ve sdíleném adresáři (`~/.lnd/stores/…`).

## Souhrn

Pro per-projektový store vychází nejlépe **git common dir** — jako jediné umístění
řeší worktrees bez konfigurace, je strukturálně neodeslatelné na klientský remote
a nepotřebuje žádný mapovací stav. Jeho reálné slabiny (ztráta neodeslaných změn při
smazání `.git`, zálohy, archiv checkoutu včetně `.git`) jsou známé a mitigovatelné.
**`~/.lnd` mimo repo** má dvě skutečné výhody — store přežije checkout a obsah není
v archivu checkoutu — ale platí za ně mapovacím stavem, úklidem a koncentrací všech
klientů do jednoho místa; je to *nutné* umístění, pokud je store sdílený mezi
projekty. **`.lundegaard/` v pracovním stromě** je dominované řešení: kombinuje
nevýhody obou a přidává vlastní (git clean, worktrees, `git add -f`); v podobě
lnd-core v1 už selhalo.

## 1 · Tři kandidáti a jedna poznámka předem

- **A · `.git/lundegaard`** — klon storu uvnitř git common diru hostitelského repa.
  Symlinky z rootu worktree dovnitř. Dnešní model lnd-artifacts.
- **B · `.lundegaard/` v pracovním stromě** — klon storu jako ignorovaný adresář
  vedle kódu. Symlinky z rootu na jeho obsah. Model lnd-core v1 (opuštěný).
- **C · `~/.lnd/stores/<jméno>`** — klon storu úplně mimo repo, v domovském
  adresáři. Symlinky z rootu checkoutu ven z repa. Dnešní model mp-temp.

**Umístění ≠ topologie.** Otázka „kde leží klon" je nezávislá na otázce „jeden store
per projekt, nebo sdílený pool". Per-projektový store může ležet kdekoli z A/B/C;
sdílený store mezi projekty *vynucuje* C (nemá „svoje" repo, do jehož `.git` by
patřil). mp-temp tedy C nezvolil kvůli kvalitám umístění — vyplynulo z topologie.
Tento rozbor srovnává umístění za předpokladu per-projektového storu; kde je
vlastnost důsledkem sdílené topologie, je to řečeno.

Ve všech třech modelech se artefakty do checkoutu promítají symlinky z rootu —
rozdíl je jen v tom, kam linky vedou. Vlastnosti symlinků (nástroje je nenásledují
bez `-L`, openspec CLI je u change adresářů přeskakuje) jsou tedy společné
a v rozhodnutí nehrají roli.

## 2 · Souhrnná tabulka

| Dimenze | A · .git/lundegaard | B · .lundegaard/ | C · ~/.lnd |
|---|---|---|---|
| Git worktrees | ✓ zdarma (common dir je sdílený) | ✗ selhává (kopie per worktree) | ✓ funguje, nutný mapovací stav per worktree |
| Strukturální ochrana před commitem | ✓ obsah v .git | ✗ `git add -f` přidá obsah | ✓ obsah mimo repo |
| `git clean -ffdx` | ✓ imunní | ✗ smaže store | ✓ imunní (jen linky, heal je vrátí) |
| `rm -rf .git` / nuke-and-reclone | ✗ ztratí nepushnuté | ◐ přežije .git, ne smazání adresáře | ✓ přežije |
| Archiv checkoutu (tar vč. .git), image build | ◐ obsah jde s .git | ✗ obsah jde vždy | ✓ jen dangling linky |
| Mapování checkout → store | ✓ žádné (pozice = mapa) | ✓ žádné | ✗ nutný stav (config keyed by path/remote) |
| Přesun/přejmenování checkoutu | ✓ store jde s ním | ✓ store jde s ním | ◐ linky přežijí, mapovací stav se musí obnovit |
| Více checkoutů téhož repa | ◐ store per klon, sync přes remote | ◐ store per checkout | ✓ jeden klon pro všechny |
| Multi-repo projekt (1 store, N rep) | ◐ klon per repo, propagace přes remote | ◐ totéž | ✓ jeden lokální klon |
| Životnost / úklid | ✓ zaniká s projektem (remote = záloha) | ✓ zaniká s projektem | ✗ sirotci — přežívá, nikdo neuklízí |
| Koncentrace důvěrných dat | ✓ per projekt | ✓ per projekt | ✗ všichni klienti v jednom stromě |
| Zálohy stroje | ◐ nástroje .git přeskakují | ✓ zálohuje se s projektem | ✓ běžný adresář |
| Viditelnost pro nástroje v pracovním stromě | ✓ skrytý | ✗ viditelný (lintery, globy, indexace) | ✓ skrytý |

## 3 · Rozbor po dimenzích

### 3.1 Git worktrees

`git rev-parse --git-common-dir` z libovolného worktree vede do `.git` hlavního
klonu. Store v common diru (A) tak **všechny worktrees sdílejí automaticky** — bez
konfigurace, bez stavu; per-worktree jsou jen symlinky, které vytvoří heal. Zároveň
`info/exclude` žije tamtéž, takže jeden managed blok kryje všechny worktrees. B je
přesný opak: pracovní strom se mezi worktrees nesdílí, každý worktree by měl vlastní
klon storu a vlastní divergenci — přesně na tomhle lnd-core v1 selhal a byl opuštěn.
C funguje (obsah je mimo repo), ale musí si per checkout/worktree pamatovat, který
store k němu patří — v mp-temp je to config klíčovaný hashem absolutní cesty, takže
potvrzení storu se odpovídá v každém worktree zvlášť.

### 3.2 Ochrana před odesláním na klientský remote

Všechny tři modely spoléhají na managed blok v `.git/info/exclude` pro symlinky
v rootu. Rozdíl je v tom, co se stane, když ochrana selže (blok někdo smaže,
`git add -f`):

- **A a C:** commitnout jde nejvýš symlink — git ho uloží jako soubor s textem
  cílové cesty (mode 120000). Uniká tedy jen řetězec cesty, nikdy obsah. U A navíc
  obsah leží pod `.git/`, kam git z principu žádnou cestou nesáhne.
- **B:** `.lundegaard/` je skutečný adresář v pracovním stromě —
  `git add -f .lundegaard` commitne *celý obsah storu* do klientského repa. Jediný
  model, kde selhání ignorace znamená únik obsahu, ne jen cesty.

### 3.3 Destruktivní operace v pracovním stromě

`git clean -ffdx` (běžný „scorched earth" recept, mj. v CI úklidech — druhé `-f`
existuje právě kvůli mazání vnořených rep) u B smaže store včetně nepushnutých
commitů. A i C jsou imunní: clean smaže jen symlinky, které heal idempotentně
obnoví. `git stash --all` vnořené repo přeskakuje (ověřeno na git 2.50.1), ale
spoléhat na to u B znamená spoléhat na detail chování gitu.

### 3.4 Zničení klonu: rm -rf .git, nuke-and-reclone

Nejsilnější argument proti A: kdo smaže `.git` nebo celý checkout a naklonuje
znovu, přijde o **nepushnuté** změny storu — store bydlel uvnitř. C tady vítězí:
store přežije jakoukoli manipulaci s checkoutem. Váhu argumentu snižují tři věci:
remote storu je vždy zdrojem pravdy (ztratit jde jen to, co nebylo synchronizováno);
Stop hook na nesynchronizovaný stav hlasitě upozorňuje; a „smazal jsem projekt"
u per-projektových artefaktů znamená ztrátu dat i v C — jen odloženě (viz 3.7).
Pro B platí horší varianta: přežije sice smazání samotného `.git`, ale ne smazání
adresáře projektu ani clean.

### 3.5 Archiv checkoutu a image build

Požadavkový dokument (R6) žádá minimalizaci rizik mimo git právě umístěním storu.
Zde je pořadí opačné než jinde:

- **C:** tar/zip adresáře i `docker COPY . .` vezmou jen symlinky, které mimo
  původní stroj nikam nevedou. Obsah neunikne. Nejčistší.
- **A:** `git archive` bere jen trackované soubory — bezpečné. Ale prostý tar
  adresáře nebo image build, který nevyloučí `.git`, přibalí i store. Mitigace je
  konvenční (`.dockerignore` s `.git` je standard, artefakty pro klienta se z `.git`
  nestaví), ne strukturální.
- **B:** reálný adresář jde do každého taru a každého image, a na rozdíl od `.git`
  ho žádná konvence nevylučuje.

### 3.6 Mapování, stav a identita

U A (i B) je pozice storu zároveň mapou: „store tohoto checkoutu" je deterministická
funkce `git rev-parse`, žádný konfigurační stav neexistuje, tudíž nemůže být
zastaralý, ztracený ani ukazovat jinam. C potřebuje odpověď na „který store patří
k tomuhle checkoutu" uloženou bokem — klíčovanou cestou (mp-temp: hash absolutní
cesty; rozbije se přesunem checkoutu), nebo remote URL (robustnější, ale řeší kolize
dvou checkoutů s různou rolí). Je to druhý zdroj pravdy se všemi režimy driftu,
které A strukturálně nemá.

### 3.7 Životnost, úklid, koncentrace dat

A váže život lokálního klonu storu na život projektu na disku: smazáním projektu
zmizí i jeho artefakty (remote zůstává). To je zároveň úklid i offboarding — po
konci práce na klientovi nezůstává na stroji nic. C store od projektu odděluje:
přežije reclone (výhoda), ale nikdo ho nikdy nesmaže (sirotci v `~/.lnd/stores` po
dávno opuštěných projektech) a všichni klienti leží v jednom podstromě domovského
adresáře — jedno místo, jeden blast radius při kompromitaci stroje, jedna položka
pro exfiltraci. U per-klientských důvěrných dat je rozptýlení po projektech (A)
konzervativnější default.

### 3.8 Více checkoutů a multi-repo projekty

Jediná kategorie, kde C strukturálně vede. Dva klony téhož repa na jednom stroji
(mimo worktrees) mají v A dva store klony a vidí se navzájem až přes remote; v C
sdílejí jeden lokální klon a změny jsou viditelné okamžitě. Totéž pro projekt
rozprostřený přes N repozitářů: A klonuje tentýž store do každého repa (funguje bez
úprav — init se stejnou URL; propagace přes sync), C má jeden lokální klon pro
všechny. Protiváha: sdílený lokální klon je zase sdílený mutable stav — souběžné
sessions přes projekty se musí serializovat globálním lockem a nehody typu
„unscoped `git checkout -- .` v klonu" zasáhnou cizí projekt (mp-temp na obojí má
kód i komentáře). V A je lock i poškození vždy omezené na jeden projekt.

### 3.9 Zálohy a vyhledávání

Drobnosti, ale reálné: zálohovací nástroje často přeskakují `.git` — store v A se
nezálohuje (mitigace: remote je záloha; eager sync). C i B se zálohují normálně.
Vyhledávací nástroje nesledují symlinky (`rg -L`) — společné všem třem modelům.

## 4 · Historická poznámka

Varianta B není hypotéza — byla to první verze lnd-core (store v `.lundegaard/`,
symlinky přes `linked/` mapu) a opustila se právě kvůli worktrees a nutnosti
per-worktree klonů a ignorací. Předchůdcem dnešního A byl plán
`lnd-store-in-git-common-dir` v ai-marketplace repu, který myšlenku common diru
validoval; mp-temp mezitím přešel na C spolu s přechodem na sdílenou topologii.
Známé slabiny C v mp-temp (stav klíčovaný hashem cesty, per-worktree potvrzování)
jsou implementační volby, ne nutné vlastnosti umístění — férové srovnání s C počítá
s tím, že by šly udělat lépe.

## 5 · Závěr

- **Per-projektový store → A (`.git/lundegaard`).** Jediné umístění, které současně
  řeší worktrees bez stavu, strukturálně brání úniku obsahu do klientského repa
  a nepotřebuje mapování. Akceptované náklady: nepushnuté změny nepřežijí zničení
  `.git` (mitigace: Stop warning, status, návyk syncovat), `.git` v záloze/taru
  (mitigace: remote, konvence `.dockerignore`).
- **C (`~/.lnd`) je legitimní tam, kde platí jeho předpoklady:** sdílená topologie
  (pak je jedinou možností), silný důraz na přežití storu nezávisle na checkoutu,
  nebo časté image buildy z adresářů včetně `.git`. Cena: mapovací stav, globální
  lock, úklid a koncentrace klientských dat. Úplný výčet scénářů, které by C
  vyžadovaly, rozebírá kapitola 6.
- **B (`.lundegaard/` v pracovním stromě) nedoporučit:** nemá žádnou dimenzi, ve
  které by bylo nejlepší, a je jediné, kde `git clean` maže store a `git add -f`
  commitne obsah. Empiricky už jednou selhalo.

## 6 · Kdy je C skutečně nutné — a případ multi-repo projektů

### 6.1 Scénáře, které by vyžadovaly umístění mimo repo

**Tvrdě vynucují C** (store nemá žádné `.git`, do kterého by patřil):

- **Sdílený pool mezi klienty/projekty** (mp-temp default) — store nepatří žádnému
  hostitelskému repu. Zároveň jediný scénář, který požadavky (R4, R5) zakazují.
- **Artefakty k něčemu, co není git repo** (složka dokumentace bez checkoutu) —
  okrajové, mimo dnešní scope.
- **Efemérní checkouty** (CI runnery, zahazované devcontainery) — v A se store
  zahazuje s checkoutem a každý start klonuje znovu; C funguje jako lokální cache.
  Vývojářských strojů se netýká.

**Vyžadují C jen při konkrétním výkladu požadavku:**

- **Okamžitá lokální propagace** mezi repy projektu nebo mezi dvěma klony téhož
  repa — bez remote round-tripu. Pokud stačí propagace přes remote (jeden `sync`),
  C není potřeba — viz 6.2.
- **Lokální přežití nepushnutých změn** i po zničení checkoutu — jestli je to
  požadavek, nebo akceptovaný náklad s mitigací (Stop warning), je rozhodnutí
  k diskusi (3.4).

**Tlačí k C, ale mají lepší alternativy:**

- Velké artefakty (grafy, binární exporty) a deduplikace disku → velké artefakty do
  storu nepatří (LFS, artefaktové úložiště).
- Lokální nástroje čtoucí napříč projekty (harvester, graph-joiner) → enumerace přes
  GitLab nebo server-side mirror/gateway; vytěžování stejně míří na sdílenou
  infrastrukturu, ne na laptop.
- Rutinní tary/image buildy včetně `.git` → primárně konvence (`.dockerignore`),
  viz 3.5.

**Co C nevyžaduje, i když to tak vypadá:** sdílení v týmu (řeší remote), worktrees
(A nativně), zálohy (remote je záloha), přesun checkoutu (v A jde store s ním).

### 6.2 Multi-repo projekty fungují nad A

Frontend řeší více aplikací zpravidla monorepem; v Javě je běžné obojí —
Maven/Gradle multi-module projekt (ekvivalent monorepa), ale u microservice
a enterprise projektů často repo per service plus infra repo. Klientský projekt tak
může být hrst repozitářů. Pro monorepo je otázka triviální (jedno repo = jeden
store); multi-repo je jediný případ, který vyžaduje rozmysl.

Klíčové pozorování: „sdílet artefakty mezi repy" v silném smyslu (stejné soubory
nalinkované všude) je potřeba jen pro malou podmnožinu. Artefakty se dělí na
**per-repo** (`CLAUDE.md` dané codebase, `.claude/`, openspec changes služby —
linkovat je křížem by bylo aktivně špatně) a **per-projekt** (PRD, doménový slovník,
architektonická rozhodnutí přesahující služby — ty chce agent v každém repu). Cíl
tedy není synchronizovat totéž všude, ale mít všechny artefakty projektu *na jedné
hromadě v jednom artefakt-repu* — kvůli uchování know-how (nový správce klonuje
jedno repo a vidí celý projekt) i vytěžování.

Model nad A (analyzováno v lnd-artifacts `docs/CONTEXT.md` §6, funguje bez změny
enginu):

- jedno artefakt-repo per projekt; `init <stejná URL>` v každém hostitelském repu
  (klon v jeho `.git/lundegaard`),
- **větev per hostitelské repo + větev `common`**, ze které se merguje; heal linkuje
  strom checkoutnuté větve, takže každé repo dostane jen svou sadu,
- proč větve, ne podadresáře: první úroveň store rootu = manifest linků,
  podadresáře by se nalinkovaly do každého repa všechny — a filtr „která složka
  patří komu" by znamenal manifest, tedy druhý zdroj pravdy. Strom větve je výběr,
  git je mechanismus.

Oproti C je horší jen dvojí: propagace jde přes remote (repo B vidí push z repa
A až po vlastním `sync`; auto-pull v hooku byl zamítnut záměrně — hooky nesmí
mutovat store) a N klonů na disku (u textových artefaktů zanedbatelné). Lepší je
naopak izolace selhání (lock i případné poškození klonu per repo, ne per projekt)
a nulový mapovací stav. Přijaté náklady: změna v `common` = N mergů; a žádný projekt
takhle zatím reálně neběží — je to analýza, ne ověřená praxe.

**Důsledek pro celkové rozhodnutí:** multi-repo projekt nevyžaduje ani C, ani
sdílený pool — stačí „1 store = 1 klientský projekt" s větvemi. Jediným tvrdým
důvodem pro C tak zůstává sdílený pool mezi klienty, který požadavky zakazují.

---

Zdroje: lnd-artifacts `docs/CONTEXT.md` (§2 — ověřené chování git clean/stash na
git 2.50.1, §6 — multi-repo analýza) · audit mp-temp @ `4279b83` (`_state.sh`,
`lnd-bootstrap.sh`, `lnd-spec-sync.sh`, `transport.md`) · lnd-core v1
v ai-marketplace (reference) · DLVR-Požadavky na správu AI a projektových artefaktů,
R6. Navazuje na dokument „mp-temp × lnd-artifacts" z téhož dne.
