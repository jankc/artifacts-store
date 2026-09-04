# Dopad rozhodnutí „všichni vývojáři vidí všechny repozitáře"

Podklad k týmové diskusi · 3. 9. 2026 · dodatek k dokumentům z 1. 9. 2026
(„mp-temp × lnd-artifacts", „Umístění artefaktového storu")

Firma rozhodla, že všichni vývojáři budou mít přístup ke všem repozitářům, tedy
i k repozitářům s artefakty. Tím padá požadavek na oddělení klientských dat mezi
vývojáři. Tento dokument vyhodnocuje, co z analýzy z 1. 9. tím přestává platit, co
platí dál a jak se mění závěr.

## Souhrn

Padají požadavky **R4** (oprávnění na úrovni projektu) a **R5** (izolace klientů).
Byly to jediné dva body, kde mp-temp selhával architektonicky a lnd-artifacts
vyhrával konstrukcí. Bez nich mp-temp **není diskvalifikován**; téma T6 („dá se
R4/R5 dodělat") je bezpředmětné a sdílený pool je přípustná topologie. Doporučení
„transport = lnd-artifacts, guardy z mp-temp" stojí na zbylých důvodech (adopt
libovolné cesty, vratnost, jednoduchost enginu, worktrees), ale mění se
z bezpečnostní nutnosti na **inženýrskou preferenci**. Pravidlo „1 store = 1
klientský projekt" ztrácí své původní zdůvodnění a stává se volbou k potvrzení.

## 1 · Scorecard po škrtnutí R4 a R5

| | mp-temp | lnd-artifacts |
|---|---|---|
| Původní scorecard (17 požadavků) | 8 ✓ · 4 ◐ · 5 ✗ | 12 ✓ · 5 ◐ · 0 ✗ |
| Po škrtnutí R4/R5 (15 požadavků) | 8 ✓ · 4 ◐ · 3 ✗ | 10 ✓ · 5 ◐ · 0 ✗ |

Zbývající ✗ mp-tempu: R0a a R1 (kurátorovaný whitelist typů) a R14 (vratnost).
Jsou to pořád zaznamenaná designová rozhodnutí, ale žádné není bezpečnostní
showstopper.

## 2 · Co v dokumentu „mp-temp × lnd-artifacts" přestává platit

- **T6 celé.** Věta „pro roli transportu klientských artefaktů diskvalifikující,
  dokud požadavky platí v dnešním znění" už neplatí — požadavky se změnily. Cesty
  1–3 (překlopení defaultu, gateway, šifrování) nikdo nemusí řešit. Podmínka
  v `RETURN-MAP.md` („pending legal") je tímto firemním rozhodnutím fakticky
  splněna; je to přesně ono „bezpečnostní rozhodnutí vyžadující explicitní podpis",
  které dokument označil za nutný předstupeň.
- **Z2 ztrácí většinu váhy.** Incident 94 souborů byl únik *mezi klienty uvnitř
  poolu*, tedy do prostoru, který teď všichni vidí legitimně. Přestává být
  materializovaným rizikem R5. Zůstává jen jako doklad, že auto-push bez člověka
  v cestě dělá nechtěné velké pushe (Z4).
- **T1 (model oprávnění) se řeší triviálně.** Store nemusí být repem projektové
  skupiny kvůli dědění oprávnění. K dořešení zbývá jen přístup lidí *mimo firmu*
  (externisté, klient), pokud takový případ existuje.
- **T3 (pool vs. izolované story) je skutečně otevřené.** Argument „opačný směr
  nefunguje, izolace se do poolu zpětně nedostaví" už nemá adresáta. Hodnota poolu
  (čtení napříč projekty jedním klonem, R15) je dosažitelná bez ACL ceny.
- **Řádky R4 a R5 ve scorecardu** a poznámka o `tools/store-gateway` jako cestě
  k per-caller scopingu — gateway zůstává zajímavá pouze pro budoucí čtecí
  přístup, ne jako bezpečnostní nutnost.

## 3 · Co v dokumentu „Umístění artefaktového storu" přestává platit

- Dimenze **„Koncentrace důvěrných dat" (C ✗)** je neutrální — škrtnout.
- 6.1: „sdílený pool… jediný scénář, který požadavky (R4, R5) zakazují" — pool
  je nyní přípustný.
- 6.2 závěr: „jediným tvrdým důvodem pro C zůstává sdílený pool, který požadavky
  zakazují" — přesněji: sdílený pool je nyní legitimní volba a **vynucuje C**
  (`~/.lnd`) jako důsledek topologie, nikoli kvůli kvalitám umístění. C se tím
  vrací do hry.
- **Doporučení A pro per-projektový store zůstává beze změny.** Všechny jeho
  výhody (worktrees zdarma, strukturální necommitovatelnost, nulový mapovací stav,
  životnost s projektem) jsou nezávislé na izolaci. Změnila se otázka o úroveň výš:
  chceme vůbec per-projektový store?
- Multi-repo analýza (6.2, lnd-artifacts `docs/CONTEXT.md` §6) platí dál, ale
  přestává být jedinou cestou. Pool s cestami per projekt řeší multi-repo také,
  a bez N mergů z větve `common`.

## 4 · Co platí dál

- **R6 (ochrana proti úniku) platí, jen se posouvá.** Únik už neznamená „klient A
  vidí data klienta B", ale „artefakt nebo secret skončí v klientském repu nebo
  mimo firmu". Secret scan z mp-tempu je stále nejvážnější mezera lnd-artifacts;
  pushnutý částečný Azure klíč je stále reálný incident. R3 (žádná stopa
  v klientském repu) platí beze změny.
- **R0a/R1** (whitelist vs. adopt-anything, T4), **R14** (vratnost, Z3), **Z4**
  (automatika × explicitní publish, T2), **Z5** (4 510 ř. bash + Python vs.
  1 282 ř. POSIX sh), **R8** (worktrees), **R13** (CI, kde mp-temp vede), **T5**
  (provozní zralost).
- **Doporučení kap. 6** („transport = lnd-artifacts, guardy z mp-temp, kvalita =
  disciplína mp-temp, harvesting jako vrstva nad tím") stojí na zbylých důvodech.
  Je ale poctivé ho **přeformulovat z „mp-temp je diskvalifikován" na
  „inženýrská preference"** — jinak ho na diskusi někdo oprávněně napadne.

## 5 · Dopad na lnd-artifacts samotný

Tvrdý constraint „1 artifact repo = 1 klientský projekt" má v `docs/CONTEXT.md`
§4 zdůvodnění „hranice transportu = hranice izolace klientů". To zdůvodnění padlo.
Pravidlo může zůstat z jiných důvodů:

- store zaniká s projektem, remote je záloha, žádný úklid sirotků,
- vratnost (R14) je per projekt, ne per firma,
- store root = manifest bez druhého zdroje pravdy (žádný filtr „co patří komu"),
- 1 : 1 s GitLab skupinou projektu je organizačně čitelné,
- mizí mezera orphan branch ze starého branch-per-project modelu.

Je to však nyní **volba k potvrzení, ne constraint**. Pokud by firma zvolila
pool, lnd-artifacts ho dnes neumí: `init <stejná URL>` ve všech repech by
nalinkoval všechny projekty do každého rootu. Musel by se buď vrátit odložený
branch-per-project model (větev per projekt, `heal` linkuje strom checkoutnuté
větve — funguje bez změny enginu, viz `docs/CONTEXT.md` §6), nebo přidat výběr
podmnožiny, což CONTEXT §6 odmítl kvůli druhému zdroji pravdy.

## 6 · Doporučení dalšího postupu

1. **Přeformulovat závěr srovnání.** Rozhodnutí je nyní o *ceně změny*
   (whitelist vs. adopt, vratnost, složitost enginu, worktrees) a *provozní
   zralosti*, nikoli o bezpečnosti.
2. **Ověřit rozsah firemního rozhodnutí.** Potvrdit, že „všichni vidí vše" pokrývá
   i NDA/ISO závazky vůči klientům — to je ta legální podmínka, na kterou mp-temp
   čekal. Zároveň aktualizovat požadavkový dokument (škrtnout nebo přeformulovat
   R4, R5).
3. **Až poté rozhodnout pool vs. per-projekt.** Doporučení autora zůstává
   per-projektový store v git common diru: pool nepřidává nic, co by enumerace
   rep přes GitLab a naming konvence nedaly, a přináší mapovací stav, globální
   lock a úklid. Je to ale už jen preference, ne požadavek.

---

Zdroje: „mp-temp × lnd-artifacts" a „Umístění artefaktového storu" (oba 1. 9.
2026) · lnd-artifacts `docs/CONTEXT.md` §4, §6 · firemní rozhodnutí o plošném
přístupu k repozitářům (sděleno 3. 9. 2026, bez písemného podkladu v repu).
