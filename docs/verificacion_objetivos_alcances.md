# Verificación: Objetivos Específicos y Alcances vs. código real

Verificación punto por punto de la sección "Objetivos Específicos" y "Tabla 1.1.
Alcances del Proyecto" contra el estado actual del código (`lib/`, `functions/`,
`firestore.rules`). 23 de 30 claims coinciden exactamente; 6 tienen matices
importantes; 1 no existe como se describe.

## Resumen

| # | Claim | Veredicto |
|---|---|---|
| 1 | Jerarquía de 5 niveles (contenido→unidad→lección→actividad→tarea) | ✅ Confirmado |
| 2 | Exactamente 12 tipos de tarea | ✅ Confirmado |
| 3 | CRUD de contenidos | ✅ Confirmado |
| 4 | Fechas programadas + cierre automático | ✅ Confirmado |
| 5 | Gestor de imágenes por categorías | ✅ Confirmado |
| 6 | Seleccionar del repositorio o subir propias | ✅ Confirmado |
| 7 | Registro de 3 roles | ✅ Confirmado |
| 8 | Permisos por rol | ✅ Confirmado |
| 9 | Vinculación 1 padre : N hijos | ✅ Confirmado |
| 10 | Recuperación por OTP | ✅ Confirmado |
| 11 | Creación de grupos | ✅ Confirmado |
| 12 | Asignación de contenido a grupos | ✅ Confirmado |
| 13 | Desbloqueo secuencial automático | ✅ Confirmado |
| 14 | Estadísticas de grupo por unidad | ✅ Confirmado |
| 15 | Detalle por estudiante/actividad + feedback | ✅ Confirmado |
| 16 | Archivar grupo (condicionado a completar todo) | ⚠️ Archivar existe, pero **sin** esa condición |
| 17 | Formativa+sumativa, mismo formulario | ✅ Confirmado |
| 18 | Docente decide CUÁNDO habilitar cada evaluación | ⚠️ No hay paso de "habilitar"; disponible al crearse |
| 19 | Resultados de quiz alimentan XP y reportes | ✅ Confirmado |
| 20 | XP por actividades y evaluaciones | ✅ Confirmado |
| 21 | XP acumulado por grupo, preservado al archivar | ❌ XP es global por estudiante, no por grupo |
| 22 | Ligas por rango de XP, ascenso automático | ✅ Confirmado |
| 23 | Recompensas reales configurables por periodo | ✅ Confirmado |
| 24 | Estudiante ve liga/puntos/progreso | ✅ Confirmado |
| 25 | Reporte generado al finalizar unidad | ⚠️ Lo genera el docente, no es automático |
| 26 | Contenido del reporte + comparación con unidades previas | ✅ Confirmado |
| 27 | Reportes visibles por docente y padre | ✅ Confirmado |
| 28 | Exportación a PDF | ✅ Confirmado |
| 29 | Notificación al padre cuando el reporte está listo | ⚠️ La dispara el docente, no es automática |
| 30 | Notificación al padre por actividad nueva | ✅ Confirmado (100% automático) |

## Detalle de los puntos con matices

### 16. Archivar grupo
`archived` existe como campo booleano y está completamente implementado
(`lib/screens/teacher/widgets/group_card.dart`, `archived_groups_screen.dart`),
pero es un **toggle manual que el docente puede usar en cualquier momento** —
no hay ninguna verificación en el código que exija que todo el contenido esté
completo o que no haya actividades pendientes antes de permitir archivar.

**Sugerencia de redacción:** "Permitir archivar un grupo de forma manual,
conservándolo como registro histórico consultable por el docente" (quitar la
condición de "una vez concluido todo su contenido").

### 18. Habilitación de evaluaciones por el docente
No existe un campo `enabled`/`published`/`active` en los documentos de quiz.
Un quiz queda disponible para los estudiantes tan pronto el docente lo crea
(sujeto solo al desbloqueo secuencial de lección/unidad, no a un paso de
activación aparte). Lo único que el docente controla es la regla de que un
Quiz de Unidad no puede *crearse* hasta que existan al menos 3 Quizzes de
Lección.

**Sugerencia de redacción:** "Permitir al docente decidir el momento de
crear cada evaluación según el avance del grupo" (en vez de "habilitar").

### 21. XP por grupo
Ambos puntos donde se otorga XP (`saveActivityCompletion`,
`saveQuizCompletion` en `database.dart`) escriben directamente sobre el campo
plano `students/{id}.xp` — sin `groupId` alguno. El XP es un contador único
y global por estudiante, no está particionado por grupo. Por lo tanto la idea
de "preservarlo en el historial del grupo al archivarlo" tampoco aplica,
porque el XP nunca estuvo ligado a un grupo específico.

**Sugerencia de redacción:** "Acumular XP global del estudiante al completar
actividades y evaluaciones del sistema" (quitar "dentro de su grupo" y la
cláusula de preservación al archivar).

### 25 y 29. Generación de reporte y notificación al finalizar unidad
El reporte vive en `students/{id}/reports/{unitId}` (sí está por unidad), pero
**no se genera automáticamente** cuando el estudiante termina — se genera
cuando el docente revisa el Quiz de Unidad y presiona "Send Report to Parent"
(`unit_quiz_review_screen.dart`), lo cual también exige que el docente escriba
retroalimentación antes de poder enviarlo. La notificación push
("New Report Available") se dispara en ese mismo momento, no automáticamente
al completar la unidad.

**Sugerencia de redacción:** "Generar reportes por unidad temática una vez
que el docente revisa el desempeño del estudiante y agrega retroalimentación"
+ "Notificar al padre cuando el docente envía el reporte de desempeño."

## Puntos confirmados sin matices (evidencia rápida)

- **Tipos de tarea (12):** `lib/screens/teacher/widgets/task_type_option.dart`
  — coincide 1:1 con la lista de la tesis.
- **Cierre automático:** `database.dart` calcula `isClosed` comparando
  `closeDate` con `now()` y bloquea el envío — no es solo un campo decorativo.
- **Desbloqueo secuencial:** `requiredActivityId` se deriva automáticamente
  (el docente nunca lo define) y se verifica contra `completedActivities`.
- **OTP:** flujo propio vía Cloud Functions (`otp_service.dart` +
  `functions/src/resetPassword.ts`), no el link estándar de Firebase Auth.
- **Recompensas de liga:** `leagueCampaigns` en Firestore, configurable por
  docente con `startDate`/`endDate` y texto libre por tier — funcionalidad
  real, no aspiracional.
- **Notificación de actividad nueva:** `functions/src/activityCreatedNotifications.ts`
  usa un trigger `onDocumentCreated` — esta sí es 100% automática, a
  diferencia de la del reporte (#29).
- **PDF:** paquetes `pdf`/`printing` en `pubspec.yaml`,
  `lib/utils/unit_report_pdf.dart` implementa la exportación real,
  compartida entre pantalla de docente y de padre.

---
*Elaborado a partir de una revisión exhaustiva del código fuente,
2026-08-18.*
