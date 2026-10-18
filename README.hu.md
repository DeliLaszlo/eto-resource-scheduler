# ETO FC Heti Program: üzemeltetési kézikönyv

In English: [README.md](README.md).

Az ETO FC Heti Program az ETO FC labdarúgóklub heti beosztás- és erőforrás-kezelő webalkalmazása: edzések, mérkőzések, pályák, helyiségek, a kollégium és a heti program. Ez a telepítőcsomagja, minden, ami a futtatásához egy szerveren kell. Forráskódot nem tartalmaz: az alkalmazás konténerképként érkezik a GitHub Container Registryből (`ghcr.io/delilaszlo/eto-backend`, `eto-frontend` és `eto-backup`).

Az [eto-resource-scheduler](https://github.com/delilaszlo/eto-resource-scheduler) nyilvános tárolót a privát forráskód-tárolóból automatikusan frissítjük, ezért az ott közvetlenül végzett módosítások felülíródnak. Minden verziócímke (`v1.0.0`) az azonos számú képfájl-verzióhoz tartozik. Licenc: MIT, lásd [LICENSE](LICENSE).

| Fájl | Szerepe |
| --- | --- |
| `docker-compose.yaml` | A négy szolgáltatás: adatbázis, backend, éjszakai mentés, webszerver |
| `setup.sh` | Egyszer megírja a `.env` fájlt: bekéri a külső adatokat, és minden titkot legenerál |
| `update.sh` | Új verzióra vált: mentés, újraindítás, állapotellenőrzés |
| `proxy/` | HTTPS proxy példák Caddyhez és nginxhez |

## 1. Követelmények

**Szerver**
- Linux x86-64 processzoron, 2 vCPU, 4 GB RAM, 20 GB szabad lemezterület.
- Docker Engine Compose v2-vel (a `docker compose version` működik). A Compose 2.33 és 5.6 kipróbált.
- Az órának szinkronban kell lennie, mert a kétlépcsős azonosítás kódjai időalapúak. A `timedatectl` kimenetében `System clock synchronized: yes` szerepeljen.

Mérések egy 2 vCPU-s, 4 GB-os szerveren: 40 egyidejű felhasználónál a terhelési átlag 1 alatt, a teljes szerver memóriahasználata 800 MB alatt maradt, és a kérések 95%-ára 120 ms-on belül jött válasz. Az első PDF elindít egy Chromiumot, amely a memóriában marad, ettől kezdve a backend körülbelül 0,5 GB-ot használ, renderelés közben legfeljebb 0,6 GB-ot. A lemezt főleg a képfájlok (image-ek) foglalják: körülbelül 5 GB, amíg két verzió van a szerveren (5. fejezet).

**Hálózat**
- A Docker a belső hálózatait a `172.17.0.0/16`–`172.31.0.0/16` és a `192.168.0.0/16` tartományban hozza létre. Ha a helyi hálózat ezek közül bármelyiket használja, az első indítás előtt állítsd be a `default-address-pools` értéket a `/etc/docker/daemon.json` fájlban, különben a szerver elvesztheti a kapcsolatot a hálózat azon részével.
- Közvetlen kimenő hozzáférés (az alkalmazás nem támogat kimenő HTTP proxyt):
  - az SMTP szerver a portjával;
  - `ghcr.io` és `registry-1.docker.io` (képfájlok);
  - `adatbank.mlsz.hu` (mérkőzések);
  - `login.microsoftonline.com` és `graph.microsoft.com` (csak Outlookkal).
- Sok tárhelyszolgáltató tiltja a kimenő 587-es és 465-ös portot. Az SMTP port kiválasztása előtt próbáld ki:
  ```bash
  nc -vz -w 5 <smtp-szerver> 587
  ```
  Ha időtúllépéssel leáll, a port tiltva van. A legtöbb levelezőszolgáltatás más portot is elfogad, például a 2525-öt.

**Levelezőszolgáltatás**
- A feladó címének domainje DNS-ben engedélyezze a szolgáltatást (SPF, DKIM és DMARC), különben a heti program a levélszemétbe kerül.
- A szolgáltatás ne írja át a hivatkozásokat (kattintáskövetés), ne tegyen a levélbe követőképet, és ne adjon hozzá leiratkozási fejlécet. Az átírt hivatkozás a levélszemétszűrőknek adathalászatnak látszik. Ha egy munkatárs leiratkozási hivatkozásra kattint, a szolgáltatás szó nélkül letiltja, és többé nem kapja meg a heti programot.
- Élesítés előtt küldj próbalevelet egy Gmail és egy Outlook.com címre. Egy új feladói domain levele a Microsoftnál gyakran a Levélszemét mappába kerül akkor is, ha minden ellenőrzésen átmegy.

**HTTPS proxy előtte**

Az alkalmazás sima HTTP-t szolgál ki a szerver egy portján. Elé HTTPS proxy kell, és az alkalmazásnak saját hosztnév kell (`eto.example.hu`, nem `example.hu/eto/`). A proxy:
- csak HTTPS-t szolgáljon ki, a HTTP-t irányítsa át HTTPS-re;
- a teljes hosztnevet továbbítsa az alkalmazás portjára;
- engedjen legalább 10 MB-os kéréstörzset;
- ne pufferelje a `text/event-stream` válaszokat (a heti véglegesítés folyamatjelzője);
- engedjen legalább 60 másodperces olvasási időkorlátot;
- állítsa be az `X-Forwarded-For` fejlécet.

Működő példák: `proxy/Caddyfile.example` és `proxy/nginx.conf.example`. A `Strict-Transport-Security` fejléc ajánlott, mindkettőben benne van.

**Tűzfal.** A Docker által közzétett port megkerüli az `ufw`-t. Ha a proxy ugyanazon a gépen fut, a `setup.sh` az alkalmazást a `127.0.0.1` címhez köti, így más nem éri el. Ha a proxy másik gépen fut, az alkalmazás a hálózaton figyel, ezért a portját korlátozd a proxy címére a felhő vagy a hálózat tűzfalában, vagy a `DOCKER-USER` iptables láncban.

## 2. Telepítés

Másold ezt a mappát a szerverre, például a `/opt/etofc` helyre, és abban dolgozz. Arról a gépről, ahol a mappa van (Linux, macOS vagy Windows PowerShell):
```bash
scp -r deploy <felhasználó>@<szerver>:~/etofc
ssh <felhasználó>@<szerver> "sudo mv ~/etofc /opt/etofc"
```
Vagy klónozd a nyilvános tárolót a szerveren, és válts a telepítendő verzióra:
```bash
sudo git clone https://github.com/delilaszlo/eto-resource-scheduler.git /opt/etofc
sudo chown -R $USER: /opt/etofc
cd /opt/etofc && git checkout v1.0.0
```
Az alábbi parancsok feltételezik, hogy a felhasználó a `docker` csoport tagja. Ha nem, minden `docker` és `sh` parancs elé írj `sudo`-t.

1. Ha a képfájlok privátak, egyszer jelentkezz be egy csak `read:packages` jogosultságú GitHub tokennel:
   ```bash
   docker login ghcr.io -u <github-felhasználó>
   ```
2. Írd meg a beállításokat. A paraméter a telepítendő verzió:
   ```bash
   sh setup.sh 1.0.0
   ```
   Bekéri:
   - a nyilvános címet;
   - hány HTTPS proxy áll előtte, és a legközelebbi ezen a gépen fut-e;
   - az SMTP szervert, portot, felhasználót és jelszót, valamint a feladó címét;
   - az üzemeltető e-mail címét;
   - az Outlook adatait (nem kötelező, lásd a 4. fejezetet);
   - az alkalmazás nevét.

   Minden titkot legenerál, és a `.env` fájlt csak a tulajdonosa számára olvashatóan írja meg. **A végén kiír két kulcsot. Ezeket most tárold el a szerveren kívül, két helyen** (jelszókezelő, lezárt boríték). A `BACKUP_ENCRYPTION_KEY` nélkül egyetlen mentés sem állítható vissza. A `TWO_FACTOR_ENCRYPTION_KEY` nélkül a kétlépcsős azonosítást használók nem tudnak belépni. Még jobb, ha a teljes `.env` fájlról van másolat.

   A `setup.sh` nem fut le, ha már van `.env`, mert az új kulcsok használhatatlanná tennék a meglévő mentéseket és a kétlépcsős azonosítást.
3. Indítás:
   ```bash
   docker compose pull
   docker compose up -d
   docker compose ps
   ```
   A backend az első indításkor létrehozza az adatbázis tábláit. Körülbelül egy perc múlva mind a négy szolgáltatás fut, a `db` és a `backend` állapota `healthy`.
4. Ellenőrzés magáról a szerverről (a `setup.sh`-nak megadott porttal):
   ```bash
   curl http://127.0.0.1:3000/health
   ```
   A válasz `{"status":"ok"}`.
5. Állítsd be a HTTPS proxyt, majd nyisd meg a nyilvános címet böngészőben. Megjelenik a bejelentkezési oldal. Belépni még senki sem tud.

Összeomlás vagy újraindítás után minden szolgáltatás magától elindul.

## 3. Kezdő adatok és élesítés

A telepítés nem küld e-mailt. Az alábbi lépések csak az ellenőrzést végző személynek küldenek levelet.

**3.1 Kezdő adatok, egyszer.** A klub kezdő adatai (adminisztrátor, munkatársak, csapatok, helyiségek) a `seed-data.json` fájlban érkeznek. Neveket, e-mail címeket és az adminisztrátor egyszer használatos jelszavát tartalmazza, ezért csak SSH-n (`scp`) utazik, soha nem e-mailben vagy csevegőben.

Ha nulláról kell megírni, indulj ki a képfájlban lévő példából, és cserélj le benne minden értéket, mindenekelőtt az adminisztrátor címét és jelszavát:
```bash
docker compose run --rm -T --no-deps --entrypoint cat backend prisma/seed-data.example.json > seed-data.json
```

```bash
chmod 644 seed-data.json
docker compose run --rm -v "$PWD/seed-data.json:/app/backend/prisma/seed-data.json:ro" backend npm run db:seed
rm seed-data.json
```

A `$PWD` pontosan így szerepeljen. A Compose régebbi verziói az itt megadott relatív útvonalból üres kötetet csinálnak. A fájl nélkül a parancs leáll, és kiírja a szükséges csatolást. Az adatok innentől az adatbázisban és a mentéseiben vannak.

Hibás fájl esetén az adatbázis kiüríthető és újra feltölthető, de csak amíg semmi valódi adat nem került bele:
```bash
docker compose down
docker volume rm etofc_pg_data
docker compose up -d
```

**3.2 Ellenőrzések.** Ezek senkinek sem küldenek levelet a munkatársak közül. Ne véglegesíts hetet, és ne hívj meg munkatársakat.
- A `https://<cím>/health` válasza `{"status":"ok"}`, és a `http://<cím>` HTTPS-re irányít át.
- Az adminisztrátor belép az egyszer használatos jelszóval, megváltoztatja, és beállítja a kétlépcsős azonosítást.
- E-mail: az adminisztrátor a Felhasználók oldalon meghívja az ellenőrző saját címét. A levél megérkezik, és a hivatkozása a nyilvános címet nyitja meg. Utána az adminisztrátor felhasználatlanul törli a meghívót.
- PDF: a Tervező nyomtatási előnézete megjelenik.
- Kimenő hozzáférés a backend konténerből:
  ```bash
  docker compose exec backend node -e "fetch('https://adatbank.mlsz.hu').then(r => console.log(r.status))"
  ```
- Mentések: másnap reggel új fájl van a `backups/` mappában, és megnyílik a kulcs szerveren kívüli másolatával (6.4).

**3.3 Élesítés (a klub adminisztrátora).** Töltsd fel a kollégium alaprajzát, állítsd be a tervezők jogosultságait, majd a Felhasználók oldalon hívd meg azokat a munkatársakat, akik használni fogják az alkalmazást. Akiknek csak a heti PDF kell, azokat nem kell meghívni: így is megkapják. A fel nem használt meghívó 7 nap után lejár, és újraküldhető. Az első valódi véglegesítés mindenkinek elküldi a heti PDF-et.

## 4. Outlook

Az Outlook naptárszinkron ki van kapcsolva, amíg az Outlook értékek üresek a `.env` fájlban. Az alkalmazás többi része normálisan működik, az adminisztrátorok a profiljukon látják, hogy az integráció nincs beállítva.

**4.1 Bekapcsolás**
1. A Microsoft Entra felügyeleti központban regisztrálj egy alkalmazást (vagy használj egy meglévőt):
   - fióktípus: csak ez a szervezet;
   - átirányítási URI, Web platform: `https://<cím>/api/integrations/outlook/callback`;
   - delegált Microsoft Graph jogosultságok: `offline_access`, `User.Read`, `Calendars.ReadWrite`.

   Hozz létre egy ügyfélkulcsot (client secret), és **jegyezd fel a lejárati napját**.
2. Töltsd ki ezeket a sorokat a `.env` fájlban (egy minimális szerveren lehet, hogy nincs szerkesztő: `sudo apt install -y nano`, majd `nano .env`):
   ```
   OUTLOOK_CLIENT_ID=<alkalmazás (ügyfél) azonosító>
   OUTLOOK_CLIENT_SECRET='<az ügyfélkulcs értéke>'
   OUTLOOK_CLIENT_SECRET_EXPIRES=2028-10-15
   OUTLOOK_TENANT_ID=<címtár (bérlő) azonosító>
   ```
   Az `OUTLOOK_REDIRECT_URI` sort a `setup.sh` már megírta. A backend nem indul el, ha az azonosító és a kulcs meg van adva érvényes lejárati nap nélkül.
3. Érvényesítés:
   ```bash
   docker compose up -d
   ```
   Csak a backend jön létre újra, az alkalmazás 10–20 másodpercig nem érhető el. A felhasználók bejelentkezve maradnak. Ne a `docker compose restart` parancsot használd: az nem olvassa újra a `.env` fájlt. Ez minden `.env` módosításra igaz.

A kikapcsolás fordítva megy: ürítsd ki az azonosítót és a kulcsot, majd `docker compose up -d`. A meglévő kapcsolatok megmaradnak, és visszakapcsolás után újra működnek.

**4.2 Az ügyfélkulcs lejár.** A portál legfeljebb 24 hónapot enged. Az üzemeltető címére 30, 7 és 1 nappal az `OUTLOOK_CLIENT_SECRET_EXPIRES` előtt levél érkezik. Csere:
1. Hozz létre új ügyfélkulcsot ugyanabban az alkalmazásregisztrációban, és jegyezd fel a lejárati napját.
2. Az új értéket írd az `OUTLOOK_CLIENT_SECRET`, az új napot az `OUTLOOK_CLIENT_SECRET_EXPIRES` sorba.
3. Futtasd: `docker compose up -d`.
4. Töröld a régi kulcsot a portálon.

Ha a kulcs mégis lejár, a szinkron leáll, és az éjszakai ellenőrzés levelet küld az üzemeltetőnek. A kulcs cseréje elég: a felhasználóknak nem kell újra csatlakozniuk.

## 5. Frissítés

```bash
sh update.sh 1.0.1
```
Ha a mappa a nyilvános tároló klónja, előbb válts ugyanarra a verzióra, hogy a csomag fájljai egyezzenek a képfájlokkal:
```bash
git fetch --tags && git checkout v1.0.1
```

Megerősítést kér, majd:
1. letölti az új verzió képfájljait, ha még nincsenek a szerveren;
2. mentést készít;
3. az új verzióval újraindít, és megvárja, amíg minden szolgáltatás egészséges;
4. törli az előző verziónál régebbi képfájlokat;
5. kiírja a pontos visszaállítási parancsokat.

Az adatbázis-migrációk az új backend indulásakor maguktól lefutnak. Egy frissítés körülbelül 650 MB letöltés. Az előző verzió képfájljai a visszaálláshoz a következő frissítésig a szerveren maradnak.

**Mikor ne frissíts**
- Amíg valaki egy hetet véglegesít: a véglegesítés a backend memóriájában fut, újraindításkor elvész.
- 01:45 és 04:00 között magyar idő szerint: ekkor futnak az éjszakai mentés és feladatok.

**Visszaállás.** A migrációk nem vonhatók vissza, ezért a visszaállás az előző verzió és a közvetlenül a frissítés előtt készült mentés. Az `update.sh` ezeket a parancsokat a verzióval és a fájlnévvel kitöltve írja ki:
```bash
sed -i 's/^APP_VERSION=.*/APP_VERSION=1.0.0/' .env
docker compose stop backend
docker compose exec -T backup sh /backup.sh restore etofc-20261015T164549Z.dump.age
docker compose up -d
```
A frissítés után bevitt adatok elvesznek.

**Biztonsági frissítések.** A képfájlok saját operációs rendszert, Node.js-t, Chromiumot, nginxet és PostgreSQL-t tartalmaznak. Minden kiadás az aktuális alapképekre épül, így egy kiadás telepítése ezeket is frissíti; ha csak egy alapképben van javítás, ugyanannak a kódnak egy új kiadása elég. A szerver saját csomagjait a disztribúció szokásos eszközeivel frissítsd.

## 6. Mentések

**6.1 Ütemezés.** A `backup` szolgáltatás minden éjjel 01:00-kor (UTC) menti az adatbázist a `backups/` mappába, a `BACKUP_ENCRYPTION_KEY` kulccsal titkosítva, és a 14 legújabb fájlt tartja meg. A titkosított fájlok bárhová másolhatók. A fájlok a `root` tulajdonában vannak: bárki olvashatja és másolhatja őket, de kézi törlésükhöz `sudo` kell.

**6.2 A szerveren kívül.** Az ugyanazon a lemezen lévő mentés nem éli túl a szerver elvesztését. Másold a `backups/` mappát naponta máshová, például egy másik gépről:
```bash
rsync -a etofc-server:/opt/etofc/backups/ /srv/etofc-backups/
```

**6.3 Kézi mentés**
```bash
docker compose exec -T backup sh /backup.sh dump
```

**6.4 Mentés ellenőrzése visszaállítás nélkül.** Ott futtasd, ahol a lemásolt mentések vannak, például a szerveren kívüli másolatot tároló gépen. A mentési képfájl kell hozzá, ezért ha a képfájlok privátak, előbb ott is jelentkezz be a `ghcr.io`-ba. Tedd a kulcs szerveren kívüli másolatát (csak az `AGE-SECRET-KEY-...` szöveget) egy fájlba, majd:
```bash
docker run --rm -i -v "$PWD/backups:/backups:ro" --entrypoint sh ghcr.io/delilaszlo/eto-backup:<verzió> \
  -c 'cat > /tmp/key && age -d -i /tmp/key /backups/<fájl> | pg_restore --list > /dev/null && echo OK' < key.txt
rm key.txt
```
`OK` jelenik meg. Rossz kulccsal „no identity matched" hibával leáll. Windows PowerShellben, ahol nincs `<`, másold a kulcsot a vágólapra, és csővezetékkel add át:
```powershell
Get-Clipboard | docker run --rm -i -v "${PWD}/backups:/backups:ro" --entrypoint sh ghcr.io/delilaszlo/eto-backup:<verzió> -c 'cat > /tmp/key && age -d -i /tmp/key /backups/<fájl> | pg_restore --list > /dev/null && echo OK'
```

**6.5 Visszaállítás**
```bash
docker compose stop backend
docker compose exec -T backup sh /backup.sh restore <fájl>
docker compose up -d
```
A `restore` nem fut, amíg a backend fut. Külön adatbázisba állít vissza, és csak siker esetén cseréli le az élőt, így egy sikertelen visszaállítás a jelenlegi adatokat érintetlenül hagyja.

**6.6 Új szerveren.** Másold át a régi `.env` fájlt, ne futtasd a `setup.sh`-t: ugyanazok a kulcsok kellenek a mentésekhez, a kétlépcsős azonosításhoz és az Outlook kapcsolatokhoz. Utána:
1. Másold a mentésfájlt a `backups/` mappába.
2. Futtasd: `docker compose up -d`.
3. Állítsd vissza a 6.5 szerint.

**6.7 Visszaállítás gyakorlása ugyanazon a szerveren.** A mappa második példánya ugyanaz a telepítés, amíg nincs saját projektneve, és az `up` az élő adatbázishoz csatlakozna. Ezért:
1. Másold a mappát, például a `/opt/etofc-drill` helyre, az élő `.env` fájllal együtt, és tegyél egy mentésfájlt a `backups/` mappájába.
2. Írd a `.env` fájljába: `COMPOSE_PROJECT_NAME=etofc-drill`, és mielőtt továbbmész, ellenőrizd, hogy a `docker compose config | head -1` kimenete `name: etofc-drill`.
3. Futtasd: `docker compose up -d db backup`, majd állíts vissza a 6.5 szerint (itt a backend nem fut, a `stop` kimarad). Ebben a mappában ne indítsd el a backendet és a webszervert: az élő `.env` fájllal az éjszakai feladatai az élő telepítés felhasználóinak küldenének levelet.
4. Hasonlítsd össze a sorok számát az élő telepítéssel; futtasd mindkét mappában:
   ```bash
   docker compose exec -T db psql -U eto -d etofc -c "SELECT table_name, (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I', table_name), false, true, '')))[1]::text::int AS rows FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY 1"
   ```
5. A gyakorlás eltávolítása: `docker compose down -v` a mappájában, majd töröld a mappát.

## 7. Felügyelet

- **Elérhetőség:** egy külső figyelő (UptimeRobot vagy a szolgáltatóé) figyelje a `https://<cím>/health` címet, és `{"status":"ok"}` választ várjon. Ez azt mutatja, hogy a backend fut, az adatbázist nem vizsgálja. Az 5 percenként ellenőrző figyelő a rövid kieséseket, például egy frissítés újraindítását, nem veszi észre, és a riasztása akár 5 percet is késhet.
- **Levelezőfiók:** egyes levelezőszolgáltatások értesítés nélkül letiltják az egy ideig nem használt SMTP hozzáférést. Az üzemeltetőnek szóló hibalevelek ugyanezen a fiókon mennek, így ezt semmi sem jelzi. Hosszabb csendes időszak, például a nyári szünet után küldj egy próbameghívót.
- **Mentések:** a `backups/` legújabb fájlja legyen 26 óránál fiatalabb:
  ```bash
  find backups -name 'etofc-*.dump.age' -mmin -1560 | grep -q . || echo "no recent backup"
  ```
- **Háttérfeladatok:** egy sikertelen éjszakai feladat levelet küld az üzemeltető címére.
- **Naplók:** `docker compose logs --tail 200 backend`. Minden szolgáltatás három 10 MB-os naplófájlt tart meg.

## 8. Karbantartási feladatok

**A nyilvános cím megváltoztatása**
1. Írd az új címet a `.env` fájl `FRONTEND_URL` és `OUTLOOK_REDIRECT_URI` sorába.
2. Módosítsd az átirányítási URI-t az Azure alkalmazásregisztrációban.
3. Frissítsd a proxyt.
4. Futtasd: `docker compose up -d`.

**Háttérfeladat kézi futtatása.** A feladatok: `outlook-token-health`, `outlook-repair`, `outlook-prune`, `mlsz-refresh` és `dorm-digest`:
```bash
docker compose exec backend node dist/src/jobs/cli.js mlsz-refresh
```

**A PostgreSQL 16 támogatása 2028 novemberéig tart.** Az újabb főverzióra váltás alkalmazáskiadásként érkezik, hozzá illő mentési képfájllal. A menete:
1. Készíts mentést, és ellenőrizd (6.4).
2. Futtasd: `docker compose down`.
3. Futtasd: `docker volume rm etofc_pg_data`.
4. Telepítsd a kiadást.
5. Futtasd: `docker compose up -d db backup`.
6. Állítsd vissza (6.5).
7. Futtasd: `docker compose up -d`.

## 9. Hibaelhárítás

| Jelenség | Ok |
| --- | --- |
| A `docker compose` leáll ezzel: „... nincs megadva a .env fájlban" | A `.env` ezen sora hiányzik vagy üres |
| A backend újra és újra elindul, a naplóban „Hibás éles konfiguráció" | A naplósor megnevezi a hibás `.env` értéket |
| Minden belépés és mentés 403-mal hiúsul meg | A `FRONTEND_URL` nem pontosan a böngészőben lévő cím (séma, hoszt és port, perjel nélkül a végén) |
| Sima HTTP-n nem marad meg a bejelentkezés | A munkamenet sütik csak HTTPS-en működnek. Használd a proxy HTTPS címét |
| Egyszerre mindenki „Túl sok kérés" üzenetet kap, kevés felhasználónál is | A `TRUST_PROXY_HOPS` kisebb, mint a proxyk száma plusz egy, így minden felhasználó egy közös korláton osztozik |
| Egy közös címről (a klub wifije) csatlakozók csúcsidőben „Túl sok kérés" üzenetet kapnak | A korlát címenként 15 percenként 5000 kérés. Emelhető: `RATE_LIMIT_GLOBAL_MAX=<n>` a `.env` fájlban, majd `docker compose up -d` |
| Az alaprajz vagy a PDF feltöltése nem sikerül | A proxy kéréstörzs-korlátja 10 MB alatt van |
| A véglegesítés folyamatjelzője megáll, majd ugrik | A proxy puffereli a `text/event-stream` választ |
| Nem érkeznek e-mailek | `docker compose logs backend`. Ellenőrizd a feladói domain SPF és DKIM rekordjait is az SMTP szolgáltatáshoz |
| Egy meghívó küldése fél percig tart, majd sikertelen | A szolgáltató tiltja az SMTP portot. Próbáld ki az 1. fejezet szerint, és használd a levelezőszolgáltatás másik portját |
| A levelek a levélszemétbe kerülnek | Lásd a levelezőszolgáltatás követelményeit az 1. fejezetben |
| A 6.4 `docker run` parancsa „unauthorized" hibával leáll | Az a gép nincs bejelentkezve a `ghcr.io`-ba (2. fejezet, 1. lépés) |
| A `docker volume ls` egy név nélküli kötetet is mutat az `etofc_pg_data` mellett | A mentési szolgáltatás saját, üres kötete. Ártalmatlan. `docker compose down -v` után a `docker volume prune` eltávolítja a megmaradt név nélküli köteteket, a nevesítetteket soha nem érinti |
| Az API hívások `up -d` után néhány másodpercig 502-vel hiúsulnak meg | A backend még indul. Akkor válaszol, amikor a `docker compose ps` `healthy` állapotot mutat |
| `[pdf]` sorok a naplóban a Chromium homokozójáról | Konténerben ez várható. A PDF-ek így is elkészülnek |

## 10. Titkok

Minden titok a `.env` fájlban van, amelyet csak a tulajdonosa olvashat. Ne módosíts egy értéket, hacsak ez a táblázat nem mondja, hogy biztonságos.

| Érték | Mit okoz a módosítása |
| --- | --- |
| `JWT_SECRET` | Bármikor biztonságos. Mindenki kijelentkezik |
| `OUTLOOK_STATE_SECRET` | Bármikor biztonságos. Az utolsó 10 percben indított Outlook csatlakozás meghiúsul, és újrapróbálható |
| `TWO_FACTOR_ENCRYPTION_KEY` | **Soha ne módosítsd, és ne veszítsd el.** Minden kétlépcsős azonosítást használó kizáródik |
| `OUTLOOK_TOKEN_ENCRYPTION_KEY` | Minden csatlakozott felhasználónak újra kell csatlakoztatnia az Outlookot |
| `BACKUP_ENCRYPTION_KEY` | Az új mentések az új kulcsot használják. A régi kulcsot addig őrizd meg, amíg vele készült mentés létezik |
| `POSTGRES_PASSWORD` | Futtasd: `docker compose exec db psql -U eto -d etofc -c "ALTER ROLE eto WITH PASSWORD '<új>'"`, majd ugyanezt az értéket írd a `.env` fájlba, és futtasd: `docker compose up -d` |
| `SMTP_PASS` | A levelezőszolgáltató adja. Előbb ott módosítsd, aztán a `.env` fájlban |
| `OUTLOOK_CLIENT_SECRET` | Lásd a 4.2-t |
