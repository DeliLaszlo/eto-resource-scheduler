# ETO FC Heti Program external API

Other systems can read the finalized weekly programme through this API. The API is read-only. The Hungarian version of this document is [API.hu.md](API.hu.md).

## 1. Access

The base address is the address of the app followed by `/api/external/v1`.

```text
https://eto.example.hu/api/external/v1
```

Every request needs an API key in the `Authorization` header. The operator creates the key on the API keys card of the operator console, one for each external system. The console shows it only once, and a lost key is replaced by a new one. Only a server may store the key.

```http
GET /api/external/v1/age-groups HTTP/1.1
Host: eto.example.hu
Authorization: Bearer eto_3f9c2b7a51d84e0f96a2c4b8d7e1f03a5b6c7d8e9f0a1b2c3d4e5f60718293a4
```

## 2. Conventions

| Topic | Rule |
| --- | --- |
| Format | JSON in UTF-8 |
| Success | `{ "status": "success", "data": { } }` with HTTP 200 |
| Error | `{ "status": "error", "code": "...", "message": "..." }` with a 4xx or 5xx status. The `code` is stable, the `message` is Hungarian text for people |
| Days | `YYYY-MM-DD`, a calendar day in the club's time zone, `Europe/Budapest` |
| Instants | ISO 8601 in UTC, such as `2026-11-10T15:00:00.000Z` |
| Empty values | A field without a value is `null`. No field is ever left out |
| Identifiers | UUID strings. An event keeps its `id` for its whole life |

## 3. Age groups

```text
GET /age-groups
```

The age groups of the club, in the order the club lists them. The `id` of an age group is the value of the `ageGroupId` filter of the other endpoints.

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

| Field | Example | Note |
| --- | --- | --- |
| `id` | `0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70` | |
| `name` | `U17` | Unique within the club |
| `gender` | `MALE` | `MALE`, `FEMALE` or `UNISEX` |
| `division` | `Akadémia` | The division the age group belongs to, or `null` |

## 4. Events of a period

```text
GET /events?from=2026-11-09&to=2026-11-15
GET /events?from=2026-11-09&to=2026-11-15&ageGroupId=0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70&type=TRAINING
```

The finalized events that start on the days from `from` to `to`, both included, ordered by start.

| Parameter | Required | Example | Note |
| --- | --- | --- | --- |
| `from` | yes | `2026-11-09` | First day |
| `to` | yes | `2026-11-15` | Last day. The period can be at most 90 days |
| `ageGroupId` | no | `0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70` | Only the events of this age group |
| `type` | no | `TRAINING` | `TRAINING`, `MATCH` or `OTHER` |

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

| Field | Example | Note |
| --- | --- | --- |
| `id` | `2daa7e4c-9f6a-4b3c-9d5e-4a8f0c3b6e92` | |
| `type` | `TRAINING` | `TRAINING`, `MATCH` or `OTHER` |
| `title` | `Edzés` | |
| `date` | `2026-11-10` | The day of the event. `null` while the day is not known |
| `startsAt` | `2026-11-10T15:00:00.000Z` | `null` while the time is not known. The `date` is still valid then |
| `endsAt` | `2026-11-10T16:30:00.000Z` | `null` together with `startsAt` |
| `ageGroups` | | Every age group that takes part, each with `id` and `name` |
| `trainingType` | `Pályaedzés` | The name of the training type, or `null` |
| `pitches` | `["Camping 1/2"]` | The pitches of the event. `1/2` and `1/4` mark a part of a pitch. An item such as `Camping / Műfű` means one of the two pitches. An empty list for an outside location |
| `dressingRooms` | | The home dressing rooms. `name` is the name of the room, `ageGroup` the name of the age group that uses it |
| `location` | `Budapest, Illovszky Stadion` | A place outside the club's pitches, or `null` |
| `match` | | `null` unless `type` is `MATCH` |
| `match.venue` | `HOME` | `HOME` or `AWAY` |
| `match.homeTeam` | `ETO FC U17` | `null` for a tournament |
| `match.awayTeam` | `Vasas U17` | `null` for a tournament |
| `match.competition` | `U17 Kiemelt` | `null` when not known |
| `updatedAt` | `2026-11-06T09:30:00.000Z` | The last change of the event |

`finalizedWeeks` lists the weeks of the requested period that are already published, each by the day of its Monday. The programme of a listed week is final, so when it has no events the age group has nothing that week. A week missing from the list is not published yet, and its events appear after the club finalizes it.

## 5. Change indicator

```text
GET /events/revision?from=2026-11-09&to=2026-11-15
GET /events/revision?from=2026-11-09&to=2026-11-15&ageGroupId=0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70&type=TRAINING
```

The parameters are the same as for the events of a period. The answer is small, so it suits frequent polling. When `count` or `lastChangedAt` differs from the last stored answer, the events of the period have to be read again.

```json
{
  "status": "success",
  "data": {
    "revision": { "count": 42, "lastChangedAt": "2026-11-06T09:30:00.000Z" }
  }
}
```

| Field | Example | Note |
| --- | --- | --- |
| `count` | `42` | The number of events the same request to `/events` returns |
| `lastChangedAt` | `2026-11-06T09:30:00.000Z` | The latest `updatedAt` among them, or `null` when there are none |

## 6. One event

```text
GET /events/2daa7e4c-9f6a-4b3c-9d5e-4a8f0c3b6e92
```

One event by its `id`, with the fields of section 4. A deleted event answers 404 with the code `event_not_found`.

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

## 7. Upcoming matches

```text
GET /matches
GET /matches?from=2026-11-10&ageGroupId=0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70&limit=20
```

The matches from a day onwards, ordered by date. The list has two sources. A match of a finalized week comes from the programme and has an `eventId`. A match the club has not finalized yet comes from the fixture list of the Hungarian Football Federation (MLSZ) and has `eventId` `null`. Its date can still change.

| Parameter | Required | Example | Note |
| --- | --- | --- | --- |
| `from` | no | `2026-11-10` | First day. Today when left out |
| `ageGroupId` | no | `0b8f5c2a-7d4e-4f1a-9b3c-2e6d8a1f4c70` | Only the matches of this age group |
| `limit` | no | `20` | The number of matches, at most 100. 20 when left out |

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

| Field | Example | Note |
| --- | --- | --- |
| `eventId` | `3ebb8f5d-a07b-4c4d-ae6f-5b9a1d4c7fa3` | The `id` of the event in the finalized programme, or `null` |
| `title` | `ETO FC U17 – Vasas U17` | |
| `homeTeam` | `ETO FC U17` | `null` for a tournament |
| `awayTeam` | `Vasas U17` | `null` for a tournament |
| `date` | `2026-11-14` | |
| `time` | `11:00` | Kick-off in the club's time zone, or `null` while not known |
| `venue` | `HOME` | `HOME` or `AWAY` |
| `location` | `Székesfehérvár, Sóstói út` | The place of the match when it is not on the club's pitches, or `null` |
| `competition` | `U17 Kiemelt` | `null` when not known |
| `ageGroup` | `U17` | The name of the club's age group that plays |
| `pitches` | `["Centerpálya"]` | Empty until the match is in the finalized programme |
| `dressingRoom` | `1-es öltöző` | The dressing room of the club's team, or `null` |

## 8. Errors

```json
{
  "status": "error",
  "code": "api_key_invalid",
  "message": "Az API kulcs érvénytelen."
}
```

| Status | Code | Cause |
| --- | --- | --- |
| 400 | varies | A parameter is missing or malformed. The `errors` list names each faulty parameter in its `path` field |
| 400 | `date_range_too_long` | The period is longer than 90 days |
| 401 | `api_key_required` | The `Authorization` header is missing or is not `Bearer` followed by the key |
| 401 | `api_key_invalid` | The key is wrong or the operator deleted it |
| 404 | `event_not_found` | No finalized event has this `id` |
| 404 | `not_found` | The address is not part of the API |
| 429 | `too_many_requests` | The limit of section 9 is reached |
| 500 | `server_error` | A fault in the app. The operator sees it in the system log |

## 9. Limits

One key can send 600 requests in 15 minutes. The `RateLimit-Limit`, `RateLimit-Remaining` and `RateLimit-Reset` headers of every answer show the state of the allowance. After a 429 answer the value of `RateLimit-Reset` is the number of seconds until a new request can be sent. The `/events/revision` endpoint is for watching for changes, and `/events` needs reading only after one.
