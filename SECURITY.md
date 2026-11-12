# Política de seguridad

## Reportar una vulnerabilidad
No abras un issue público. Escríbeme por GitHub (perfil DiegoFranciscoG) con los pasos para reproducir el problema. Respondo en un máximo de 7 días.

## Reportar un dato personal publicado
Si un párrafo permite identificar a una persona, usa la página **Corrección y retiro** del sitio. No necesitas identificarte; el plazo de respuesta es de 15 días.

## Prácticas aplicadas en este proyecto
- Secretos solo por variables de entorno, sin valores por defecto: la release no arranca si falta `SECRET_KEY_BASE`, `ADMIN_PASSWORD`, `PHX_HOST` o la clave de Meilisearch (`.env` no se versiona; ver `.env.example`).
- Escaneo de secretos con gitleaks en cada push y pull request; acciones de GitHub fijadas por SHA y permisos mínimos.
- CSP estricta (`default-src 'self'`, sin `unsafe-inline`), `frame-ancestors 'none'`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy`; sin scripts, fuentes ni rastreadores de terceros.
- Área de revisión con HTTP Basic sobre variables de entorno, comparación en tiempo constante y límite de intentos.
- Límite de peticiones por IP (páginas, búsquedas, correcciones); la IP se usa en memoria y no se guarda.
- Validación y lista blanca de todos los parámetros de búsqueda; SQL solo parametrizado (Ecto); filtros de Meilisearch escapados.
- Errores sin trazas ni detalles internos; `/health` no expone información.
- Minimización (LOPDP): no se guarda el dato original anonimizado, ni el PDF descargado, ni las búsquedas; el correo de contacto opcional se borra al cerrar la solicitud.
- El modo de respuesta con modelo de lenguaje trata los párrafos como datos no confiables y un verificador elimina toda oración sin cita textual (OWASP LLM01 y LLM09).
- Docker multi-stage con imágenes de versión fija, usuario no root y healthcheck.
