# Loringo — Documentación Técnica del Proyecto

> Documento de referencia para entender la arquitectura y el funcionamiento de
> Loringo sin tener que revisar archivo por archivo. Organizado según los 6
> módulos funcionales del proyecto de tesis. Pensado tanto para uso propio
> como desarrollador, como para servir de base descriptiva en la tesis.
>
> Este documento describe el **estado actual del código**, no decisiones de
> diseño hipotéticas — cada afirmación está respaldada por archivos concretos
> del repositorio, citados entre paréntesis.

## Índice

1. [Resumen general](#1-resumen-general)
2. [Arquitectura y patrones generales](#2-arquitectura-y-patrones-generales)
3. [Módulo 1 — Gestión de contenidos y recursos educativos](#3-módulo-1--gestión-de-contenidos-y-recursos-educativos)
4. [Módulo 2 — Gestión de usuarios](#4-módulo-2--gestión-de-usuarios)
5. [Módulo 3 — Grupos y avance del aprendizaje](#5-módulo-3--grupos-y-avance-del-aprendizaje)
6. [Módulo 4 — Evaluación](#6-módulo-4--evaluación)
7. [Módulo 5 — Gamificación](#7-módulo-5--gamificación)
8. [Módulo 6 — Reportes](#8-módulo-6--reportes)
9. [Pila tecnológica (resumen)](#9-pila-tecnológica-resumen)
10. [Cómo mantener este documento](#10-cómo-mantener-este-documento)

---

## 1. Resumen general

Loringo es una aplicación educativa Flutter/Firebase orientada a la
enseñanza de lectura e idioma a niños, con **cuatro roles**: `admin`,
`teacher` (docente), `parent` (padre/madre) y `student` (estudiante). Los
docentes crean contenido educativo (unidades → lecciones → actividades →
tareas) y lo asignan a grupos de estudiantes; los estudiantes completan ese
contenido y evaluaciones; los padres monitorean el progreso de sus hijos y
reciben notificaciones y reportes.

El contenido educativo sigue una jerarquía fija en Firestore, base de casi
todos los módulos descritos más adelante:

```
content/{contentId}
  └── units/{unitId}                     (unidad temática)
        └── lessons/{lessonId}           (lección dentro de la unidad)
              └── activities/{activityId} (actividad de práctica)
                    └── tasks/{taskId}    (ejercicio atómico, con un `type`)
```

- `content` = curso/materia.
- `units` = unidad temática (el nivel que cierra con una evaluación sumativa).
- `lessons` = lección dentro de una unidad (puede cerrar con una evaluación
  formativa opcional).
- `activities` = actividad de práctica dentro de una lección.
- `tasks` = el ejercicio atómico dentro de una actividad — cada uno tiene un
  campo `type` que determina qué widget de Flutter lo reproduce (lectura,
  repetición, arrastrar-y-soltar, etc. — ver Módulo 1).

## 2. Arquitectura y patrones generales

- **Frontend**: Flutter/Dart. Gestión de estado con `provider` **solo** para
  estado verdaderamente global (estado biométrico, contador de
  notificaciones — `lib/providers/`, registrado en `lib/main.dart`). El
  estado de cada pantalla es `StatefulWidget` + `setState`; no hay
  Bloc/Riverpod/GetX en el proyecto.
- **Backend**: Firebase — Firestore (base de datos), Firebase Auth (cuentas
  de docente/padre/admin — los estudiantes **no** usan Firebase Auth, ver
  Módulo 2), Cloud Functions en TypeScript (`functions/src/`).
- **Capa única de acceso a datos**: la clase `Database`
  (`lib/services/database/database.dart`) centraliza casi todas las
  lecturas/escrituras a Firestore. Las pantallas llaman métodos de
  `Database` (`get*`, `get*Stream`, `save*`, `create*`, `update*`,
  `delete*`) en vez de usar `FirebaseFirestore.instance` directamente. La
  única excepción documentada es un servicio de una sola responsabilidad
  (`content_assignment_guard.dart`) que consulta Firestore directamente
  para una única regla bien definida.
- **Multimedia**: Cloudinary (no Firebase Storage) — usado tanto para el
  repositorio de imágenes (Módulo 1) como para el audio sintetizado de
  texto-a-voz.
- **Notificaciones push**: OneSignal, disparadas desde Cloud Functions
  (nunca desde el cliente directamente).
- **Organización por rol**: las pantallas están particionadas por rol bajo
  `lib/screens/{initials,teacher,parent,student,admin}/`, no por
  funcionalidad — una funcionalidad que toca varios roles (p. ej. cuestionarios)
  tiene pantallas separadas en cada carpeta de rol relevante.
- **Cloud Functions**: en su mayoría `onCall` (invocadas por el cliente) y
  `onSchedule` (cron); recientemente se añadieron también algunas
  `onDocumentWritten`/`onDocumentCreated` puntuales para notificaciones en
  tiempo real y para el caché de audio TTS.

---

## 3. Módulo 1 — Gestión de contenidos y recursos educativos

> *"Desarrollar el módulo de gestión de contenidos y recursos educativos
> que permita a los docentes crear y personalizar contenidos, y al gestor
> de imágenes administrar un repositorio de imágenes organizado por
> categorías para su reutilización."*

### 3.1 Jerarquía y autoría de contenido

El docente crea contenido navegando la jerarquía descrita en la sección 1,
a través de un conjunto de pantallas editoras en `lib/screens/teacher/`:
`teacher_content_editor_screen.dart`, `teacher_unit_editor_screen.dart`,
`teacher_lesson_editor_screen.dart`, `teacher_activity_editor_screen.dart`,
`teacher_task_editor_screen.dart` (además de `create_activity_screen.dart`,
`create_lesson_screen.dart`, `create_unit_screen.dart`, `create_task_screen.dart`
para la creación inicial). Cada nivel se persiste como un documento/subcolección
en la ruta de Firestore ya descrita.

### 3.2 Tipos de tarea (el ejercicio atómico)

Cada tarea (`task`) tiene un `type` que determina qué pantalla de
edición (`lib/screens/teacher/task_types/*.dart`) y qué pantalla de
reproducción del lado del estudiante se usa. Actualmente existen:

| `type` | Descripción |
|---|---|
| `reading` | Lectura de un pasaje (una o varias páginas), con narración TTS y preguntas de comprensión al final. |
| `repeat_after_me` | El estudiante escucha una frase y la repite (grabación/reconocimiento de voz). |
| `listen_and_speak` | Escuchar una frase y responder hablando. |
| `sound_match` | Emparejar un sonido con una imagen o palabra. |
| `match` | Emparejamiento de pares (p. ej. palabra ↔ traducción). |
| `complete_the_chat` | Completar un diálogo/chat con la opción correcta. |
| `sentence_builder` | Armar una oración a partir de bloques de palabras. |
| `arrange` | Ordenar elementos (palabras) en la secuencia correcta. |
| `fill_blank` | Completar espacios en blanco dentro de un texto. |
| `image_select` | Elegir la imagen correcta dada una palabra/audio. |
| `image_select_reverse` | Elegir la palabra/etiqueta correcta dada una imagen. |
| `odd_one_out` | Identificar el elemento que no pertenece al grupo. |
| `slow_reveal` | Revelado progresivo de una imagen/pista (actualmente inactivo/comentado en el código). |

Cada editor implementa una interfaz común (`task_type_editor.dart`) y
expone un método `collectData()` que define exactamente qué campos guarda
ese tipo de tarea — esto es lo que después consumen tanto el reproductor
del estudiante como (para los tipos con audio) el módulo de
pre-generación de voz.

### 3.3 Asignación de contenido a grupos

Un contenido (`content/{id}`) se asigna a uno o varios grupos mediante un
campo `assignedTo` (arreglo de `groupId`). La regla de negocio clave —
implementada en `lib/services/content/content_assignment_guard.dart` — es
que **una vez que algún estudiante de un grupo tiene progreso registrado
contra ese contenido, el contenido ya no puede desasignarse de ese grupo**.
Es una decisión de producto deliberada (documentada en el propio archivo):
evita que un docente "oculte" contenido que un estudiante ya cursó a
mitad de camino. Un grupo mal asignado solo puede corregirse manualmente
por soporte, no desde la app.

### 3.4 Repositorio de imágenes (gestor de imágenes)

Implementado en `lib/utils/image_service.dart`, con las pantallas
`lib/screens/admin/admin_upload_image_screen.dart` y
`admin_view_images_screen.dart`.

**Flujo de subida** (`uploadToCloudinary`):
1. **Capa 1 — filtro de nombre de archivo**: bloqueo rápido por lista de
   términos prohibidos en el nombre (`checkImageNameForBlockedTerms`), sin
   costo de red.
2. **Capa 2 — moderación real de contenido**: la imagen se envía (en
   base64) a la Cloud Function `moderateImage`, que usa Google Cloud
   Vision (SafeSearch) del lado del servidor — la API key nunca llega al
   cliente. Solo el nivel `VERY_LIKELY` bloquea la subida (un umbral más
   bajo sería demasiado agresivo para ilustraciones/dibujos animados,
   que es el tipo de contenido normal de Loringo).
3. Si pasa ambas capas, se sube a Cloudinary.

**Organización por categorías** (para su reutilización): la carpeta de
destino se decide en `getUploadFolder()` según el rol del usuario —
`imagesPredefined` para administradores (imágenes de uso general,
reutilizables por cualquier docente) o `teacherUploads/{uid}` para
docentes (imágenes propias de ese docente). Un parámetro opcional
`categoryName` añade una subcarpeta (`{carpetaBase}/{categoría}`),
permitiendo organizar el repositorio por categoría temática dentro de
cada ámbito.

**Eliminación**: enrutada por una Cloud Function dedicada
(`deleteCloudinaryImage`) en vez de llamarse directamente desde el
cliente — evita problemas de CORS con el endpoint administrativo de
Cloudinary y evita exponer el API secret en el bundle compilado.

---

## 4. Módulo 2 — Gestión de usuarios

> *"Desarrollar el módulo de gestión de usuarios para administrar la
> autenticación, el registro y la asignación de roles."*

### 4.1 Cuatro roles, dos mecanismos de autenticación

- **Docente, padre/madre y administrador** se autentican con **Firebase
  Auth** (correo/contraseña), creado vía
  `FirebaseAuth.createUserWithEmailAndPassword` en
  `lib/screens/initials/register_screen.dart` (el rol se elige en el
  formulario de registro; el rol `admin` es un flag especial, no
  auto-seleccionable por el usuario).
- **El estudiante no tiene cuenta de Firebase Auth en absoluto.** Inicia
  sesión con un **código de acceso de 6 caracteres** (alfabeto que excluye
  `O`/`0`/`I`/`1` para evitar ambigüedad visual), y la sesión se guarda
  únicamente en `SharedPreferences` en el dispositivo
  (`lib/services/auth/student_auth_service.dart`: `student_id`,
  `student_name`, `student_avatar`, `access_code`). Esta es la razón por
  la que varias Cloud Functions usadas por estudiantes (como la síntesis
  de voz) **no** exigen `request.auth` — un estudiante nunca tiene ese
  contexto.

### 4.2 Enrutamiento post-login por rol

`lib/services/auth/auth_gate.dart` decide qué pantalla mostrar:

1. Primero comprueba si hay una **sesión de estudiante activa**
   (`StudentAuthService.isLoggedIn()`) — debe revisarse *antes* que el
   estado de Firebase Auth, ya que una sesión de estudiante no deja rastro
   en Firebase. Si existe, va directo a `StudentMainScreen`.
2. Si no, escucha `FirebaseAuth.authStateChanges()` y, con un usuario
   autenticado, lee el campo `role` del documento `users/{uid}` en
   Firestore, y enruta: `admin` → `AdminNavigationScreen`, `teacher` →
   `TeacherHomeScreen`, `parent` → un enrutador intermedio que revisa si
   ese padre ya tiene hijos registrados (`students` donde
   `parentId == uid`) para decidir entre la pantalla de "registrar primer
   hijo" o el panel normal del padre.

### 4.3 Registro

- **Docente/padre**: auto-registro mediante `LoginOrRegister` →
  `RegisterScreen`, eligiendo su rol en el formulario.
- **Estudiante**: no existe auto-registro. Es el **padre/madre** quien
  crea al estudiante (`parent_register_child_screen.dart`), generando el
  código de acceso y el documento `students/{id}`. Existe un límite
  estricto de **8 hijos por cuenta de padre**.

### 4.4 Seguridad adicional

- **Login biométrico** (`lib/services/auth/biometric_service.dart`):
  envuelve el paquete `local_auth`. Es una re-autenticación a nivel de
  dispositivo (huella/rostro), opcional por usuario, con la preferencia
  guardada localmente (`SharedPreferences`) — no reemplaza la credencial
  real, solo evita reescribirla cada vez.
- **Recuperación de contraseña (OTP)**: flujo cliente
  (`otp_service.dart` + `password_service.dart`) respaldado por la Cloud
  Function `resetPassword` (`functions/src/resetPassword.ts`). Primero se
  verifica un código OTP (se marca `used: true` en Firestore); la función
  vuelve a validar que exista ese OTP ya usado antes de cambiar la
  contraseña con el Admin SDK — el usuario nunca necesita una sesión
  iniciada durante este proceso.

---

## 5. Módulo 3 — Grupos y avance del aprendizaje

> *"Desarrollar el módulo de grupos y avance del aprendizaje para
> gestionar grupos de estudiantes y realizar el seguimiento del
> progreso."*

### 5.1 Modelo de grupos

Cada grupo del docente vive en `teacherGroups/{groupId}`
(`groupCode`, `teacherId`, `name`, `archived`). La pertenencia de un
estudiante a un grupo se registra **dos veces** (deben mantenerse
sincronizadas conceptualmente, pero se usan para propósitos distintos):

- `students/{studentId}.groupId` — fuente de verdad para consultas de
  progreso/asignación de contenido.
- `teacherGroups/{groupId}/students/{studentId}` — subcolección tipo
  "roster", usada por la UI de gestión de miembros del grupo (invitar,
  remover).

### 5.2 Cómo se une un estudiante a un grupo

El único mecanismo es el **código de grupo**. El padre/madre lo ingresa en
`parent_join_group_screen.dart`, que busca `teacherGroups` por
`groupCode`, rechaza si el grupo está archivado, y actualiza ambas
representaciones descritas arriba. Del lado del docente,
`invite_student_modal.dart` solo **muestra/copia** el código del grupo —
no envía invitaciones activas; la unión siempre la inicia el padre con el
código.

### 5.3 Seguimiento de progreso

El progreso vive en `students/{studentId}/progress/{progressId}`, con
historial detallado por intento en una subcolección `attempts`. Un
documento de progreso de actividad (`Database.saveActivityCompletion`)
incluye: `type: 'activity'`, `contentId`, `unitId`, `isCompleted`,
`firstCompletedAt`, `lastCompletedAt`, `totalAttempts`, `bestScore`,
`stars`, `xpEarned` y `taskAnswers` (detalle de respuesta por tarea,
usado en la vista de revisión del docente). Existe un método análogo
`saveQuizCompletion` para cuestionarios (ver Módulo 4).

### 5.4 Cadena de desbloqueo (unlock chain)

Implementada en `student_activities_screen.dart`
(`_loadAssignedContent`), es la lógica que decide qué puede hacer un
estudiante en cada momento:

1. **Unidades**: se desbloquean secuencialmente — la unidad *N+1* requiere
   que la unidad *N* esté completamente terminada (todas sus actividades
   **y**, si tiene, su Evaluación Sumativa/Unit Quiz aprobada).
2. **Lecciones dentro de una unidad**: también secuenciales — la lección
   *N+1* requiere que **todas las actividades** de la lección *N* estén
   completas. La Evaluación Formativa/Lesson Quiz de una lección
   **no** forma parte de este candado — es intencionalmente opcional y no
   bloqueante.
3. **Actividades**: además de pertenecer a una lección/unidad ya
   desbloqueada, una actividad requiere que su `scheduledDate` (si existe)
   ya haya llegado, que no esté cerrada por `closeDate` (corte estilo
   Canvas/Teams), y — si declara un `requiredActivityId` — que esa
   actividad previa específica ya esté completada. `dueDate` es solo
   informativo (marca "atrasada"), nunca bloquea.

### 5.5 Panel del docente

`lib/models/teacher/student_progress.dart` es **el único modelo de datos
tipado de toda la aplicación** (el resto del código usa
`Map<String, dynamic>` directamente contra Firestore). Define
`StudentStats`, que expone, por estudiante: actividades
completadas/totales y su puntaje promedio, cuestionarios formativos
completados/totales y su promedio, el puntaje del cuestionario sumativo,
y un `overallScore` ponderado — **40 % actividades + 30 % evaluaciones
formativas + 30 % evaluación sumativa** — junto a sus estrellas
correspondientes. `SummaryStats` agrega estos datos a nivel de grupo.
Consumido por `student_progress_dashboard.dart` (vista de grupo) y
`student_detail_progress_screen.dart` (vista individual).

---

## 6. Módulo 4 — Evaluación

> *"Desarrollar el módulo de evaluación para gestionar evaluaciones
> formativas por lección y evaluaciones sumativas por unidad temática,
> registrando el desempeño del estudiante y proporcionando
> retroalimentación."*

### 6.1 Dos tipos de evaluación, una sola colección

Ambos tipos de evaluación viven en la colección `quizzes`, diferenciados
por un campo `scope`:

| | Evaluación Formativa (`scope: 'lesson'`) | Evaluación Sumativa (`scope: 'unit'`) |
|---|---|---|
| Alcance | Por lección | Por unidad temática |
| ¿Bloquea el avance? | No — siempre opcional | Sí — requerida para desbloquear la siguiente unidad |
| Intentos | Prácticamente ilimitados (99, sin calificación estricta) | Configurable por el docente, 1 a 5 |
| Puntaje mínimo (`passingScore`) | No aplica | Configurable por el docente |

### 6.2 Autoría de evaluaciones

`create_quiz_screen.dart` permite construir un cuestionario con preguntas
ordenadas y sus opciones (guardadas en una subcolección del documento del
quiz). Según el `scope` elegido, la pantalla oculta/fuerza distintos
campos: las evaluaciones formativas fijan `maxAttempts` en un valor alto y
ocultan el `passingScore`; las sumativas exponen ambos como configurables
por el docente.

### 6.3 Resolución y calificación

`lib/screens/initials/quiz_play_screen.dart` carga los intentos previos
del estudiante desde su documento de progreso para calcular los intentos
restantes, y bloquea un nuevo intento si ya se agotaron. Al enviar
(`_submitQuiz`), calcula las respuestas correctas y llama a
`Database.saveQuizCompletion`, que registra `correctAnswers`,
`wrongAnswers`, `stars` (mismos umbrales que las actividades — ver Módulo
5) y, para evaluaciones sumativas, si el cuestionario queda cerrado tras
agotar los intentos (`isClosedAfterAttempts`).

### 6.4 Retroalimentación

El docente revisa las respuestas de un estudiante en
`unit_quiz_review_screen.dart` (sumativas) o
`lesson_quiz_review_screen.dart` (formativas). Desde la revisión de una
evaluación sumativa, el botón **"Enviar reporte al padre/madre"**
dispara `Database.saveReportOnly` (ver Módulo 6) y luego la Cloud
Function `sendReportNotification`, que ubica al padre del estudiante,
registra el aviso y lo empuja por OneSignal — así la retroalimentación
del docente llega directamente al padre/madre.

### 6.5 Evaluación formativa embebida en lectura

Las tareas de tipo `reading` incluyen preguntas de comprensión al final
del pasaje, con un mecanismo de reintento local **por pregunta**
(`screen_seven.dart`, usando el mixin `RetryableTask`): una respuesta
incorrecta en el primer intento ofrece un reintento inmediato antes de
contar como error definitivo. Esto es una evaluación formativa adicional,
distinta de los cuestionarios de la colección `quizzes` — no genera un
registro de "quiz" independiente, solo afecta el resultado de esa tarea
de lectura.

---

## 7. Módulo 5 — Gamificación

> *"Desarrollar el módulo de gamificación para gestionar la acumulación
> de puntos de experiencia (XP) y el ascenso de ligas."*

### 7.1 Puntos de experiencia (XP)

Cada actividad tiene un `xpBase` (definido por el docente al crearla,
100 por defecto) y opcionalmente un `bonusXP`. La lógica de otorgamiento
(`Database.saveActivityCompletion`/`saveQuizCompletion`) distingue entre
**primer intento completado** y **reintentos**:

- **Primera vez que se completa**: `xpEarned = round(xpBase × puntaje/100) + bonusXP`.
- **Reintentos posteriores** (incluso con mejor puntaje): un valor plano
  de **5 XP** — el incentivo principal es completar contenido nuevo, no
  repetir lo ya hecho.

El XP se suma al documento del estudiante de forma atómica
(`FieldValue.increment`), y cada intento individual queda además
registrado en la subcolección `attempts` con su propio detalle,
independientemente del acumulado total.

### 7.2 Estrellas

El número de estrellas (1 a 3) que recibe una actividad o evaluación se
calcula únicamente por umbral de puntaje, con la misma regla en ambos
flujos:

- `puntaje ≥ 90 %` → 3 estrellas
- `puntaje ≥ 70 %` → 2 estrellas
- cualquier otro caso → 1 estrella

Las estrellas guardadas solo se actualizan cuando el nuevo intento
establece un **nuevo mejor puntaje** — un reintento con peor resultado no
las reduce.

### 7.3 Ligas

La fuente única de verdad son 6 niveles de liga fijos definidos en
`lib/models/league_tier.dart` (`kLeagueTiers`), cada uno con un rango de
XP, un color y una insignia (`assets/leagues/*.png`):

| Liga | Rango de XP | Recompensa disponible |
|---|---|---|
| Starter | 0 – 199 | No (`rewardLocked`) |
| Bronze | 200 – 499 | Sí |
| Silver | 500 – 999 | Sí |
| Gold | 1000 – 1999 | Sí |
| Platinum | 2000 – 3999 | Sí |
| Diamond | 4000+ | Sí |

**La liga actual de un estudiante no se almacena** — se **deriva** en
cada render llamando a `tierForXp(xp)` sobre el XP acumulado del
estudiante (leído en vivo desde `students/{id}.xp`). El ascenso de liga
es, por lo tanto, automático e inmediato en cuanto el XP cruza el
umbral, sin ningún proceso batch ni disparador manual.

Sobre esta base existe una capa opcional de **recompensas/competencia**:
el docente puede crear una `leagueCampaign` (con alcance a todo el
grupo o a un grupo específico, y un rango de fechas). Dentro de una
campaña, los estudiantes se agrupan por su liga actual y se ordenan por
XP para determinar el ranking — la liga Starter queda siempre excluida
de recompensas.

### 7.4 Campo `streak` (histórico, ya no vigente)

El documento del estudiante conserva un campo `streak` (inicializado en
0) de una etapa temprana del desarrollo, cuando sí se contempló una
mecánica de racha. **No forma parte del diseño actual**: ningún flujo del
código lo lee ni lo incrementa hoy. La consistencia del estudiante no se
deriva de un contador de racha calculado por la app, sino que depende de
la cadencia de asignación/entrega definida por el docente (fechas
`scheduledDate`/`dueDate`/`closeDate` por actividad — ver Módulo 3). No
lo describas como funcionalidad activa ni como mecánica de gamificación
vigente en la tesis; es campo heredado sin uso, no una feature planificada.

---

## 8. Módulo 6 — Reportes

> *"Desarrollar el módulo de reportes para generar y visualizar
> información el desempeño del estudiante."*

### 8.1 Generación del reporte

`Database.saveReportOnly` es el algoritmo central: al revisar una
evaluación sumativa, agrega información de **varias colecciones** para
construir un solo documento de reporte:

1. Ubica el `contentId` dueño de la unidad (recorriendo la subcolección
   `units` de cada contenido).
2. Cuenta el total de actividades de esa unidad.
3. Cuenta las evaluaciones formativas (`quizzes` con `scope: 'lesson'`)
   de esa unidad.
4. Recorre todo el progreso del estudiante (`studentProgress`),
   filtrando por esa unidad, para calcular actividades y evaluaciones
   formativas efectivamente completadas.
5. Escribe un único documento combinado en
   `students/{id}/reports/{unitId}` con: resultado del cuestionario
   sumativo (correctas/incorrectas/porcentaje), porcentaje de actividades
   completadas, conteo de evaluaciones formativas completadas, historial
   de puntajes de unidades anteriores, estrellas, retroalimentación
   escrita del docente y fecha de generación.

### 8.2 Visualización para el docente

`report_preview_screen.dart` muestra el reporte (nombre del estudiante,
unidad, porcentaje del cuestionario, proporción de actividades
completadas, retroalimentación) y permite **exportarlo a PDF**
(`lib/utils/unit_report_pdf.dart`, paquetes `pdf`/`printing`). El
proyecto **no** usa ninguna librería de gráficos (no hay `fl_chart`,
`charts_flutter` ni similar) — las visualizaciones son widgets planos de
Flutter (insignias de puntaje, barras/filas de progreso) más el PDF
exportable.

### 8.3 Entrega al padre/madre

Tras generarse el reporte, la Cloud Function `sendReportNotification`
ubica al padre del estudiante, registra un aviso de tipo `quiz_report` y
lo empuja por OneSignal. Si el envío de la notificación push falla, el
reporte **igual queda disponible** para el padre dentro de la app — el
fallo del push nunca bloquea la generación/visualización del reporte.

### 8.4 Visualización para el padre/madre

`child_report_detail_screen.dart` muestra cada documento de
`students/{id}/reports/*` como una tarjeta: unidad, resultado del
cuestionario, proporción de actividades, historial de unidades
anteriores, retroalimentación del docente y fecha — con la misma opción
de exportar a PDF disponible del lado del docente.

---

## 9. Pila tecnológica (resumen)

| Área | Tecnología |
|---|---|
| Frontend | Flutter/Dart |
| Gestión de estado | `provider` (solo estado global) + `setState` (estado local) |
| Base de datos | Cloud Firestore |
| Autenticación | Firebase Auth (docente/padre/admin) + código de acceso local (estudiante) |
| Backend serverless | Firebase Cloud Functions (TypeScript) |
| Multimedia (imágenes y audio) | Cloudinary |
| Notificaciones push | OneSignal |
| Texto a voz | Google Cloud Text-to-Speech (síntesis server-side, cacheada) |
| Reconocimiento/síntesis de voz en tareas | `flutter_tts`, `speech_to_text`, `just_audio` |
| Moderación de imágenes | Google Cloud Vision (SafeSearch) |
| Envío de correo | Resend (desde Cloud Functions) |
| Exportación de reportes | `pdf` / `printing` |

## 10. Cómo mantener este documento

Este archivo describe el sistema tal como está implementado hoy. Si en el
futuro cambian reglas de negocio importantes (fórmula de XP, umbrales de
estrellas, la cadena de desbloqueo, la estructura de `quizzes`, etc.),
actualiza la sección correspondiente — de lo contrario este documento
quedará desactualizado igual que cualquier otra documentación que no se
mantiene junto al código. Para patrones de *código* (no de producto) —
cómo se estructura el acceso a datos, el manejo de roles, las Cloud
Functions — ver también `.claude/docs/architectural_patterns.md`, que es
más detallado a nivel de convenciones de implementación.
