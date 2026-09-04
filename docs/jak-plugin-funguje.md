# lnd-artifacts — jak plugin funguje

Stručný popis pro kolegy a vedení. Detailní referenci má `README.md`.

## Problém

Při práci s AI agenty (Claude Code, Codex) vznikají v projektu soubory jako `.claude/`,
`openspec/` nebo `CLAUDE.md`. Chceme je verzovat a sdílet v týmu, ale **nesmí se dostat do
repozitáře zákazníka**. Ruční `.gitignore` je křehký a artefakty pak nikde nežijí.

## Řešení v jedné větě

Artefakty žijí ve **vlastním privátním git repozitáři**, který je naklonovaný *dovnitř*
adresáře `.git/` zákaznického projektu a do kořene projektu jen **nasymlinkovaný**.

```
customer-project/
  .git/
    lundegaard/          <- artefaktový repozitář (běžný git clone)
      .claude/
      openspec/
      CLAUDE.md
    lundegaard.engine.sh <- kopie skriptu pluginu (funguje i bez pluginu)
    info/exclude         <- spravovaný blok ignorující symlinky níže
  .claude      -> .git/lundegaard/.claude
  openspec     -> .git/lundegaard/openspec
  CLAUDE.md    -> .git/lundegaard/CLAUDE.md
  src/ ...                (obsah zákazníka, nedotčený)
```

Proč právě `.git/`:

- **Nemůže uniknout.** Nic uvnitř `.git/` nelze commitnout do zákaznického remote.
- **Čistý `git status`.** Symlinky jsou ignorované přes `.git/info/exclude`, tedy bez zásahu
  do souborů zákazníka.
- **Worktrees zdarma.** Všechny worktrees jednoho klonu sdílejí jeden store i remote.
- **Přežije `git clean -fdx`.** Clean smaže jen symlinky, ne store; plugin je obnoví.

### Nulová konfigurace

Hlavní přednost návrhu je, že **nic není třeba konfigurovat ani udržovat**. Všechno, co
plugin potřebuje vědět, plyne z polohy souborů:

- **Kde je store.** Vždy `<git common dir>/lundegaard`. Cesta se nikde neukládá, spočítá
  se z aktuálního adresáře přes `git rev-parse --git-common-dir`. Proto stejný výpočet
  funguje v hlavním klonu, v každém worktree i ve skriptu bez pluginu.
- **Co se linkuje.** Neexistuje seznam „tyto složky patří do projektu“. Manifestem je
  **první úroveň artefaktového repa**: cokoli leží v kořeni storu (kromě `.git`), to dostane
  symlink v kořeni projektu, se stejným jménem. Přidat artefakt znamená vytvořit složku
  nebo soubor ve storu, nic víc. Odstranit ho znamená smazat ho ve storu; `heal` osiřelý
  symlink uklidí.
- **Co se ignoruje.** Blok v `info/exclude` se generuje z téhož seznamu. Jeden vstup
  (obsah kořene storu), dva výstupy (symlinky, exclude), které se nemohou rozejít.
- **Kam linky ukazují.** Vždy relativně na `.git/lundegaard/<jméno>`. Linky vypadají
  v každém projektu i u každého kolegy stejně, takže se dají kdykoli smazat a znovu
  odvodit — `heal` je jen „přepočítej stav z obsahu storu“.

Důsledek: neexistuje konfigurační soubor, který by se mohl rozejít s realitou, zapomenout
commitnout nebo omylem dostat do zákaznického repa. Jediné, co uživatel kdy zadá, je URL
artefaktového repa při `init`.

## Z čeho se plugin skládá

| Část | Role |
| --- | --- |
| `scripts/lnd-artifacts.sh` | „engine“ — POSIX shell skript se všemi příkazy (viz níže) |
| skill `lnd-artifacts` | návod pro agenta, jak engine volat (Claude Code i Codex) |
| příkaz `/lnd-artifacts:help` | jen čtení: stav artefaktů + seznam příkazů (pouze Claude Code) |
| hook SessionStart | při startu session spustí `heal` (opraví symlinky) |
| hook Stop | na konci session upozorní na nesynchronizované změny |

Závislosti: jen POSIX shell, git a coreutils. Engine **nikdy nesahá na zákaznický
repozitář** (žádné commity, staging ani konfigurace) a hooky **nikdy necommitují ani
nepushují** — publikace je vždy explicitní rozhodnutí člověka.

## Příkazy enginu

| Příkaz | Co dělá |
| --- | --- |
| `init <remote-url>` | Naklonuje artefaktový repo do `.git/lundegaard` a vytvoří symlinky. Jednorázově na projekt. |
| `heal` | Idempotentní oprava: doplní chybějící symlinky, opraví špatné, odstraní osiřelé, přepíše exclude blok. |
| `adopt <cesta>` | Přesune existující neverzovanou složku/soubor do store a nasymlinkuje zpět. |
| `sync` | Commitne vše ve store, `pull --rebase`, push. Jediný způsob publikace. |
| `status` | Přehled: existence store, počet necommitnutých/nepushnutých změn, zdraví symlinků. Nic nemění. |
| `detach` | Odstraní symlinky a exclude blok. Store zůstává; `heal` vše vrátí. |

Každý měnící příkaz umí `--dry-run`.

## Workflow

### 1. Jednorázové zavedení do projektu

1. Založí se prázdný privátní repozitář pro artefakty (1 repo = 1 zákaznický projekt).
2. V projektu se spustí `init git@host:team/project-artifacts.git` — buď přes agenta
   („nastav správu artefaktů“), nebo ručně z checkoutu pluginu.
3. `init` naklonuje store, nasymlinkuje jeho obsah do kořene, zapíše exclude blok a uloží
   kopii enginu do `.git/lundegaard.engine.sh`.
4. Pokud v projektu už např. `.claude/` existuje, `init` ho **nesmaže**, jen přejmenuje na
   `.claude.quarantined-<timestamp>` a nahlásí. Do store se pak dostane přes `adopt`.

### 2. Běžná práce

- Vývojář i agent pracují s `.claude/`, `openspec/`, `CLAUDE.md` normálně — přes symlinky
  se zapisuje přímo do store.
- Zákaznický `git status` zůstává čistý; artefakty do jeho commitů nejdou.
- Při každém startu session hook spustí `heal`, takže po `git clean` nebo v novém worktree
  se symlinky samy obnoví.

### 3. Publikace změn

- Když je co sdílet, člověk (nebo agent na výslovnou žádost) spustí `sync`.
- Na konci session hook Stop upozorní, pokud ve store zbývají nesynchronizované změny.
- Kolega si změny stáhne také přes `sync` (obsahuje `pull --rebase`).

### 4. Nový kolega / nový klon

- Naklonuje zákaznický projekt a spustí `init` se stejnou URL artefaktového repa.
- Pro nové worktrees stačí `heal`; lze jej automatizovat jednou řádkou v worktree tooling
  nebo v git `post-checkout` hooku (viz README).

### 5. Ukončení

- `detach` odstraní symlinky a exclude blok, store v `.git/lundegaard` zůstane.
- Definitivní odstranění je smazání `.git/lundegaard` — **před tím `sync`**, jinak se
  nepushnuté artefakty ztratí.

## Životní cyklus artefaktu

```
vznik ──> adopt / vytvoření přes symlink ──> úpravy (lokálně, ve store) ──> sync (commit + push)
                                                   ^                             |
                                                   └── heal obnoví symlink  <────┘
                                                       po clean / novém worktree
```

1. **Vznik** — soubor vytvořený přes symlink vzniká rovnou ve store; existující soubor se
   přesune příkazem `adopt`.
2. **Úpravy** — necommitnutý stav žije jen lokálně v `.git/lundegaard`. `status` a hook Stop
   ho hlásí.
3. **Publikace** — `sync` commitne a pushne do artefaktového remote. Konflikty se řeší při
   rebase, stejně jako u běžného gitu.
4. **Obnova** — symlinky jsou jednorázové a obnovitelné; `heal` je kdykoli dopočítá z obsahu
   store.
5. **Zánik** — smazání souboru ve store + `sync`; `heal` pak odstraní osiřelý symlink.

## Codex

Skill funguje i v Codexu: nejprve zkusí cestu pluginu, pokud není dostupná, použije kopii
enginu v `.git/lundegaard.engine.sh`. Codex nemá hooky SessionStart/Stop — nahradí je
`heal` ve worktree toolingu a pravidlo skillu spouštět `status` před prací a hlásit
nesynchronizovaný stav po ní.

## Varianty a možná rozšíření

Současný návrh je záměrně minimální. Níže jsou směry, které jsou připravené k diskusi;
nic z toho není implementováno.

### Varianta: centrální úložiště mimo repozitář (`~/.lnd/…`)

Store by neležel v `.git/` zákaznického projektu, ale v centrálním adresáři uživatele,
např. `~/.lnd/artifacts/<projekt>/`, a do projektu by se jen symlinkoval.

```
~/.lnd/artifacts/
  acme-shop/           <- artefaktový repo pro projekt acme-shop
  bank-portal/
  ...
customer-project/
  .claude   -> ~/.lnd/artifacts/acme-shop/.claude
  ...
```

| | `.git/lundegaard` (dnes) | `~/.lnd/…` (varianta) |
| --- | --- | --- |
| Přežije `rm -rf .git` / nový klon | ne (nepushnuté změny se ztratí) | ano |
| Obsah v archivu/image buildu checkoutu | ano, pokud se balí `.git` | ne |
| Sdílení jednoho artefaktového repa mezi více repy | ano, klon per repo, propagace přes remote při `sync` | ano, jeden klon, změny vidí všechna repa okamžitě |
| Worktrees | zdarma, bez konfigurace | nutné mapování worktree → store |
| Mapování projekt → store | žádné (dáno polohou) | nutný konfigurační/stavový soubor |
| Ochrana před únikem do zákaznického remote | strukturální | jen přes `info/exclude` |
| Úklid po smazaném projektu | automatický | ruční / vlastní příkaz |

Shrnutí: centrální úložiště je **nutné** jen tam, kde store nemá žádné `.git`, do kterého by
patřil (efemérní CI checkouty, artefakty k něčemu, co není git repo), nebo když má více
repozitářů sdílet **jeden klon** s okamžitou lokální propagací bez `sync`. Multi-repo projekt
s jedním artefaktovým repem ho nevyžaduje (viz níže). Dává smysl také tehdy, když je prioritou
přežití nepushnutých změn nezávisle na checkoutu. Platí se za to mapovacím stavem a
úklidem. Příkazy enginu i linkování by zůstaly beze změny, cesta ke storu se odvozuje na
jednom místě. Nově by ale bylo třeba vyřešit mapování projekt → store funkční i z worktrees,
umístění locku a vendorovaného enginu (dnes leží vedle storu v `.git/`), napojení na už
existující store při `init` a úklid po smazaném projektu. Podrobný rozbor: `docs/analysis/2026-09-01-store-placement.md`.

### Rozšíření: automatizace, aby uživatel nemusel téměř nic dělat

Dnes je jediným ručním krokem `sync`. Možné stupně automatizace, od nejmírnějšího:

1. **Auto-commit na konci session** — hook Stop commitne (bez push).
2. **Auto-sync na konci session** — hook Stop provede celý `sync`; konflikt při rebase se
   nahlásí a nechá na člověku.
3. **Periodický sync** — cron / launchd / plánovaný agent volá `sync`.
4. **Auto-init** — první session v projektu bez storu provede `init` podle konvence URL.
5. **Auto-heal mimo agenta** — git `post-checkout` hook nebo worktree tooling (dnes již
   podporováno).

Auto-sync ruší dnešní záruku „hooky nikdy necommitují ani nepushují“, která dává kontrolu
nad tím, co se posílá do sdíleného repa. Rozumný kompromis je auto-sync jako **volitelný
přepínač** per projekt nebo uživatel; výchozí stav zůstane explicitní `sync`.

### Rozšíření: jeden projekt, více repozitářů, jedno artefaktové repo

Typický případ: Java/Spring projekt rozdělený na `order-service`, `payment-service` a
`gateway`. Každý repozitář má mít **vlastní store** (svůj `CLAUDE.md`, `.claude/`, openspec),
ale všechny story mají žít v **jednom artefaktovém repu** projektu, spolu se sdílenými
artefakty (PRD, doménový slovník, architektonická rozhodnutí).

Preferované řešení jsou **podadresáře**: artefaktové repo má na první úrovni `common/` a
jeden adresář per hostitelský repozitář. Engine linkuje obsah `<klon>/<název-repa>/` a
`<klon>/common/` místo kořene klonu; název podstoru se odvodí z názvu repa, s možností
přepsat ho při `init`. Pravidlo „první úroveň = manifest“ i `sync` zůstávají beze změny,
ploché artefaktové repo funguje jako dosud.

```
acme-artifacts/
  common/            <- sdílené artefakty, linkované do každého repa
  order-service/     <- store repa order-service
  payment-service/
  gateway/
```

Varianta s větví per repozitář (viz `docs/CONTEXT.md` §6) je zamítnuta kvůli nutnosti
mergovat každou změnu sdílených artefaktů do N větví. Další alternativy (sparse-checkout,
submoduly, manifest) byly zváženy a nepřinášejí nic navíc oproti podadresářům.

### Rozšíření: kurátorovaný seznam povolených artefaktů

Store má pojmout jakýkoli artefakt, ale ne úplně cokoli od kohokoli. Řešením je
**allowlist jmen na první úrovni storu** (`.claude`, `openspec`, `CLAUDE.md`, `docs`, …),
navazující na pravidlo „první úroveň = manifest“. Seznam nehlídá obsah, jen pod jakým
jménem v kořeni smí artefakt existovat; obecná položka typu `docs/` pokryje věci bez
vlastní kategorie.

- **Seznam žije v pluginu, přímo v enginu.** Jeho rozšíření je merge request do pluginu
  (review, verze), a protože se engine vendoruje a `heal` ho obnovuje, nová verze seznamu
  se sama rozšíří do všech projektů. Seznam ve storu by cíl nesplnil, každý by si ho
  rozšířil sám.
- **Vynucení:** `adopt` odmítne jméno mimo seznam, `sync` odmítne commitnout store
  s nepovolenou položkou (bez `--force`), `status` a hook Stop varují, `heal` položku dál
  linkuje, jen ji nahlásí.
- **Druhá linie na serveru:** CI v artefaktovém repu zavolá read-only příkaz enginu a ověří
  první úroveň proti témuž seznamu, aby ruční `git push` kontrolu neobešel.
- **Bez per-projektových výjimek.** Jakmile by existovaly, kurátorování ztrácí smysl.

### Další menší rozšíření

- **`status` napříč projekty** — jeden příkaz vypíše nesynchronizované story všech
  projektů (přirozené s centrálním úložištěm).
- **Šablony storu** — `init` naplní nový artefaktový repo výchozí strukturou
  (`.claude/`, `openspec/`, kostra `CLAUDE.md`).
- **Podpora dalších agentů** — skill je runtime-neutrální; přidání dalšího nástroje znamená
  hlavně zjistit, jak načítá skilly, engine se nemění.

## Rizika, o kterých je dobré vědět

- **`rm -rf .git` nebo nový klon zničí nepushnuté artefakty.** Synchronizovat často.
- **Zálohy přeskakující `.git/` store nezálohují.** Zálohou je artefaktový remote.
- **Vyhledávače (rg, grep) nesledují symlinky** — použít `rg -L`.
- **Worktrees sdílejí necommitnutý stav** — lokálně vyhrává poslední zápis, konflikty se
  ukážou při `sync`.
- Store je **jen payload**: v jeho kořeni nesmí být `README.md` ani `.gitignore`, protože
  všechno z kořene se symlinkuje do projektu.
