# Plan por días

| Día | Entregable | Pruebas |
|---|---|---|
| D1 | `docs/investigacion.md`, `docs/verificacion.md`, `docs/modelo-datos.md`, `docs/solicitud-lotaip.md`, este plan | — |
| D2 | Esqueleto Phoenix 1.8, migraciones, esquemas Ecto, reglas en `priv/rules/*.yaml`, extracción y segmentación | T-04 |
| D3 | Exclusión, anonimización (reglas + NER), relaciones, ingesta, cosecha con Broadway, índice, respuestas con verificador, retiro | T-01, T-02, T-03, T-05, T-06, T-07, T-08, T-10, T-11 |
| D4 | LiveView: búsqueda, ficha, red de precedentes, metodología, corrección y revisión | T-09, T-12 |
| D5 | Seguridad (CSP, rate limiting, basic auth de revisión), Dockerfile multi-stage, Compose, CI | gitleaks, cobertura ≥ 70 % |
| D6 | Demo local con corpus ficticio, capturas | evaluación de búsqueda |
| D7 | README final, `docs/metodologia.md`, `docs/legal.md`, pulido | todo en verde |

Alcance inicial (recomendado por el documento base): un solo tipo de acción (EP) y un rango de años. La demo usa sentencias ficticias.
