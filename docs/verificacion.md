# Verificación legal y técnica (Fase 1)

Fecha de verificación: **2026-11-12**. Las fuentes numeradas están en [investigacion.md](investigacion.md).

## a) Cómo publica hoy la Corte sus sentencias

- **Buscador oficial:** sistema SACC de la Corte (`esacc.corteconstitucional.gob.ec`) y el buscador de relatoría. Las sentencias se publican como **PDF** descargables por una API de almacenamiento (`/storage/api/v1/10_DWL_FL/<token-base64>`), sin un listado masivo ni un formato abierto (#2, #4).
- **robots.txt:** el portal principal permite todo (`Disallow:` vacío). Los subdominios de documentos y buscador no publican un robots.txt válido (301/404) ⇒ según RFC 9309 se trata como "sin restricciones", pero LEXEC aplica igualmente sus propios límites (#2, #3).
- **Términos de uso:** no se encontraron publicados (SUPUESTO S-1).
- **Decisión:** la ruta preferida es pedir el corpus en bloque por **LOTAIP**. Borrador listo en [solicitud-lotaip.md](solicitud-lotaip.md). Si hubiera que recopilar del portal: 1 petición/s como máximo, `User-Agent` con contacto (variables `HARVEST_USER_AGENT` y `HARVEST_CONTACT`), caché por URL y por hash, respeto a robots.txt por host.
- **En este repositorio no se descargó ninguna sentencia real.** El cosechador se prueba contra un servidor simulado y la demo usa sentencias ficticias.

## b) Versiones exactas (verificadas en hex.pm, GitHub y Docker Hub)

| Componente | Versión | Fuente |
|---|---|---|
| Elixir | 1.20.5 | #8 |
| Erlang/OTP | 29.1.2 | #8 |
| Phoenix | 1.8.16 | #7 |
| Phoenix LiveView | 1.2.13 (el documento base decía 1.1; 1.2 es la estable vigente) | #7, #10 |
| Broadway | 1.3.1 | #7 |
| Req | 0.7.5 | #7 |
| Bumblebee | 0.8.0 | #7 |
| Nx / EXLA | 1.0.0 / 1.0.0 | #7 |
| ecto_sqlite3 | 0.26.0 | #7 |
| Meilisearch | v1.56.2 (Community Edition, MIT) | #11, #12 |
| poppler-utils (`pdftotext`) | la del repositorio de Debian trixie | imagen base |

**Búsqueda híbrida en la edición MIT:** sí. Lo único exclusivo de Enterprise es sharding (#12).

## c) Modelos (sin Python, con Bumblebee)

| Uso | Modelo | Licencia | Notas |
|---|---|---|---|
| Embeddings | `intfloat/multilingual-e5-small` | MIT | BERT, 384 dim, prefijos `query:`/`passage:` (#14) |
| NER | `Davlan/bert-base-multilingual-cased-ner-hrl` | AFL-3.0 | PER/ORG/LOC/DATE, incluye español; tokenizador de `google-bert/bert-base-multilingual-cased` (#15) |

**Medición:** `mix lexec.ner_eval` corre el NER + reglas sobre 30 párrafos sintéticos anotados (`test/fixtures/ner_paragraphs.json`) e imprime precisión y recall por tipo. La prueba automática T-02 exige **cero cédulas** y un recall de personas ≥ `person_recall_min` definido en `priv/rules/anonymization.yaml` (0,90). Resultados de la última corrida en el README.

**Por qué las reglas van primero:** las cédulas, teléfonos y correos se detectan con expresiones regulares deterministas (recall 100 % en fixtures). El NER solo agrega nombres que las reglas no encontraron; si su confianza es baja, la sentencia va a la cola de revisión y **no se publica** hasta que una persona la apruebe.

## d) Alojamiento gratuito

| Opción | Veredicto |
|---|---|
| Render free | 512 MB de RAM y se duerme a los 15 min: no alcanza para Meilisearch + modelos (~1,2 GB). |
| Meilisearch Cloud | No admite embedders locales y no es gratuito de forma sostenible. |
| Oracle Always Free | Exige tarjeta. Descartado sin tu autorización. |
| **Local con Docker Compose + capturas** | **Elegida.** `docker compose up --build` levanta Phoenix + Meilisearch con la demo ficticia. |

## e) Resumen para el abogado

1. **Política POL-A-05 de la Corte (v1.0, 29-06-2026).** Exige protección reforzada para NNA, víctimas de violencia y datos sensibles (§7.2.2 b); prohíbe procesar con IA causas de violencia intrafamiliar y de menores (§7.2.9 c); prohíbe usar sentencias para fines particulares, comerciales o políticos (§7.3 f); admite la investigación académica con anonimización o seudonimización (§7.2.1 f).
2. **LOPDP (2021).** Minimización, finalidad, proporcionalidad, categorías especiales de datos. LEXEC: no guarda el dato original reemplazado, no tiene cuentas, la corrección no exige identificarse y el correo de contacto es opcional y con consentimiento.
3. **LOTAIP (2023).** Base para pedir el corpus en bloque (plazo a confirmar, S-2).
4. **Preguntas abiertas para el abogado:**
   - ¿El §7.3 f de la política alcanza a terceros que reutilizan sentencias **públicas** con fines académicos?
   - ¿Basta la exclusión por palabras clave y tipo de acción, o la Corte puede marcar las causas reservadas en el corpus entregado?
   - ¿Plazo razonable de respuesta para correcciones (hoy 15 días, configurable)?
   - ¿Textos de la interfaz ("no es asesoría legal", metodología) suficientes?

Ver además [legal.md](legal.md) y [metodologia.md](metodologia.md).
