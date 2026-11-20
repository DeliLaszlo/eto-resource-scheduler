# Az ETO FC Heti Program üzemeltetési útmutatója

[English version](README.md)

Az ETO FC Heti Program az ETO FC labdarúgóklub heti programtervező webalkalmazása. Ez a csomag Dockerrel telepíti egy szerverre. A lépések egy frissen telepített, üres szerverből indulnak ki. A telepítés után az üzemeltetés nagy része az üzemeltetői konzolon történik, a `https://<cím>/console` címen. A licenc MIT, lásd [LICENSE](LICENSE).

## 1. Követelmények

- Egy x86-64 szerver Ubuntu 22.04, 24.04 vagy Debian 12, 13 rendszerrel.
- Legalább 2 processzormag, 4 GB RAM és 20 GB szabad tárhely.
- Egy domainnév, például `eto.example.hu`. A DNS-rekordjának már a telepítés előtt a szerverre kell mutatnia.
- Egy SMTP-levelezőfiók.
- Ajánlott a telepítés előtt beállítani az SSH-t, kulcsos belépéssel és kikapcsolt jelszavas belépéssel.
- Opcionális. Egy Microsoft Entra alkalmazásregisztráció az Outlook-szinkronhoz, és egy S3-kompatibilis tárhely a felhős mentésekhez.

## 2. Telepítés

```bash
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/delilaszlo/eto-resource-scheduler.git /opt/etofc
cd /opt/etofc
sudo sh setup.sh
```

A szkript a legújabb verziót telepíti. Egy adott verzió a számával telepíthető, például `sudo sh setup.sh 1.0.0`.

A szkript az alábbi kérdéseket teszi fel. A szögletes zárójelben lévő érték az alapérték, ezt az Enter elfogadja.

| Kérdés | Példa válasz | Megjegyzés |
| --- | --- | --- |
| „A Docker nincs telepítve. Telepítsem a Docker hivatalos csomagtárából” | `i` | Csak ha nincs Docker |
| „A curl nincs telepítve. Telepítsem” | `i` | Csak ha nincs curl |
| „Folytatod így is” | `n` | Csak óra- vagy hálózati figyelmeztetés után. A figyelmeztetés megmondja a javítást |
| „Egy korábbi telepítés mentését állítod vissza (költözés új szerverre)” | `n` | `i` csak költözéskor, lásd az 5. részt |
| „Az alkalmazás nyilvános címe, például https://eto.example.hu” | `https://eto.example.hu` | |
| „A HTTPS-t ez a szerver szolgálja ki a beépített Caddyvel (nem, ha már van saját HTTPS proxy)” | `i` | `n` esetén a következő táblázat kérdései jönnek |
| „Hány CDN áll a szerver előtt (például 1 Cloudflare-rel, 0 ha nincs)” | `0` | |
| „Az alkalmazás neve” | Enter | Alapérték `ETO FC Heti Program`. Az e-mailek tárgyában jelenik meg |
| „Az üzemeltető e-mail címe (a konzol belépése és az értesítések)” | `uzemelteto@example.hu` | |
| „Az üzemeltető jelszava (legalább 12 karakter)”, majd „Jelszó újra” | | Gépelés közben nem látszik |
| „A(z) admin felhasználó sudo nélkül is kezelje a konténereket (docker csoport)” | `i` | Csak sudóval futtatva. A felhasználó következő belépésétől érvényes |
| „Az ufw tűzfal nincs telepítve. Telepítsem és állítsam be” | `i` | Csak ha nincs ufw |
| „Az SSH port(ok), szóközzel elválasztva” | Enter | Az alapérték az SSH-szerver portja |
| „Bekapcsoljam a tűzfalat úgy, hogy csak ezek a portok legyenek nyitva (22 80 443)” | `i` | |

Ha saját HTTPS proxy áll az alkalmazás előtt, a CDN-es kérdés helyett ezek jönnek.

| Kérdés | Példa válasz | Megjegyzés |
| --- | --- | --- |
| „Hány proxy áll az alkalmazás előtt a saját HTTPS proxyval együtt (például 1, vagy 2 Cloudflare-rel)” | `1` | |
| „Melyik porton figyeljen az alkalmazás a saját proxy felé” | `3000` | |
| „A saját HTTPS proxy ezen a gépen fut” | `i` | |
| „Melyik címen érje el a proxy ezt a gépet (0.0.0.0 = minden címen)” | `10.0.0.5` | Csak ha az előző válasz `n` volt |

A végén a szkript kiírja a `BACKUP_ENCRYPTION_KEY` és a `TWO_FACTOR_ENCRYPTION_KEY` értékét. Ezek a `.env` fájlban is megvannak. Ha a szerver vagy a `.env` elvész, egy mentés csak ezzel a két kulccsal állítható vissza, ezért a szerveren kívül is tárolni kell őket, például egy jelszókezelőben.

Ha a szkript félúton leáll, a hiba javítása után újra futtatható. Ott folytatja, ahol abbahagyta, és megtartja a kulcsokat.

## 3. Első lépések a konzolon

A konzol a `https://<cím>/console` címen érhető el, az üzemeltető e-mail-címével és jelszavával. Az első belépés beállítja a kétlépcsős azonosítást egy hitelesítő alkalmazással. Ezután az Áttekintés oldal sorolja fel a hiányzó beállításokat. A mentések felhőmásolatát a 4. rész írja le.

### Levelezés

A levelezés beállításai a Beállítások, Levelezés alatt vannak. Amíg nincsenek beállítva, az alkalmazás nem küld e-mailt. Mentés előtt próbalevél megy az üzemeltető címére.

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| SMTP szerver | `smtp.example.hu` | A levelezési szolgáltató adja meg |
| Port | `587` | A levelezési szolgáltató adja meg |
| Felhasználónév | `heti@example.hu` | Üres, ha a szerver nem kér belépést |
| Jelszó | | A levelezőfiók jelszava |
| Feladó címe | `heti@example.hu` | A levelezési szolgáltatónak engedélyeznie kell a küldést erről a címről |
| Feladó neve | `ETO FC Heti Program` | |

### Kezdő adatok

Az Áttekintés oldal kártyáján letölthető egy példafájl. A kitöltött fájl ugyanott tölthető fel, egyszer, amíg a klubnak nincs felhasználója. Mentés előtt egy előnézet jelzi a hibákat.

A `seededUsers` felhasználói a fájlban megadott jelszóval lépnek be. Az `invitedUsers` felhasználóit a klub adminjai hívják meg. A jelszavak kiküldése után a fájlt törölni kell.

### Outlook

Az Outlook beállításai a Beállítások, Outlook alatt vannak. Az Outlook-szinkronhoz egy alkalmazásregisztráció kell. A regisztráció a Microsoft Entra felügyeleti központban (`entra.microsoft.com`) készül, a következő lépésekkel.

1. App registrations, New registration.
2. Név `ETO FC Heti Program`. Supported account types „Accounts in any organizational directory and personal Microsoft accounts”, ha bármilyen Microsoft-fiók csatlakozhat. „Accounts in this organizational directory only”, ha csak egy szervezet fiókjai.
3. Redirect URI Web platformmal. Az értéke a konzol Átirányítási cím mezője, például `https://eto.example.hu/api/integrations/outlook/callback`.
4. API permissions, Add a permission, Microsoft Graph, Delegated permissions. Az `offline_access`, a `User.Read` és a `Calendars.ReadWrite` jogosultságot kell hozzáadni.
5. Certificates & secrets, New client secret. A lejárat legfeljebb 24 hónap. A titok értékét (Value) csak egyszer mutatja meg.

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| Alkalmazásazonosító | `0f3c9a2e-5b1d-4c7e-9a8f-2d6b4e1c7a90` | Application (client) ID az alkalmazás Overview oldalán |
| Bérlőazonosító | `common` | `common`, ha bármilyen Microsoft-fiók csatlakozhat. Ha csak egy szervezet fiókjai, a Directory (tenant) ID az alkalmazás Overview oldaláról |
| Alkalmazás titka | | Az új titok Value értéke, nem a Secret ID |
| A titok lejárata | `2028-11-01` | A titok lejárati dátuma |

Mentés előtt a konzol az Azure-nál ellenőrzi az azonosítót és a titkot. A titok lejárata előtt a konzol e-mailt küld. Az új titok az 5. lépéssel készül, és ugyanebbe a két mezőbe kerül.

### Külső rendszerek

Más rendszer a külső API-n keresztül olvashatja a véglegesített heti programot. Az API csak olvasható, a leírása az [API.hu.md](API.hu.md) fájlban van.

Minden külső rendszer saját kulcsot kap az API kulcsok kártyán, az Új API kulcs gombbal. A konzol a kulcsot csak egyszer mutatja meg, ezért akkor kell átadni. A kulcs törlése ugyanezen a kártyán azonnal kizárja az adott rendszert. A kártya mutatja, hogy az egyes kulcsokat mikor használták utoljára.

## 4. Mentések

Az adatbázisról minden éjjel 02:00-kor, nyári időszámítás idején 03:00-kor mentés készül. A mentéseket a `BACKUP_ENCRYPTION_KEY` titkosítja. A szerver 14 napig őrzi meg őket, egyszerre legfeljebb 21-et. A konzol Mentések oldalán igény szerint is készíthető mentés, és ott minden mentés letölthető.

### Felhőmásolat

A szerveren lévő mentés a szerverrel együtt elvész. Ezért a konzol minden éjjel 03:40-kor feltölti az új mentéseket egy S3-kompatibilis tárhelyre, hetente legfeljebb 14-et. A beállítások a Beállítások, Felhőmásolat alatt vannak.

A tárhelynek három beállítás kell. Object Lock zárolás 6 napos alapértelmezett megőrzéssel, így 6 napig senki sem törölheti a mentést, ellopott kulccsal sem. Egy életciklus-szabály, amely a zárolás lejárta után egy nappal törli a mentéseket, így minden mentés a feltöltés után 7 nappal eltűnik. Egy kulcs, amely ebbe az egy tárolóba feltölteni tud, törölni nem. Bármely S3-kompatibilis tárhely megfelel, amely így beállítható.

A példa a Backblaze B2, mert az első 10 GB ingyenes, és ez elég a klub mentéseihez. A Backblaze regisztrációkor csak amerikai és kanadai régiót kínál, ezért ez a példa nem az EU-ban tárolja a mentéseket. Egy EU-s régiójú, ugyanígy beállított S3-kompatibilis tárhely az EU-ban tartja őket. Amerikai régiónál a klubnak adattovábbítási jogalap kell, például a szolgáltató adatfeldolgozási szerződésében szereplő általános szerződési feltételek.

A Backblaze B2 tárhely a következő lépésekkel készül.

1. Regisztráció a `backblaze.com` oldalon. A régió csak a regisztrációkor választható.
2. Buckets, Create a Bucket. Egyedi név, például `eto-mentesek`, Files in Bucket Private, Object Lock Enable.
3. A tároló Object Lock beállítása, 6 napos alapértelmezett megőrzéssel.
4. A tároló Lifecycle Settings beállítása, egyéni szabállyal. Days till hide 6, days till delete 1.
5. Application Keys, Add a New Application Key. Hozzáférés csak ehhez a tárolóhoz, Write Only típussal. A kulcsot a Backblaze csak egyszer mutatja meg.

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| S3 végpont | `s3.us-east-005.backblazeb2.com` | A tárolók listájában látható Endpoint |
| Régió | `us-east-005` | A végpont középső része |
| Tároló neve | `eto-mentesek` | |
| Mappa a tárolóban | `etofc` | Opcionális. Üresen a tároló gyökerébe tölt fel |
| Kulcsazonosító | `0051a2b3c4d5e6f0000000001` | Az új kulcs keyID értéke |
| Titkos kulcs | | Az új kulcs applicationKey értéke |

Mentés előtt a konzol egy próbafájlt tölt fel a tárolóba. A zárolás a próbafájlt is 6 napig megtartja.

### Mentés visszaállítása

Egy mentés négy paranccsal állítható vissza a szerveren. A Mentések oldal minden mentésnél megmutatja őket, a fájl nevével.

```bash
cd /opt/etofc
sudo docker compose stop backend
sudo docker compose exec -T backup sh /backup.sh restore etofc-20261107T010000Z.dump.age
sudo docker compose up -d --wait
```

A visszaállítás először egy külön adatbázisba történik. Sikertelen visszaállítás esetén a jelenlegi adatok érintetlenek maradnak.

## 5. Költözés új szerverre

A költözéshez a legújabb mentés és a két elmentett kulcs kell. A mentés az S3-tárolóból vagy a régi konzolról tölthető le. A domain DNS-rekordjának már a telepítés előtt az új szerverre kell mutatnia.

A mentést először fel kell másolni az új szerverre. Onnan a telepítés előtt a csomag `backups` mappájába kerül, egyébként a telepítés a 2. rész parancsaival történik.

```bash
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/delilaszlo/eto-resource-scheduler.git /opt/etofc
sudo mkdir /opt/etofc/backups
sudo cp ~/etofc-*.dump.age /opt/etofc/backups/
cd /opt/etofc
sudo sh setup.sh
```

A 2. részhez képest ezek a kérdések térnek el.

| Kérdés | Példa válasz | Megjegyzés |
| --- | --- | --- |
| „Egy korábbi telepítés mentését állítod vissza (költözés új szerverre)” | `i` | |
| „BACKUP_ENCRYPTION_KEY” | `AGE-SECRET-KEY-1…` | Az elmentett kulcs, gépelés közben nem látszik |
| „TWO_FACTOR_ENCRYPTION_KEY” | 64 hexadecimális karakter | Az elmentett kulcs, gépelés közben nem látszik |

Az üzemeltető e-mail-címét és jelszavát nem kérdezi, mert az üzemeltetői fiók a mentéssel visszajön. Az indulás után a szkript visszaállítja a `backups` mappa legújabb mentését. Ezzel a konzol beállításai is visszajönnek.

Az új `.env` új `JWT_SECRET` és új `OUTLOOK_TOKEN_ENCRYPTION_KEY` értéket kap. Ezért mindenkinek újra be kell lépnie, és az Outlookot csatlakoztató felhasználóknak újra csatlakoztatniuk kell. Ha a régi `.env` megmaradt, a `setup.sh` előtt az `/opt/etofc` mappába másolható, és ekkor erre nincs szükség. A szkript ilyenkor megkérdezi, visszaállítsa-e a legújabb mentést, erre a válasz `i`.

A még futó régi szervert le kell állítani, különben mindkét szerver kiküldi az e-maileket.

## 6. Frissítés

```bash
cd /opt/etofc
sudo sh update.sh X.Y.Z
```

Az `X.Y.Z` egy kiadott verziószám, például `1.2.0`. A verziók listája a [GitHubon](https://github.com/delilaszlo/eto-resource-scheduler/tags) van. A legújabbat a konzol Állapot oldala is mutatja, és az üzemeltető minden új verzióról e-mailt kap.

A szkript mentést készít, majd elindítja az új verziót, és megvárja, amíg elkészül. Ha az új verzió nem indul el, kiírja a régi verzióra és annak mentésére visszaálló parancsokat. Heti program véglegesítése közben, és magyar idő szerint 01:45 és 04:00 között nem szabad frissíteni, mert ekkor futnak az éjszakai feladatok.

## 7. Hibaelhárítás

### Telepítés közben

| Probléma | Ok | Megoldás |
| --- | --- | --- |
| A cím még nem válaszol | A DNS-rekord nem a szerverre mutat, vagy a tárhelyszolgáltató tiltja a 80-as és 443-as portot | A DNS-rekord vagy a portok javítása után a `setup.sh` újra futtatható. A részleteket a proxy naplója mutatja |
| Nem indultak el a szolgáltatások | Többnyire egy hibás `.env` érték | A backend naplója megnevezi a hibát |
| Nem sikerült a letöltés | A szerver nem éri el a `ghcr.io` vagy a `download.docker.com` címet | A kimenő HTTPS-forgalmat engedélyezni kell |

A naplókat ezek a parancsok mutatják.

```bash
cd /opt/etofc
sudo docker compose logs proxy
sudo docker compose logs backend
```

### Működés közben

A futó alkalmazás hibái a konzol Rendszernapló oldalán jelennek meg.

| Probléma | Ok | Megoldás |
| --- | --- | --- |
| Nem érkeznek e-mailek | Hibás levelezési beállítás, vagy a tárhelyszolgáltató tiltja az 587-es portot | Az Állapot oldal mutatja az utolsó levelezési hibát. A levelezési szolgáltató másik portja, például a 2525 segíthet |
| Az e-mailek a levélszemétbe kerülnek | A feladó domainjén nincs SPF-, DKIM- vagy DMARC-rekord | A levelezési szolgáltató rekordjait fel kell venni a domainre |
| Minden belépés 403-as hibát ad | A `.env` `FRONTEND_URL` értéke eltér a böngészőben lévő címtől | A `FRONTEND_URL` javítása |
| Mindenki „Túl sok kérés” hibát kap | A klub hálózata egy közös címet használ | A korlát emelése a Beállítások, Kéréskorlát alatt |
| Leállt az Outlook-szinkron | Lejárt az Azure titok | Új titok készítése az Entra felügyeleti központban és megadása a konzolon, lásd a 3. részt |
| Egy klubadmin elvesztette a telefonját vagy a jelszavát | | Klub adminok, Helyreállítás. Az admin jelszó-visszaállító linket kap |
| Egy külső rendszer 401 hibát kap | Az API kulcsa hibás, vagy törölték | Új kulcs az API kulcsok kártyán, majd a kulcs átadása |
| Az üzemeltető elvesztette a telefonját | | A belépési oldal „Nem tudsz bejelentkezni?” linkje e-mailt küld, amely kikapcsolja a kétlépcsős azonosítást |
| Az üzemeltető a jelszavát és a telefonját is elvesztette | | Az alábbi parancs |

Ez a parancs új üzemeltetői jelszót állít be, és kikapcsolja a kétlépcsős azonosítást. Az új jelszót kétszer kéri.

```bash
cd /opt/etofc
sudo docker compose exec backend node dist/src/cli/operator.js reset
```

## 8. A .env fájl

A `setup.sh` a szerver beállításait és titkait a `/opt/etofc/.env` fájlba írja. Csak a tulajdonosa olvashatja. Módosítás után a `sudo docker compose up -d` indítja újra az alkalmazást az új értékekkel.

| Érték | Szerepe | Példa | Módosítása |
| --- | --- | --- | --- |
| `APP_VERSION` | A futó verzió | `1.2.0` | Csak az `update.sh`-val |
| `APP_NAME` | Az alkalmazás neve az e-mailekben | `'ETO FC Heti Program'` | Bármikor |
| `FRONTEND_URL` | A nyilvános cím | `https://eto.example.hu` | A DNS-rekordot és az Azure átirányítási címét is módosítani kell |
| `TRUST_PROXY_HOPS` | Hány proxyn halad át egy kérés a backendig. Ebből állapítja meg a backend a látogató címét a kéréskorláthoz | `2` Caddyvel, `3` Caddyvel és Cloudflare-rel, `2` egy saját proxyval | Egy CDN bekapcsolása eggyel növeli, kikapcsolása eggyel csökkenti |
| `HTTP_BIND`, `HTTP_PORT` | A cím és a port, amelyen az alkalmazás a saját proxy felé figyel | `127.0.0.1`, `3000` | A saját proxyban is át kell írni a továbbítási címet |
| `COMPOSE_PROFILES` | `https` esetén a beépített Caddy fut, üresen saját proxy kell | `https` | Váltáskor a `TRUST_PROXY_HOPS` is változik |
| `CADDY_TRUSTED_PROXIES` | Honnan fogadja el a Caddy a látogató címét | `'127.0.0.1/32'` CDN nélkül, `'0.0.0.0/0 ::/0'` CDN-nel | CDN be- vagy kikapcsolásakor a `TRUST_PROXY_HOPS` értékkel együtt változik |
| `JWT_SECRET` | A belépések aláírása | 96 hexadecimális karakter | Lehetséges, de mindenki kijelentkezik, az üzemeltető is |
| `OUTLOOK_STATE_SECRET` | Egy folyamatban lévő Outlook-csatlakozás aláírása, 10 percig érvényes | 96 hexadecimális karakter | Lehetséges. Csak az utolsó 10 percben indított csatlakozás hiúsul meg |
| `OUTLOOK_TOKEN_ENCRYPTION_KEY` | Az Outlook-kapcsolatok titkosítása | 64 hexadecimális karakter | Lehetséges, de minden felhasználónak újra kell csatlakoztatnia az Outlookot |
| `TWO_FACTOR_ENCRYPTION_KEY` | A kétlépcsős azonosítás és a konzol beállításainak titkosítása | 64 hexadecimális karakter | **Soha.** A kétlépcsős azonosítás és a konzol beállításai elvesznek |
| `BACKUP_ENCRYPTION_KEY` | A mentések titkosítása | `AGE-SECRET-KEY-1…` | Lehetséges. A régi mentésekhez továbbra is a régi kulcs kell |
| `POSTGRES_USER`, `POSTGRES_DB` | Az adatbázis felhasználója és neve | `eto`, `etofc` | Soha |
| `POSTGRES_PASSWORD` | Az adatbázis jelszava | 48 hexadecimális karakter | Előbb az adatbázisban, lásd alább |

Az adatbázis jelszava három lépésben módosul. Az első parancs az adatbázisban állítja be. Ezután ugyanez a jelszó kerül a `.env` `POSTGRES_PASSWORD` sorába. A második parancs újraindítja az alkalmazást.

```bash
cd /opt/etofc
sudo docker compose exec db psql -U eto -d etofc -c "ALTER ROLE eto WITH PASSWORD 'UJ_JELSZO'"
sudo docker compose up -d
```

## 9. Személyes adatok

Az alkalmazás a klub munkatársainak, a meghívottaknak, a kollégiumi lakóknak és a tárgyalófoglalások résztvevőinek személyes adatait tárolja.

### Megőrzési idők

Az alkalmazás minden éjjel 03:20-kor törli a lejárt adatokat. A konzol Ütemezett feladatok kártyáján ez a Megőrzési időn túli adatok törlése sor.

| Adat | Megőrzés | Megjegyzés |
| --- | --- | --- |
| Tevékenységnapló | 365 nap | |
| Kollégiumi lakó | A kiköltözés után 365 nap | |
| Fel nem használt meghívó | A lejárat után 30 nap | |
| Visszajelzés | 365 nap | |
| Tárgyalófoglalás résztvevőinek címei | A foglalás után 365 nap | Maga a foglalás megmarad |
| Események, pálya- és tárgyalófoglalások, mentett heti programok | 3 év | |
| Rendszernapló | 90 nap | |
| Mentés a szerveren | 14 nap | |
| Mentés a felhőtárhelyen | 7 nap | 6 napig zárolva, utána az életciklus-szabály törli |
| Webszerver napló | 30 MB | Három 10 MB-os fájl. Új fájl kezdésekor a legrégebbi törlődik |
| Felhasználói fiók | Amíg a klub nem törli | |

### Adatátadás külső szolgáltatóknak

| Szolgáltató | Milyen személyes adatot kap | Mikor |
| --- | --- | --- |
| Tárhelyszolgáltató | Minden, ami a szerveren van | Mindig |
| Levelezési szolgáltató | Az e-mailek címzettjei és tartalma | Minden e-mailnél |
| Mentési tárhely | Titkosított adatbázismentések | Ha a felhőmásolat be van állítva |
| Microsoft | Az Outlookot összekötő felhasználók eseményei és foglalásai | Csak ezeknél a felhasználóknál |
| MLSZ, `adatbank.mlsz.hu` | A látogató IP-címe | Amikor a böngésző egy csapatcímert tölt be |

### Adatkezelési tájékoztató

Amíg nincs közzétett adatkezelési tájékoztató, az alkalmazás senkitől sem kér megerősítést. Addig nincs jelölőnégyzet a regisztrációnál, nincs hivatkozás a bejelentkezési oldalon, és az e-mailekben sincs róla sor.

A tájékoztató a konzolon, a Beállítások, Adatkezelési tájékoztató résznél tehető közzé. A szerkesztő egy sablonnal indul, amely felsorolja, mit tárol az alkalmazás. Közzététel előtt a sablont jogásznak kell átnéznie és kiegészítenie. Közzétett tájékoztató nem törölhető. A módosított szöveg mentése új változatot tesz közzé, a régi változatok ugyanott olvashatók maradnak.

Minden új változat után minden felhasználó a következő bejelentkezésekor megerősíti a tájékoztatót. Új felhasználó a regisztrációkor erősíti meg.

### Hozzáférési és törlési kérelmek

Ha valaki kéri a róla tárolt adatokat vagy azok törlését, a konzol Személyes adatok keresése kártyáján a neve vagy az e-mail címe alapján megkereshetők.

Egy név több személyé is lehet. Egy azonos nevű munkatárs és kollégiumi lakó egyaránt megjelenik a találatok között. Ezért minden sornak saját jelölőnégyzete van, és a kérelmező sorait egyenként kell kijelölni. A Kijelöltek letöltése csak a kijelölt sorokat menti egy PDF fájlba, az Összes letöltése minden találatot. A fájlt elküldés előtt át kell olvasni.

A Kijelöltek törlése az üzemeltető jelszavával törli a kijelölt sorokat. Egy felhasználói fiókkal együtt minden hozzá tartozó adat törlődik. Az utolsó adminisztrátor nem törölhető. A törlés végleges, de a mentések a lejáratukig megőrzik a törölt adatokat.

Minden keresés és minden törlés egy sort ír a rendszernaplóba, csak a sorok számával, a keresett név nélkül.
