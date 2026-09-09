# Seguridad y Protección de Datos de Menores en Loringo

Documento de soporte para la tesis, enfocado en las medidas de protección de
datos personales y seguridad aplicadas a los usuarios menores de edad
(estudiantes) de la aplicación. Cada afirmación está verificada directamente
contra el código fuente (`lib/`, `functions/`, `firestore.rules`) a la fecha de
este documento — se indican explícitamente los puntos donde la protección es
parcial o no existe aún, para mantener el rigor académico del análisis.

## Resumen

| # | Aspecto | Estado |
|---|---|---|
| 1 | Datos mínimos recopilados del menor (solo nombre + avatar ilustrado) | ✅ Confirmado |
| 2 | El menor no puede autoregistrarse; solo el padre crea su perfil | ✅ Confirmado |
| 3 | Consentimiento informado explícito (checkbox/política aceptada con registro auditable) | ✅ Confirmado (dos niveles, versionado, forzado también por `firestore.rules`) |
| 4 | Límite de menores por cuenta de padre (control de abuso) | ✅ Confirmado (máx. 8) |
| 5 | Código de acceso del menor nunca almacenado en texto plano | ✅ Confirmado |
| 6 | Hash de código con clave secreta (HMAC-SHA256 + pepper) | ✅ Confirmado |
| 7 | Cifrado reversible del código para que el padre pueda revelarlo (AES-256-GCM) | ✅ Confirmado |
| 8 | Confirmación de identidad (biometría/contraseña) antes de revelar el código | ✅ Confirmado |
| 9 | Reglas de Firestore por documento/rol, denegación por defecto | ✅ Confirmado |
| 10 | Secretos de terceros nunca en el cliente (Cloudinary, Google Vision) | ✅ Confirmado |
| 11 | Moderación automática de imágenes antes de llegar al menor | ✅ Confirmado |
| 12 | Reconocimiento de voz sin persistencia de audio en la nube | ✅ Confirmado |
| 13 | Eliminación en cascada de los registros del menor al borrar la cuenta del padre | ✅ Confirmado (progreso/reportes en TODOS los grupos, no solo el actual) |
| 14 | Política de privacidad publicada dentro de la app | ✅ Confirmado (`assets/legal/privacy_policy_{es,en}.txt`, visible desde ambos puntos de consentimiento) |
| 15 | Mecanismo de exportación/portabilidad de datos a solicitud del padre | ❌ No existe |
| 16 | Código de grupo del docente nunca almacenado en texto plano, hash/cifrado generados en el servidor | ✅ Confirmado |
| 17 | Reautenticación obligatoria (contraseña) antes de eliminar una cuenta (padre o docente) | ✅ Confirmado |
| 18 | Endurecimiento de reglas de Firestore para OTP y registros de restablecimiento de contraseña | ✅ Confirmado |

---

## 1. Datos recopilados

### Del menor (colección `students`, ver `lib/services/database/database.dart`)
- `names`: nombre completo, ingresado por el padre (no por el menor).
- `avatar`: URL de una imagen ilustrada prediseñada (Cloudinary, ver
  `lib/components/avatar_selector.dart`) — **no es una fotografía real** del
  menor ni de ninguna persona.
- `parentId`, `groupId`, `groupHistory`: referencias relacionales (a qué padre
  y a qué grupo/aula pertenece), sin datos de contacto ni ubicación.
- `accessCodeHash` / `accessCodeEncrypted`: derivados del código de acceso
  (nunca el código en sí — ver sección 5).
- `state`, `createdAt`: metadatos administrativos.

### Progreso académico (`teacherGroups/{groupId}/students/{studentId}/progress`
y `/reports`)
- Puntajes, número de intentos, respuestas por tarea (`taskAnswers`),
  estrellas obtenidas, XP ganada, retroalimentación del docente.

### Explícitamente **no** se recopila
Fecha de nacimiento, documento de identidad, dirección, ubicación geográfica,
número de teléfono, fotografías reales del rostro del menor, ni grabaciones de
audio persistentes (ver sección 6, reconocimiento de voz).

### Copia local en el dispositivo del menor
`lib/services/auth/student_auth_service.dart` guarda en `SharedPreferences`
(almacenamiento local del dispositivo, no sincronizado a la nube):
`studentId`, nombre, avatar y **el código de acceso en texto plano** — usado
únicamente para mantener la sesión activa y para el flujo de reingreso con
biometría. Es una limitación menor: el cifrado de este dato depende del
cifrado de disco del sistema operativo, no de un cifrado propio de la app.

---

## 2. Consentimiento del padre/tutor

- El menor **no tiene una pantalla de registro propia**: no existe ningún
  flujo en la app donde un estudiante cree su propia cuenta o introduzca sus
  propios datos. El único punto de entrada es
  `lib/screens/parent/parent_register_child_screen.dart`, accesible
  exclusivamente desde una sesión de padre ya autenticada con Firebase Auth
  (correo + contraseña).
- Es el padre quien, de forma activa, introduce el nombre del menor y
  selecciona su avatar; el sistema genera el código de acceso y lo entrega
  **solo al padre** (nunca se muestra al público ni se comparte por otro
  canal).
- Límite de 8 menores por cuenta de padre
  (`Database.maxChildrenPerParent`), pensado como control adicional contra
  registros masivos o mal uso de la función.
- ✅ **Consentimiento en dos niveles, exigido en el flujo**: se implementó
  una política de privacidad única (`assets/legal/privacy_policy_es.txt` /
  `_en.txt`, según el idioma de la app) con dos momentos de aceptación
  distintos:
  1. **General**, al crear la cuenta (`register_screen.dart`): una casilla
     obligatoria ("He leído y acepto la política de privacidad...") antes de
     poder enviar el formulario de registro, cubriendo los propios datos del
     padre/docente/administrador. `Database.createUser` rechaza la creación
     de la cuenta si `privacyPolicyAccepted` no es `true`
     (`lib/services/database/database.dart`), pero este consentimiento ya no
     se persiste como campo con marca de tiempo en el documento — solo se
     verifica en el momento del registro.
  2. **Específico del menor**, al registrar a un hijo/a
     (`parent_register_child_screen.dart`): una segunda casilla, con texto
     propio ("Confirmo que soy el padre/madre o tutor legal... y autorizo la
     recopilación de sus datos..."), obligatoria para habilitar el botón de
     registro — un consentimiento distinto y específico para los datos del
     menor, no una reutilización del consentimiento general de la cuenta.
     Este sí queda registrado como evento auditable en el propio documento:
     `students/{id}.childDataConsentAcceptedAt` /
     `.childDataConsentVersion` (`Database.createStudent`), con marca de
     tiempo del servidor y la versión de la política vigente
     (`kPrivacyPolicyVersion`, `lib/utils/privacy_policy.dart`). Además,
     `firestore.rules` exige la presencia de este campo en la creación del
     documento (`request.resource.data.childDataConsentAcceptedAt is
     timestamp`), de modo que el consentimiento específico del menor no
     depende solo de la casilla en la interfaz — un cliente modificado no
     puede crear un perfil de menor sin ese campo. El consentimiento general
     de cuenta, en cambio, solo se aplica del lado del cliente y como
     comprobación defensiva en `Database.createUser`; no quedó como registro
     auditable con marca de tiempo por decisión explícita (campos
     considerados innecesarios para el registro de la cuenta general).

---

## 3. Permisos

### Roles de cuenta (Firebase Auth + `users/{uid}.role`)
`admin`, `teacher`, `parent`. **El estudiante no tiene cuenta de Firebase
Auth** — se autentica exclusivamente mediante el código de acceso (ver
sección 5), lo que reduce la superficie de datos de identidad ligados al
menor (no hay correo ni contraseña de un menor que proteger).

### Permisos del dispositivo
- Cámara/galería (`permission_handler`) — solo en las cuentas de docente/
  administrador, para seleccionar o subir imágenes al repositorio educativo;
  el menor nunca sube imágenes propias.
- Micrófono — para las tareas de pronunciación (`speech_to_text`), con
  solicitud de permiso nativa del sistema operativo.
- Biometría (Face ID / huella, `local_auth`) — opcional, activada mediante un
  diálogo explícito de confirmación ("¿Habilitar biometría?",
  `lib/providers/biometric_provider.dart`), nunca forzada.

### Permisos a nivel de datos
Ver sección 5 (control de acceso) para el detalle de `firestore.rules`.

---

## 4. Almacenamiento

| Dato | Dónde | Detalle |
|---|---|---|
| Perfil y progreso del menor | Cloud Firestore (Google Cloud) | Colección `students` + subcolecciones `teacherGroups/{groupId}/students/{studentId}/{progress,reports}` |
| Avatares e imágenes educativas | Cloudinary (CDN externo) | Nunca Firebase Storage; entrega vía HTTPS |
| Secretos de API (Cloudinary, Google Vision, claves de hash/cifrado) | Firebase Cloud Functions *Secrets* (`defineSecret`) | Nunca en el cliente compilado — ver `functions/src/moderateImage.ts`, `deleteCloudinaryImage.ts`, `listCloudinaryAvatars.ts` |
| Sesión local del menor | `SharedPreferences` en el dispositivo | Ver limitación en sección 1 |

Los secretos usados por el backend (`ACCESS_CODE_PEPPER`, `ACCESS_CODE_KEY`,
`CLOUDINARY_API_SECRET`, `GOOGLE_VISION_API_KEY`) se inyectan únicamente en el
entorno de ejecución de las Cloud Functions correspondientes; ni siquiera se
compilan dentro del binario/paquete web de la aplicación cliente.

---

## 5. Control de acceso

### Autenticación del menor sin contraseña
El estudiante no usa correo ni contraseña: ingresa un código de 6 caracteres
generado con `Random.secure()` (generador criptográficamente seguro),
excluyendo caracteres visualmente ambiguos (`O`, `0`, `I`, `1`).

### El código nunca se guarda en texto plano
`lib/utils/access_code_hasher.dart` y `lib/utils/access_code_cipher.dart`
derivan dos valores a partir del código, y **solo esos derivados** se
persisten en Firestore:

1. **`accessCodeHash`** — HMAC-SHA256 con una clave secreta (*pepper*)
   propia de la aplicación. Se usa únicamente para la búsqueda al iniciar
   sesión (`Database.findStudentByAccessCode`). El *pepper* hace que, incluso
   ante una filtración completa de la base de datos, no sea viable
   precalcular (*rainbow table*) todos los códigos posibles sin también tener
   acceso al secreto del servidor.
2. **`accessCodeEncrypted`** — cifrado simétrico **AES-256-GCM**. Permite que
   el propio padre pueda volver a **ver** el código (es estático, no rota en
   cada consulta) sin que el valor esté nunca expuesto de forma legible para
   un tercero con acceso de solo lectura a la base de datos.

### Confirmación de identidad para revelar el código
`lib/services/auth/identity_confirmation.dart` exige que el padre confirme su
identidad —biometría (Face ID/huella) si está habilitada, con contraseña de
la cuenta como respaldo— antes de descifrar y mostrar el código de su hijo.
Esto evita que alguien con acceso físico momentáneo al teléfono ya
desbloqueado del padre pueda ver el código sin volver a demostrar quién es.

### Reglas de seguridad de Firestore (`firestore.rules`)
- `students/{studentId}`: lectura pública (necesaria para que el menor pueda
  iniciar sesión sin tener ya una sesión de Firebase), pero **creación**
  restringida al padre autenticado dueño (`parentId == request.auth.uid`), y
  **actualización** restringida a: el propio padre, el docente del grupo del
  estudiante, o — sin sesión de Firebase — solo si el documento aún conserva
  un código de acceso válido (hash), lo que habilita casos legítimos como que
  el propio menor actualice su avatar desde su sesión por código.
- `teacherGroups/{groupId}/students/{studentId}/reports`: lectura/escritura
  restringida al padre dueño del estudiante o al docente del grupo — nunca a
  un tercero.
- **Denegación por defecto**: cualquier colección no contemplada
  explícitamente en las reglas queda bloqueada
  (`match /{document=**} { allow read, write: if false; }`).
- `otps/{otpId}`: **lectura y escritura completamente bloqueadas** desde el
  cliente (`allow read, create, update, delete: if false`). Antes de esta
  corrección, `allow read: if true` permitía que cualquiera consultara
  directamente esta colección y leyera el código OTP vigente de cualquier
  cuenta, sin siquiera intentar iniciar sesión — una vía completa de
  apropiación de cuenta a través del flujo de restablecimiento de
  contraseña. Los OTP ahora solo se leen/escriben desde el Admin SDK en
  Cloud Functions (`functions/src/email.ts`), que ignora estas reglas.
- `password_reset_logs/{logId}`: el borrado ahora solo se permite sobre
  entradas con más de 30 días (`resource.data.timestamp < request.time -
  duration.value(30, 'd')`). Antes, `allow delete: if true` permitía borrar
  la propia entrada de log recién creada y reintentar de inmediato,
  anulando por completo el limitador de intentos (*rate limiting*) que esta
  colección existe para hacer cumplir.

### Código de grupo del docente: mismo modelo, pero del lado del servidor
El código de 6 caracteres que un docente comparte para que un estudiante se
una a su grupo (`teacherGroups/{groupId}`) sigue exactamente el mismo
principio que el código de acceso del menor (hash HMAC-SHA256 para
búsqueda + cifrado AES-256-GCM reversible para volver a mostrarlo) — pero
con una diferencia deliberada y relevante para la seguridad: todo el
hashing/cifrado ocurre en `functions/src/groupCode.ts` (Cloud Functions),
nunca en el cliente Flutter.

- `generateGroupCode`, `revealGroupCode`, `findGroupByCode` son funciones
  *callable* que corren en el servidor con las claves secretas
  `GROUP_CODE_PEPPER`/`GROUP_CODE_KEY` inyectadas como *Secrets* de Firebase
  Functions (`defineSecret`) — nunca compiladas dentro del paquete de la
  app.
- `firestore.rules` refuerza esto del lado de la base de datos: la creación
  de un `teacherGroups/{groupId}` rechaza explícitamente cualquier intento
  de escribir un campo `groupCode` en texto plano
  (`!('groupCode' in request.resource.data)`), y una actualización solo se
  permite si ese campo no cambia — así que incluso un cliente modificado no
  puede reintroducir el código en claro.
- **Por qué esto importa para el análisis de seguridad**: el código de
  acceso del menor (sección 5, arriba) deriva su hash/cifrado en el
  *cliente* (`lib/utils/access_code_hasher.dart` /
  `access_code_cipher.dart`), lo que obliga a que el *pepper*/clave de
  cifrado viajen dentro del paquete compilado de la app (vía `.env`) — una
  debilidad arquitectónica reconocida (ver Recomendaciones). El código de
  grupo del docente se diseñó deliberadamente para no repetir ese mismo
  problema, sirviendo como el patrón de referencia hacia el que debería
  migrar el código de acceso del menor en un trabajo futuro.

### Separación de secretos del cliente
Toda operación que requiere una credencial sensible de un tercero (borrar/
listar en Cloudinary, moderar con Google Vision) se ejecuta exclusivamente en
Cloud Functions del lado del servidor — nunca directamente desde la app — de
forma que el paquete compilado de la aplicación no contiene ninguna clave que
permita a un atacante suplantar esas llamadas.

---

## 6. Tratamiento de la información de menores

- **Minimización de datos**: solo se recopila el nombre y un avatar ilustrado
  del menor (sección 1); no se piden datos de contacto, ubicación ni
  identificadores gubernamentales.
- **Finalidad limitada**: los datos del menor se usan exclusivamente para (a)
  identificarlo dentro de su grupo/aula, (b) calcular y mostrar su progreso
  académico al docente y al padre, y (c) la gamificación interna (XP, ligas).
  No se comparten con fines publicitarios ni se venden a terceros; los únicos
  terceros que procesan datos son proveedores de infraestructura (Google
  Firebase/Cloud, Cloudinary para imágenes, OneSignal para notificaciones
  push dirigidas al padre/docente — no al menor, que no tiene cuenta propia
  de notificaciones).
- **Moderación de contenido antes de llegar al menor**: toda imagen que un
  docente o administrador sube al repositorio compartido pasa por dos capas
  de moderación (`ImageService.uploadToCloudinary`,
  `functions/src/moderateImage.ts`): un filtro de nombre de archivo y un
  análisis de contenido con Google Cloud Vision SafeSearch, rechazando
  contenido marcado como muy probable en categorías de adulto/violencia antes
  de que quede disponible para cualquier estudiante.
- **Reconocimiento de voz sin persistencia de audio**: las tareas de
  pronunciación usan el motor de reconocimiento nativo del sistema operativo
  (paquete `speech_to_text`, ver `lib/services/speech_to_text/`); la
  aplicación conserva únicamente el resultado textual/de coincidencia de la
  tarea, no un archivo de audio de la voz del menor.
- **Eliminación de la cuenta y sus menores asociados**
  (`lib/screens/parent/parent_navigation_screen.dart::_deleteAccount`): al
  eliminar su cuenta, el padre es advertido explícitamente de que se
  eliminarán también los registros de sus hijos. El código:
  1. Exige una **reautenticación real con contraseña**
     (`reauthenticateWithPassword`, `lib/services/auth/identity_confirmation
     .dart`) **antes** de tocar cualquier dato — no basta con que la sesión
     de Firebase ya esté iniciada. Esto se corrigió después de detectar que
     el orden anterior (borrar todo primero, reautenticar al final para
     poder llamar a `user.delete()`) podía dejar el borrado a medio hacer
     si esa reautenticación fallaba tras ya haber destruido los datos.
  2. Para cada `students/{studentId}` con ese `parentId`, llama a
     `Database.deleteStudentCascade`, que borra el documento del estudiante
     **y** su progreso/intentos/reportes en **todos** los grupos en los que
     alguna vez estuvo (`groupHistory`), no solo el grupo actual — cierra la
     brecha de datos huérfanos documentada en una versión anterior de este
     análisis.
  3. Borra el documento del padre en `users` y, por último, la cuenta de
     Firebase Auth (`user.delete()`).
- **Eliminación de la cuenta del docente**
  (`lib/screens/teacher/teacher_profile_screen.dart::_deleteAccount`): sigue
  el mismo patrón (reautenticación con contraseña primero, cascada después).
  `Database.deleteTeacherOwnedData` borra el contenido educativo propio del
  docente, sus categorías/imágenes de la mediateca, marcadores, campaña de
  liga, y cada grupo (`teacherGroups`) que posee — incluyendo el progreso de
  cada estudiante bajo esos grupos. **No** borra los perfiles de los
  estudiantes (`students/{id}`) en sí, solo su historial bajo los grupos de
  ese docente; y está bloqueada mientras el docente tenga algún grupo activo
  (no archivado), forzando a archivarlo primero como paso explícito antes de
  una eliminación irreversible.

---

## Recomendaciones para trabajo futuro

1. Ofrecer un mecanismo de exportación de los datos del menor a solicitud del
   padre (portabilidad de datos).
2. Evaluar cifrar en reposo el código de acceso también en el almacenamiento
   local del dispositivo (`SharedPreferences`), no solo en Firestore.
3. Migrar el hashing/cifrado del código de acceso del menor
   (`access_code_hasher.dart` / `access_code_cipher.dart`) de operación
   cliente a Cloud Functions, siguiendo el mismo patrón ya implementado para
   el código de grupo del docente (`functions/src/groupCode.ts`) — esto
   eliminaría la necesidad de que el *pepper*/clave de cifrado viajen dentro
   del paquete compilado de la app.
4. El consentimiento implementado aplica solo a cuentas/menores nuevos — no
   se exige re-consentimiento retroactivo a cuentas creadas antes de este
   cambio (no hay usuarios reales aún en esta etapa del proyecto). Si la app
   llega a tener usuarios reales antes de este punto, evaluar una migración
   de consentimiento para las cuentas existentes.
5. Exponer al padre/docente un mecanismo explícito para revisar/exportar el
   registro de intentos de acceso (`password_reset_logs`, OTP) asociado a su
   propia cuenta, como parte de la transparencia frente al usuario.
