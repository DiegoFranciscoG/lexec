# Modelo de datos

Catálogo en SQLite (Ecto + `ecto_sqlite3`); el texto buscable vive además en Meilisearch (índice `paragraphs`).
Los nombres de tablas y campos están en inglés; la tabla de equivalencias con el documento base está al final.
Las migraciones están en `priv/repo/migrations/` (versionadas por fecha, como Flyway/Alembic).

```mermaid
erDiagram
  RULINGS ||--o{ PARAGRAPHS : "tiene"
  RULINGS ||--o{ RULING_CITATIONS : "cita"
  RULINGS |o--o{ RULING_CITATIONS : "es citada"
  RULINGS ||--o{ CITED_NORMS : "invoca"
  RULINGS ||--o{ ANONYMIZATION_STATS : "conteos"
  RULINGS ||--o{ REVIEW_ITEMS : "revisión"
  FETCHED_DOCUMENTS ||--o| RULINGS : "origen"
  EXCLUSIONS }o--|| FETCHED_DOCUMENTS : "motivo"
  CORRECTION_REQUESTS }o--o| RULINGS : "sobre"

  RULINGS {
    int id PK
    string case_number UK "1234-19-EP/23"
    string case_file "1234-19-EP"
    string action_type "catálogo priv/rules/action_types.yaml"
    int ruling_year
    date decided_on
    string rapporteur "juez/a ponente (autoridad, no se anonimiza)"
    string decision "accepted|partially_accepted|dismissed|rejected|other"
    string official_url
    string pdf_sha256 UK
    string status "pending_review|published|withdrawn"
    string rules_version
    int paragraph_count
  }
  PARAGRAPHS {
    int id PK
    int ruling_id FK
    int number
    text text "solo texto anonimizado"
  }
  RULING_CITATIONS {
    int id PK
    int citing_ruling_id FK
    string cited_case_number
    int cited_ruling_id FK "null si no está en el corpus"
    int paragraph_number
  }
  CITED_NORMS {
    int id PK
    int ruling_id FK
    string norm_body "CRE, LOGJCC, ..."
    string article
    int paragraph_number
  }
  EXCLUSIONS {
    int id PK
    string source_url UK
    string case_number
    string reason "minors|violence|reserved|other"
    string rule_id
    string rules_version
  }
  ANONYMIZATION_STATS {
    int id PK
    int ruling_id FK
    string entity_type "person|id_number|phone|email|address"
    int count
    string rules_version
    string ner_model
  }
  REVIEW_ITEMS {
    int id PK
    int ruling_id FK
    string reason
    string status "pending|approved|withdrawn"
    string reviewer
    datetime reviewed_at
  }
  CORRECTION_REQUESTS {
    int id PK
    string case_number
    int paragraph_number
    string request_type "correction|withdrawal"
    text reason "máx. 1000"
    string contact_email "opcional, con consentimiento"
    bool consent
    string status "received|withdrawn|corrected|rejected"
    date due_on
    datetime resolved_at
  }
  FETCHED_DOCUMENTS {
    int id PK
    string url UK
    string sha256
    string status "ok|failed|excluded"
    string error
    datetime fetched_at
  }
```

## Tablas, restricciones y reglas

| Tabla | Campo | Tipo | Restricción | Regla / fuente (# en investigacion.md) |
|---|---|---|---|---|
| rulings | case_number | string | único, formato `^\d{1,5}-\d{2}-[A-Z]{2,3}/\d{2}$` o antiguo `^\d{3}-\d{2}-S[A-Z]{2,3}-CC$` | Numeración oficial (#4, S-6) |
| rulings | action_type | string | en catálogo `priv/rules/action_types.yaml` | Siglas oficiales (#4, S-3) |
| rulings | rapporteur | string | nulo permitido | Autoridad en ejercicio: no se anonimiza (#1 §7.2.2) |
| rulings | official_url | string | obligatorio, `https://` | Enlace al documento oficial en cada resultado (T-09) |
| rulings | pdf_sha256 | string(64) | único si no es nulo | No descargar ni indexar dos veces (T-07) |
| rulings | status | enum | `pending_review` no se indexa | Revisión humana antes de publicar (#1 §7.2.1 f) |
| paragraphs | (ruling_id, number) | int | único; `number ≥ 1` | Párrafos numerados de la sentencia (T-04) |
| paragraphs | text | text | ya anonimizado; nunca el original | Minimización (#1 §7.2.1 c, #6) |
| ruling_citations | (citing, cited_case_number, paragraph_number) | — | único | Red de precedentes (T-05) |
| cited_norms | norm_body | string | en catálogo `priv/rules/norms.yaml` | Normas citadas |
| exclusions | — | — | **sin campos de texto de la sentencia** | §7.2.9 c y §7.2.2 b (#1) |
| anonymization_stats | count | int | ≥ 0; **nunca el dato original** | Minimización (#6) |
| correction_requests | reason | text | 10–1000 caracteres | Canal de corrección y retiro (T-11) |
| correction_requests | contact_email | string | opcional; solo si `consent = true` | Consentimiento (#6) |
| correction_requests | due_on | date | `inserted_at + response_days` (`priv/rules/app.yaml`) | Plazo visible de respuesta |
| fetched_documents | url | string | único | Caché: nunca se descarga dos veces (T-07) |

Borrados: `paragraphs`, `ruling_citations`, `cited_norms`, `anonymization_stats` y `review_items` usan `ON DELETE CASCADE`.
`ruling_citations.cited_ruling_id` usa `ON DELETE SET NULL` (si se retira la citada, la cita textual al número de caso sigue siendo pública).

## Índice Meilisearch `paragraphs`

| Campo | Uso |
|---|---|
| `id` (`<ruling_id>-<number>`) | clave primaria |
| `text` | buscable |
| `case_number`, `action_type`, `ruling_year`, `rapporteur`, `decided_on`, `paragraph_number`, `official_url`, `ruling_id` | mostrados; `action_type`, `ruling_year`, `rapporteur`, `ruling_id` filtrables |
| `_vectors.e5` | embedding de 384 dimensiones calculado en Elixir (embedder `userProvided`) |

## Equivalencias con el documento base

| Documento base | Código |
|---|---|
| sentencia | `rulings` |
| parrafo | `paragraphs` |
| cita_sentencia | `ruling_citations` |
| norma_citada | `cited_norms` |
| exclusion | `exclusions` |
| anonimizacion | `anonymization_stats` |
| revision | `review_items` |
| correccion | `correction_requests` |
| (nuevo) caché de descargas | `fetched_documents` |

## Datos de ejemplo

`priv/seeds/corpus/*.txt` contiene sentencias **ficticias** escritas para este proyecto (personas, cédulas y números de caso inventados). Ninguna es una sentencia real de la Corte.
