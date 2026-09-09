# 6. Pruebas de Calidad — Loringo App

## Criterio de clasificación

- **Prueba Unitaria:** evalúa un componente en aislamiento — el
  comportamiento visual y los estilos de una pantalla (usando datos
  simulados/mocks, sin comunicación real con la base de datos) o una
  función de lógica pura sin dependencias externas. El `Assert` verifica
  **elementos de interfaz** (texto, color, presencia/ausencia de un
  widget) o un **valor de retorno puro**.
- **Prueba de Integración:** evalúa que una función o pantalla se
  comunique correctamente con la base de datos (real o simulada) y que la
  colección/documento devuelto tenga los datos exactos esperados. El
  `Assert` verifica **el estado de un documento o colección** en
  Firestore, o el resultado de una operación que atraviesa varias capas
  (interfaz + persistencia).

Cada prueba sigue el patrón **Arrange–Act–Assert (AAA)**, con comentarios
explícitos `// 1. ARRANGE`, `// 2. ACT`, `// 3. ASSERT` en el código real.
Todas se ejecutan sobre el código real de `lib/`, usando `flutter_test`
junto con `fake_cloud_firestore` y `firebase_auth_mocks`.

El proyecto cuenta con **25 archivos de prueba** y **119 casos** en total.
A continuación se presentan casos representativos por módulo, ya
separados según el criterio anterior.

---

## 6.1 Pruebas Unitarias

Solo componentes visuales evaluados con datos simulados, y funciones de
lógica pura sin comunicación con la base de datos.

### Módulo de Gestión de Usuarios — Frontend (UI con mocks)

Archivos: `test/login_validation_test.dart`, `test/registration_validation_test.dart`,
`test/role_routing_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Login con correo vacío | Se monta `LoginScreen` con `MockFirebaseAuth`, sin datos de entrada | Se presiona "Sign In" sin llenar los campos | `find.text('Email is required')` — **verifica texto en UI** | PASS |
| Login con credenciales válidas | `MockFirebaseAuth` sin usuario previo; `SharedPreferences` vacío | Se ingresan correo/contraseña válidos y se presiona "Sign In" | `find.byType(LoginScreen)` ya no existe en el árbol — **verifica navegación de UI** | PASS |
| Registro con contraseña débil | Se monta `RegisterScreen`; nombre y correo ya llenos | Se ingresa `'weak'` como contraseña y se envía | `find.textContaining('At least 8 characters')` — **verifica texto en UI** | PASS |
| Enrutamiento con rol inválido | Usuario simulado con `role: 'not_a_real_role'` en Firestore simulado | Se monta `AuthGate` | `find.textContaining('Invalid user role: ...')` — **verifica texto de error en UI** | PASS |

```dart
testWidgets('ARRANGE-ACT-ASSERT: submitting an empty email shows a validation snackbar',
    (tester) async {
  // 1. ARRANGE
  setUpMockedFirebase();
  await pumpApp(tester, LoginScreen(onTap: () {}));

  // 2. ACT
  await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
  await tester.pump();

  // 3. ASSERT
  expect(find.text('Email is required'), findsOneWidget);
});
```

### Módulo de Gestión de Usuarios — Lógica pura

Archivo: `test/utils/password_utils_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Contraseña válida | Se define la cadena `'TestQA#2024'` | `PasswordUtils.isPasswordValid(password)` | `isValid == true` — **verifica valor de retorno puro** | PASS |
| Requisitos faltantes | Se define la cadena `'password1'` (sin mayúscula ni símbolo) | `PasswordUtils.getPasswordRequirements(password)` | La lista contiene `'At least 1 uppercase letter (A-Z)'` y `'At least 1 special character...'` | PASS |

---

### Módulo de Contenidos y Recursos — Lógica pura

Archivo: `test/utils/image_service_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Moderación de nombre de imagen | Se define el nombre `'my_naked_photo.png'` | `ImageService().checkImageNameForBlockedTerms(fileName)` | `isBlocked == true` — **verifica valor de retorno puro**, sin Firestore | PASS |

> **Nota de alcance — servicios externos:** de los servicios de terceros
> (Google Vision, Google Cloud TTS, Cloudinary, OneSignal, Resend),
> **ninguno** tiene actualmente una función con lógica separable del canal
> de plataforma o de una Cloud Function. `TtsPhoneticService` (corrección
> fonética para lectura) existía como una posible excepción, pero
> pertenecía a la integración anterior basada en `flutter_tts` on-device y
> está deshabilitada en el código actual (clase completa comentada) tras
> el cambio a Google Cloud TTS server-side — no se documenta como prueba
> real por no corresponder a código activo. `ImageService.uploadToCloudinary`
> sí se ejecuta desde el cliente, pero mezcla `FirebaseAuth`/`FirebaseFirestore`
> (sin inyección), la Cloud Function de Vision, y variables de entorno
> (`dotenv`) en una sola función — probarla requeriría un refactor mayor,
> no realizado en esta suite.

> No hay pruebas de tipo Frontend puras en este módulo: las pantallas de
> creación de contenido (`create_content_screen.dart` y similares)
> construyen su conexión a Firestore dentro de `initState()` y no pueden
> montarse de forma aislada (ver §6.3). Toda su lógica de negocio se
> valida como prueba de integración (tabla siguiente).

---

### Módulo de Grupos y Avance — Frontend (validación de UI únicamente)

Archivos: `test/parent/parent_join_group_test.dart`, `test/parent/parent_register_child_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Código de grupo vacío | Se monta `ParentJoinGroupScreen` con Firebase simulado | Se presiona "Join Group" sin ingresar código | `find.text('Please enter the group code')` — **verifica texto en UI**, sin tocar Firestore | PASS |
| Nombre de hijo vacío | Se monta `ParentRegisterChildScreen` con un padre autenticado | Se presiona "Register Child" sin ingresar nombre | `find.text("Please enter your child's name")` — **verifica texto en UI**, sin tocar Firestore | PASS |

### Módulo de Reportes — Frontend (UI con mocks)

Archivo: `test/parent/child_report_detail_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Reporte con desempeño alto | Se construye un mapa de reporte simulado con `quizPercent: 90` (sin Firestore) | Se monta `ChildReportDetailScreen(child, reports: [report], formatDate)` | El texto `'90%'` se renderiza con color `#4CAF50` — **verifica estilo/color en UI** | PASS |
| Reporte con desempeño bajo | Mapa de reporte simulado con `quizPercent: 40` | Se monta `ChildReportDetailScreen` con dicho reporte | El texto `'40%'` se renderiza con color `#FF7043` — **verifica estilo/color en UI** | PASS |
| Lista de reportes vacía | Se construye una lista vacía de reportes | Se monta `ChildReportDetailScreen` con `reports: []` | `find.text('Quiz Score')` no se encuentra — **verifica ausencia de elemento en UI** | PASS |

```dart
testWidgets('ARRANGE-ACT-ASSERT: a report with quizPercent >= 80 renders its score in green',
    (tester) async {
  // 1. ARRANGE
  final report = buildReport(quizPercent: 90, quizCorrect: 9, quizTotal: 10, activitiesPercent: 100);

  // 2. ACT
  await pumpApp(tester, ChildReportDetailScreen(child: const {'names': 'Laura'}, reports: [report], formatDate: (d) => d.toString()));
  await tester.pumpAndSettle();

  // 3. ASSERT
  final scoreText = tester.widget<Text>(find.text('90%'));
  expect(scoreText.style?.color, const Color(0xFF4CAF50));
});
```

---

## 6.2 Pruebas de Integración

Funciones/pantallas que se comunican con la base de datos (simulada con
`fake_cloud_firestore`) y cuyo resultado se verifica sobre la colección o
documento devuelto — no sobre un elemento visual.

### Módulo de Gestión de Usuarios — Integración con base de datos

Archivo: `test/database/user_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Existencia de una cuenta `image_manager` | Se guarda directamente un documento en `users` con `role: 'image_manager'` en Firestore simulado | `Database.imageManagerExists()` | Retorna `true` — **verifica el resultado real de la consulta a Firestore** | PASS |

```dart
test('ARRANGE-ACT-ASSERT: returns true once an image_manager account exists', () async {
  // 1. ARRANGE
  await fakeDb.collection('users').doc('uid_1').set({'name': 'Someone', 'role': 'image_manager'});

  // 2. ACT
  final exists = await database.imageManagerExists();

  // 3. ASSERT
  expect(exists, true);
});
```

### Módulo de Contenidos y Recursos — Integración con base de datos

Archivos: `test/database/content_hierarchy_test.dart`, `test/database/activity_progress_test.dart`,
`test/database/child_activity_status_test.dart`, `test/database/category_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Cadena de prerrequisitos entre actividades | Se crean dos actividades encadenadas (`a1`, `a2`) con `createPersonalizedActivity` | `Database.deletePersonalizedActivity('g', 'c', 'u', 'l', 'a1')` | `a2.data()['requiredActivityId'] == null` — **verifica el documento resultante en Firestore** | PASS |

### Módulo de Grupos y Avance — Integración con base de datos

Archivos: `test/parent/parent_join_group_test.dart`, `test/parent/parent_register_child_test.dart`,
`test/services/content_assignment_guard_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Unión a un grupo con código válido | Se crea `teacherGroups/group_1` con `groupCode: 'ABC123'` y el estudiante `student_1` en Firestore simulado; se monta `ParentJoinGroupScreen` | Se ingresa `'ABC123'` y se presiona "Join Group" | `students/student_1.groupId == 'group_1'`; existe `teacherGroups/group_1/students/student_1` — **verifica los documentos resultantes**, no solo el mensaje en pantalla | PASS |

### Módulo de Evaluación — Integración con base de datos

Archivos: `test/database/quiz_test.dart`, `test/database/quiz_completion_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Bloqueo de Quiz de Unidad | Se crean 2 Quizzes de Lección para `unit_1` | `Database.createQuiz(scope: 'unit', ...)` | `throwsA(isA<Exception>())` — se requieren mínimo 3 Quizzes de Lección | PASS |

### Módulo de Gamificación — Integración con base de datos

Archivo: `test/database/league_campaign_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Campaña para todos los grupos | Datos de campaña ámbito `'all'` | `saveLeagueCampaign(...)` | `doc.data().containsKey('groupId') == false` | PASS |

### Módulo de Reportes — Integración con base de datos

Archivo: `test/database/student_progress_query_test.dart`.

| Caso | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|
| Progreso acumulado de dos actividades | Se siembran dos actividades completadas (`bestScore: 90` y `60`) | `Database.getStudentProgress('student_1')` | `snapshot.docs.length == 2`; los puntajes obtenidos son exactamente `{90, 60}` — **verifica que la colección devuelta coincide con los datos exactos sembrados** | PASS |

```dart
test('ARRANGE-ACT-ASSERT: getStudentProgress returns every progress doc for that student',
    () async {
  // 1. ARRANGE
  await seedActivityProgress(fakeDb, studentId: 'student_1', activityId: 'a1', bestScore: 90, stars: 3);
  await seedActivityProgress(fakeDb, studentId: 'student_1', activityId: 'a2', bestScore: 60, stars: 1);

  // 2. ACT
  final snapshot = await database.getStudentProgress('student_1');

  // 3. ASSERT
  expect(snapshot.docs.length, 2);
  final scores = snapshot.docs.map((d) => (d.data() as Map)['bestScore']).toSet();
  expect(scores, {90, 60});
});
```

### Flujos completos multi-pantalla (dispositivo físico)

Herramienta: paquete oficial **`integration_test`** del SDK de Flutter,
ejecutado con `flutter test integration_test/` sobre un **dispositivo
Android físico conectado** (Samsung SM-A566E, Android 16).

| Flujo | Módulos integrados | Arrange | Act | Assert | Resultado |
|---|---|---|---|---|---|
| Registro → enrutamiento → hijo → grupo | Gestión de Usuarios + Grupos y Avance | Firebase simulado; existe un grupo real con código `ABC123` | Se registra un padre real; `AuthGate` enruta según el rol; se registra un hijo; se une al grupo | Existe un usuario real con rol `parent`, un estudiante vinculado y su membresía en el grupo — **verifica documentos reales en Firestore simulado, producto de una secuencia de pantallas** | PASS |
| Cadena de creación de Quizzes | Evaluación | Firestore simulado sin Quizzes previos | Se crean tres Quizzes de Lección; se crea el Quiz de Unidad; se intenta un segundo Quiz de Unidad | Rechazado con 0/2 Quizzes de Lección; aceptado con 3; el duplicado es rechazado | PASS |
| Progreso del estudiante → reporte del padre | Contenidos y Recursos (actividades) + Reportes | Firestore simulado; existe un estudiante registrado | El estudiante completa dos actividades reales; se renderiza `ChildReportDetailScreen` con el reporte resultante | El progreso consultado coincide con las actividades reales; la UI del padre muestra el porcentaje correcto (100%, 2 de 2) | PASS |

**Resultado total:** 3 de 3 flujos exitosos, ejecutados sobre dispositivo
físico real.

---

## 6.3 Limitación de arquitectura encontrada y solución adoptada

Durante la elaboración de las pruebas se identificó que la mayoría de las
pantallas de creación de contenido y los contenedores de navegación
principales (`TeacherHomeScreen`, `ParentNavigationScreen`,
`AdminDashboardScreen`, y las pantallas `create_*_screen.dart`) construyen
su propia conexión a Firestore directamente dentro de `initState()`, sin
ningún punto de inyección de dependencias. Esto impide montarlas de forma
aislada como prueba unitaria de UI, ya que intentan conectarse a Firebase
antes de que la prueba pueda intervenir.

**Solución adoptada:** en esos casos se verificó el método real de la
clase `Database` que dicha pantalla invoca al guardar información — la
misma lógica de negocio, comprobada como prueba de integración con la
base de datos en lugar de como prueba unitaria de interfaz. Esta decisión
se documenta explícitamente en los comentarios de cada archivo de prueba
afectado.

---

## 6.4 Incidencias detectadas y corregidas al ejecutar las pruebas de integración

Al ejecutar por primera vez `flutter test integration_test` sobre un
dispositivo físico para recolectar evidencia, se encontraron y corrigieron
dos defectos reales en el arnés de pruebas de integración (no en la lógica
de negocio de `lib/`). Se documentan aquí porque forman parte del proceso
de aseguramiento de calidad: las pruebas cumplieron su propósito al
exponer una desincronización entre el helper de pruebas unitarias y el de
integración.

| # | Síntoma observado | Causa raíz | Corrección aplicada |
|---|---|---|---|
| 1 | `ProviderNotFoundException: Could not find the correct Provider<LocaleProvider>` al construir `RegisterScreen` y `ChildReportDetailScreen` | `integration_test/helpers/integration_pump.dart` no registraba `LocaleProvider` en su `MultiProvider`, a diferencia de `test/helpers/pump_app.dart` (pruebas unitarias), que sí lo tenía | Se agregó `ChangeNotifierProvider(create: (_) => LocaleProvider())` a la lista de `providers` en `pumpIntegrationApp` |
| 2 | Textos traducidos no se encontraban (`find.text('Parent')`, `find.text('Create Account')` devolvían 0 widgets) pese a que las claves existen en `assets/translations/en.json` | El mismo helper nunca envolvía el árbol de widgets en `EasyLocalization`, por lo que `.tr()` devolvía la clave cruda (`"common.parent"`) en vez del texto real | Se envolvió el árbol en `EasyLocalization` (mismos parámetros que `lib/main.dart`: `supportedLocales`, `path: 'assets/translations'`, `fallbackLocale: en`, más `startLocale: en` fijo para determinismo), y se agregó `await EasyLocalization.ensureInitialized()` antes del primer pump |

Ambos fallos eran defectos del **arnés de pruebas**, no de la aplicación:
las pantallas reales (`RegisterScreen`, `ChildReportDetailScreen`) siempre
funcionaron correctamente en producción, donde `lib/main.dart` sí registra
ambos providers.

### Verificación adicional de la regla de administrador único (`image_manager`)

Durante la misma sesión se confirmó, revisando el código real, que la
regla de negocio "solo puede existir un `image_manager`, y no es un rol
seleccionable desde el registro" está completamente implementada en
`lib/screens/initials/register_screen.dart`:

- El selector de rol del formulario de registro solo ofrece **Teacher** y
  **Parent** — `image_manager` nunca aparece como opción seleccionable.
- El rol `image_manager` únicamente se asigna si el nombre ingresado es
  literalmente `admin` o `administrador` (comparación insensible a
  mayúsculas), ignorando el selector de rol en ese caso.
- Antes de crear la cuenta en Firebase Auth se consulta
  `Database.imageManagerExists()`; si ya existe una, el registro se
  bloquea con un error y no se llega a crear una segunda cuenta.
- La cuenta `image_manager` sigue autenticándose de forma real contra
  Firebase Auth (no es solo un documento de Firestore sin autenticar).

Esta regla ya está cubierta por la prueba de integración
`integration_test/auth_routing_test.dart`, grupo *"Regla de administrador
único (image_manager)"*, que registra un primer `image_manager`, intenta
un segundo, y verifica en Firestore que el bloqueo ocurre antes de crear
la segunda cuenta de Auth y que exactamente un documento tiene
`role == 'image_manager'`.

---

## 6.5 Herramientas utilizadas

| Herramienta | Propósito |
|---|---|
| `flutter_test` | Framework base de pruebas unitarias y de widgets, incluido en el SDK de Flutter |
| `integration_test` | Framework oficial de pruebas de integración, con ejecución sobre dispositivo o emulador real |
| `fake_cloud_firestore` | Simula Cloud Firestore en memoria, permitiendo probar la comunicación de `Database` con la persistencia sin red ni un proyecto de Firebase real |
| `firebase_auth_mocks` | Simula Firebase Authentication (usuarios y sesión) sin backend real |
| Dispositivo Android físico | Ejecución de los flujos de integración completos, validando la interfaz tal como la percibe el usuario final |

## 6.6 Ventajas del enfoque adoptado

- **Separación de responsabilidades:** cada prueba evalúa una sola capa —
  la interfaz visual con datos simulados, o la comunicación real con la
  base de datos — nunca ambas mezcladas en el mismo bloque de aserciones.
- **Correspondencia con el código real:** cada prueba ejercita
  directamente las clases y pantallas de `lib/`.
- **Organización por módulo y por tipo:** cada módulo del sistema cuenta
  con su cobertura de UI y su cobertura de integración con base de datos
  claramente diferenciadas.
- **Independencia de infraestructura externa:** `fake_cloud_firestore` y
  `firebase_auth_mocks` permiten ejecutar toda la suite en segundos, sin
  depender de un proyecto de Firebase activo ni de conexión a internet.
