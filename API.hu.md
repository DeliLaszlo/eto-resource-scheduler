# Az ETO FC Heti Program külső API-ja

Más rendszerek ezen az API-n keresztül olvashatják a véglegesített heti programot. Az API csak olvasható. A dokumentum angol változata az [API.md](API.md).

## 1. Hozzáférés

Az alapcím az alkalmazás címe, utána `/api/external/v1`.

```text
https://eto.example.hu/api/external/v1
```

Minden kéréshez API kulcs kell az `Authorization` fejlécben. A kulcsot az üzemeltető hozza létre az üzemeltetői konzol API kulcsok kártyáján, külső rendszerenként egyet. A konzol csak egyszer mutatja meg, az elveszett kulcs helyett új készül. A kulcsot csak szerver tárolhatja.

```http
GET /api/external/v1/age-groups HTTP/1.1
Host: eto.example.hu
Authorization: Bearer eto_3f9c2b7a51d84e0f96a2c4b8d7e1f03a5b6c7d8e9f0a1b2c3d4e5f60718293a4
```

## 2. Szabályok

| Téma | Szabály |
| --- | --- |
| Formátum | JSON, UTF-8 kódolással |
| Siker | `{ "status": "success", "data": { } }`, HTTP 200 |
| Hiba | `{ "status": "error", "code": "...", "message": "..." }`, 4xx vagy 5xx státusszal. A `code` állandó, a `message` embereknek szóló magyar szöveg |
| Napok | `YYYY-MM-DD`, naptári nap a klub időzónájában, ami `Europe/Budapest` |
| Időpontok | ISO 8601, UTC-ben, például `2026-11-10T15:00:00.000Z` |
| Üres értékek | Az érték nélküli mező `null`. Mező sosem marad ki |
| Azonosítók | UUID szövegek. Az esemény `id` értéke az esemény teljes életében ugyanaz |

## 3. Korosztályok

```text
GET /age-groups
```

A klub korosztályai, a klub saját sorrendjében. A korosztály `id` értéke a többi végpont `ageGroupId` szűrőjének értéke.

```json
{
  "status": "success",
  "data": {
    "ageGroups": [
      { "id": "0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70", "name": "U17", "gender": "MALE", "division": "Akadémia" },
      { "id": "1c9f6d3b-8e5f-4a2b-8c4d-3f7e9b2a5d81", "name": "U16", "gender": "MALE", "division": "Akadémia" }
    ]
  }
}
```

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| `id` | `0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70` | |
| `name` | `U17` | A klubon belül egyedi |
| `gender` | `MALE` | `MALE`, `FEMALE` vagy `UNISEX` |
| `division` | `Akadémia` | A szakág, amelyhez a korosztály tartozik, vagy `null` |

## 4. Egy időszak eseményei

```text
GET /events?from=2026-11-09&to=2026-11-15
GET /events?from=2026-11-09&to=2026-11-15&ageGroupId=0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70&type=TRAINING
```

A véglegesített események, amelyek a `from` és a `to` közötti napokon kezdődnek, mindkét napot beleértve, kezdés szerint rendezve.

| Paraméter | Kötelező | Példa | Megjegyzés |
| --- | --- | --- | --- |
| `from` | igen | `2026-11-09` | Első nap |
| `to` | igen | `2026-11-15` | Utolsó nap. Az időszak legfeljebb 90 nap lehet |
| `ageGroupId` | nem | `0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70` | Csak ennek a korosztálynak az eseményei |
| `type` | nem | `TRAINING` | `TRAINING`, `MATCH` vagy `OTHER` |

```json
{
  "status": "success",
  "data": {
    "events": [
      {
        "id": "2daa7e4c-9f6a-4b3c-9d5e-4a8f0c3b6e92",
        "type": "TRAINING",
        "title": "Edzés",
        "date": "2026-11-10",
        "startsAt": "2026-11-10T15:00:00.000Z",
        "endsAt": "2026-11-10T16:30:00.000Z",
        "ageGroups": [
          { "id": "0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70", "name": "U17" }
        ],
        "trainingType": "Pályaedzés",
        "pitches": ["Camping 1/2"],
        "dressingRooms": [
          { "name": "3-as öltöző", "ageGroup": "U17" }
        ],
        "location": null,
        "match": null,
        "updatedAt": "2026-11-06T09:30:00.000Z"
      },
      {
        "id": "3ebb8f5d-a07b-4c4d-ae6f-5b9a1d4c7fa3",
        "type": "MATCH",
        "title": "ETO FC U17 – Vasas U17",
        "date": "2026-11-14",
        "startsAt": "2026-11-14T10:00:00.000Z",
        "endsAt": "2026-11-14T12:00:00.000Z",
        "ageGroups": [
          { "id": "0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70", "name": "U17" }
        ],
        "trainingType": null,
        "pitches": ["Centerpálya"],
        "dressingRooms": [
          { "name": "1-es öltöző", "ageGroup": "U17" }
        ],
        "location": null,
        "match": {
          "venue": "HOME",
          "homeTeam": "ETO FC U17",
          "awayTeam": "Vasas U17",
          "competition": "U17 Kiemelt"
        },
        "updatedAt": "2026-11-06T09:30:00.000Z"
      }
    ],
    "finalizedWeeks": ["2026-11-09"]
  }
}
```

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| `id` | `2daa7e4c-9f6a-4b3c-9d5e-4a8f0c3b6e92` | |
| `type` | `TRAINING` | `TRAINING`, `MATCH` vagy `OTHER` |
| `title` | `Edzés` | |
| `date` | `2026-11-10` | Az esemény napja. `null`, amíg a nap nem ismert |
| `startsAt` | `2026-11-10T15:00:00.000Z` | `null`, amíg az időpont nem ismert. A `date` ilyenkor is érvényes |
| `endsAt` | `2026-11-10T16:30:00.000Z` | A `startsAt` mezővel együtt `null` |
| `ageGroups` | | Minden részt vevő korosztály, `id` és `name` mezővel |
| `trainingType` | `Pályaedzés` | Az edzéstípus neve, vagy `null` |
| `pitches` | `["Camping 1/2"]` | Az esemény pályái. Az `1/2` és az `1/4` a pálya egy részét jelöli. A `Camping / Műfű` alakú elem a két pálya egyikét jelenti. Külső helyszínnél üres lista |
| `dressingRooms` | | A hazai öltözők. A `name` az öltöző neve, az `ageGroup` az öltözőt használó korosztály neve |
| `location` | `Budapest, Illovszky Stadion` | A klub pályáin kívüli helyszín, vagy `null` |
| `match` | | `null`, kivéve ha a `type` értéke `MATCH` |
| `match.venue` | `HOME` | `HOME` vagy `AWAY` |
| `match.homeTeam` | `ETO FC U17` | Tornánál `null` |
| `match.awayTeam` | `Vasas U17` | Tornánál `null` |
| `match.competition` | `U17 Kiemelt` | `null`, ha nem ismert |
| `updatedAt` | `2026-11-06T09:30:00.000Z` | Az esemény utolsó módosítása |

A `finalizedWeeks` a kért időszak már kiadott heteit sorolja fel, mindegyiket a hétfőjének napjával. A listában szereplő hét programja végleges, így ha arra a hétre nincs esemény, a korosztálynak nincs programja. A listából hiányzó hét még nincs kiadva, az eseményei a véglegesítés után jelennek meg.

## 5. Változásjelző

```text
GET /events/revision?from=2026-11-09&to=2026-11-15
GET /events/revision?from=2026-11-09&to=2026-11-15&ageGroupId=0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70&type=TRAINING
```

A paraméterek megegyeznek az időszak eseményeinek paramétereivel. A válasz kicsi, ezért gyakori lekérdezésre alkalmas. Ha a `count` vagy a `lastChangedAt` eltér az utoljára eltárolt választól, az időszak eseményeit újra be kell olvasni.

```json
{
  "status": "success",
  "data": {
    "revision": { "count": 42, "lastChangedAt": "2026-11-06T09:30:00.000Z" }
  }
}
```

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| `count` | `42` | Az események száma, amennyit ugyanez a kérés az `/events` végponton visszaad |
| `lastChangedAt` | `2026-11-06T09:30:00.000Z` | Közülük a legkésőbbi `updatedAt`, vagy `null`, ha nincs esemény |

## 6. Egy esemény

```text
GET /events/2daa7e4c-9f6a-4b3c-9d5e-4a8f0c3b6e92
```

Egy esemény az `id` értéke alapján, a 4. fejezet mezőivel. A törölt esemény 404 választ ad `event_not_found` kóddal.

```json
{
  "status": "success",
  "data": {
    "event": {
      "id": "2daa7e4c-9f6a-4b3c-9d5e-4a8f0c3b6e92",
      "type": "TRAINING",
      "title": "Edzés",
      "date": "2026-11-10",
      "startsAt": "2026-11-10T15:00:00.000Z",
      "endsAt": "2026-11-10T16:30:00.000Z",
      "ageGroups": [
        { "id": "0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70", "name": "U17" }
      ],
      "trainingType": "Pályaedzés",
      "pitches": ["Camping 1/2"],
      "dressingRooms": [
        { "name": "3-as öltöző", "ageGroup": "U17" }
      ],
      "location": null,
      "match": null,
      "updatedAt": "2026-11-06T09:30:00.000Z"
    }
  }
}
```

## 7. Közelgő mérkőzések

```text
GET /matches
GET /matches?from=2026-11-10&ageGroupId=0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70&limit=20
```

A mérkőzések egy naptól kezdve, dátum szerint rendezve. A listának két forrása van. A véglegesített hét mérkőzése a programból származik, és van `eventId` értéke. Az a mérkőzés, amelyet a klub még nem véglegesített, a Magyar Labdarúgó Szövetség (MLSZ) sorsolásából származik, és az `eventId` értéke `null`. Az időpontja még változhat.

| Paraméter | Kötelező | Példa | Megjegyzés |
| --- | --- | --- | --- |
| `from` | nem | `2026-11-10` | Első nap. Ha kimarad, a mai nap |
| `ageGroupId` | nem | `0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70` | Csak ennek a korosztálynak a mérkőzései |
| `limit` | nem | `20` | A mérkőzések száma, legfeljebb 100. Ha kimarad, 20 |

```json
{
  "status": "success",
  "data": {
    "matches": [
      {
        "eventId": "3ebb8f5d-a07b-4c4d-ae6f-5b9a1d4c7fa3",
        "title": "ETO FC U17 – Vasas U17",
        "homeTeam": "ETO FC U17",
        "awayTeam": "Vasas U17",
        "date": "2026-11-14",
        "time": "11:00",
        "venue": "HOME",
        "location": null,
        "competition": "U17 Kiemelt",
        "ageGroup": "U17",
        "pitches": ["Centerpálya"],
        "dressingRoom": "1-es öltöző"
      },
      {
        "eventId": null,
        "title": "Fehérvár U17 – ETO FC U17",
        "homeTeam": "Fehérvár U17",
        "awayTeam": "ETO FC U17",
        "date": "2026-11-21",
        "time": "11:00",
        "venue": "AWAY",
        "location": "Székesfehérvár, Sóstói út",
        "competition": "U17 Kiemelt",
        "ageGroup": "U17",
        "pitches": [],
        "dressingRoom": null
      }
    ]
  }
}
```

| Mező | Példa | Megjegyzés |
| --- | --- | --- |
| `eventId` | `3ebb8f5d-a07b-4c4d-ae6f-5b9a1d4c7fa3` | Az esemény `id` értéke a véglegesített programban, vagy `null` |
| `title` | `ETO FC U17 – Vasas U17` | |
| `homeTeam` | `ETO FC U17` | Tornánál `null` |
| `awayTeam` | `Vasas U17` | Tornánál `null` |
| `date` | `2026-11-14` | |
| `time` | `11:00` | Kezdés a klub időzónájában, vagy `null`, amíg nem ismert |
| `venue` | `HOME` | `HOME` vagy `AWAY` |
| `location` | `Székesfehérvár, Sóstói út` | A mérkőzés helyszíne, ha nem a klub pályáin van, vagy `null` |
| `competition` | `U17 Kiemelt` | `null`, ha nem ismert |
| `ageGroup` | `U17` | A klub pályára lépő korosztályának neve |
| `pitches` | `["Centerpálya"]` | Üres, amíg a mérkőzés nincs a véglegesített programban |
| `dressingRoom` | `1-es öltöző` | A klub csapatának öltözője, vagy `null` |

## 8. Hibák

```json
{
  "status": "error",
  "code": "api_key_invalid",
  "message": "Az API kulcs érvénytelen."
}
```

| Státusz | Kód | Ok |
| --- | --- | --- |
| 400 | változó | Egy paraméter hiányzik vagy hibás. Az `errors` lista a `path` mezőben nevezi meg a hibás paramétereket |
| 400 | `date_range_too_long` | Az időszak hosszabb 90 napnál |
| 401 | `api_key_required` | Az `Authorization` fejléc hiányzik, vagy nem a `Bearer` szó és a kulcs áll benne |
| 401 | `api_key_invalid` | A kulcs hibás, vagy az üzemeltető törölte |
| 404 | `event_not_found` | Ezzel az `id` értékkel nincs véglegesített esemény |
| 404 | `not_found` | A cím nem része az API-nak |
| 429 | `too_many_requests` | A 9. fejezet korlátja betelt |
| 500 | `server_error` | Hiba az alkalmazásban. Az üzemeltető a rendszernaplóban látja |

## 9. Korlátok

Egy kulcs 15 perc alatt 600 kérést küldhet. A keret állását minden válasz `RateLimit-Limit`, `RateLimit-Remaining` és `RateLimit-Reset` fejléce mutatja. 429 válasz után a `RateLimit-Reset` értéke adja meg, hány másodperc múlva küldhető új kérés. A változások figyelésére az `/events/revision` végpont szolgál, az `/events` végpontot elég változás után olvasni.
