# Revisión legal (para abogado)

> Documento de trabajo. No es asesoría legal. Debe revisarlo un profesional antes de publicar el sitio; la Facultad de Jurisprudencia de la Universidad de Cuenca es un aliado natural.

## 1. Marco aplicable

| Norma | Puntos que afectan a LEXEC |
|---|---|
| Política de Protección de Datos Personales de la Corte Constitucional (POL-A-05, v1.0, 29-06-2026) | §7.2.2 b protección reforzada (NNA, víctimas, datos sensibles); §7.2.9 c prohibido procesar con IA causas de violencia intrafamiliar y de menores; §7.3 f prohibido usar sentencias con fines particulares, comerciales o políticos; §7.2.1 f investigación académica con anonimización |
| LOPDP (R.O. 459, 2021) | Minimización, finalidad, proporcionalidad; derechos de acceso, rectificación, eliminación y oposición |
| LOTAIP (R.O. 245, 2023) | Acceso al corpus en bloque |
| Constitución, art. 18 num. 2 y art. 66 num. 19 | Acceso a la información pública; protección de datos personales |

## 2. Cómo cumple LEXEC (diseño)

| Requisito | Implementación | Verificación |
|---|---|---|
| Excluir NNA y violencia antes de cualquier IA | `Lexec.Privacy.Exclusion` antes de NER y embeddings | T-01 |
| Anonimizar personas naturales | Reglas + NER + revisión humana | T-02, T-03 |
| No guardar el dato original | Solo conteos por tipo y versión de reglas | Esquema `anonymization_stats` |
| Sin fines comerciales ni políticos | Sin anuncios, cobro ni cuentas; aviso en cada página | T-09 |
| Canal de corrección y retiro con plazo | `/correccion`, 15 días (`app.yaml`) | T-11 |
| Minimizar datos de quien pide corrección | Correo opcional con consentimiento, borrado al cerrar | Pruebas de `Corrections` |
| Cookies | Solo `_lexec_key` (técnica, CSRF); aviso informativo | Prueba de cabeceras |

## 3. Preguntas abiertas

1. ¿La prohibición del §7.3 f de la política alcanza a terceros que reutilizan sentencias **públicas** con fines académicos y gratuitos?
2. ¿La exclusión por palabras clave es suficiente, o debe exigirse la lista de causas reservadas a la Corte?
3. ¿Es razonable el plazo de 15 días para correcciones y retiros?
4. ¿Los textos de "Aviso legal", "Privacidad" y "Cookies" (`/aviso-legal`) son adecuados? ¿Hace falta designar un responsable con datos de contacto públicos?
5. ¿Conviene un acuerdo o comunicación formal con la Corte antes de publicar?

## 4. Antes de publicar

- [ ] Respuesta de la Corte a la solicitud LOTAIP o confirmación de términos de uso del portal.
- [ ] Revisión de este documento y de los textos de la interfaz por un abogado.
- [ ] Repetir las métricas de anonimización con una muestra real revisada a mano.
- [ ] Publicar la página de metodología con la fecha de corte del corpus.
