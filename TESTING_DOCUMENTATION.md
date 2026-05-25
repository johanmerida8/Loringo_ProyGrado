# Documentación de Pruebas - Loringo App

## 3.3.1. Pruebas de Caja Negra

Las pruebas de caja negra validan el funcionamiento general del sistema sin conocer su estructura interna, enfocándose en el comportamiento desde la perspectiva del usuario.

### 3.3.1.1. Pruebas Unitarias

Las pruebas unitarias permiten asegurar la consistencia de cada uno de los módulos del sistema de forma independiente.

#### Tabla 4.1 Pruebas Unitarias - Módulo Usuarios

| Objetivo | Verificar el correcto funcionamiento del módulo Usuarios de forma independiente |
|----------|------------------|
| **Acción** | • Validar creación de cuentas de usuario con diferentes roles (estudiante, docente, padre, administrador)<br>• Probar autenticación con Firebase Authentication<br>• Validar actualización de perfil de usuario<br>• Probar eliminación lógica de usuarios<br>• Validar recuperación de contraseña<br>• Probar OTP (One-Time Password) |
| **Efecto** | Se valida que cada método y función opera correctamente: creación segura de credenciales, autenticación fluida, actualización de datos de perfil, gestión de contraseñas y OTP funcionando sin errores. |
| **Fuente** | Elaboración Propia (2026) |

#### Tabla 4.2 Pruebas Unitarias - Módulo Contenidos y Recursos

| Objetivo | Verificar el correcto funcionamiento del módulo Contenidos y Recursos de forma independiente |
|----------|------------------|
| **Acción** | • Probar creación, lectura, actualización y eliminación (CRUD) de contenidos<br>• Validar carga de recursos (imágenes, PDFs, videos)<br>• Probar organización jerárquica de contenidos (Unidades, Lecciones, Actividades)<br>• Validar caché de recursos locales<br>• Probar búsqueda y filtrado de contenidos |
| **Efecto** | Se valida que el almacenamiento en Firestore, gestión de recursos en Cloud Storage y caché funcionan correctamente, permitiendo acceso rápido a contenidos. |
| **Fuente** | Elaboración Propia (2026) |

#### Tabla 4.3 Pruebas Unitarias - Módulo Grupos y Avance

| Objetivo | Verificar el correcto funcionamiento del módulo Grupos y Avance de forma independiente |
|----------|------------------|
| **Acción** | • Probar creación y gestión de grupos de estudiantes<br>• Validar vinculación de estudiantes a grupos<br>• Probar registro de progreso de estudiantes en actividades<br>• Validar cálculo de porcentaje de avance<br>• Probar rastreo de puntos y medallas<br>• Validar suscripción a cambios de estado en tiempo real |
| **Efecto** | Se valida que la creación de grupos, vinculación de miembros, registro de progreso y cálculos de avance funcionan correctamente en Firestore. |
| **Fuente** | Elaboración Propia (2026) |

#### Tabla 4.4 Pruebas Unitarias - Módulo Evaluación

| Objetivo | Verificar el correcto funcionamiento del módulo Evaluación de forma independiente |
|----------|------------------|
| **Acción** | • Probar creación y configuración de quizzes<br>• Validar presentación de preguntas y opciones de respuesta<br>• Probar envío y almacenamiento de respuestas<br>• Validar cálculo automático de calificaciones<br>• Probar generación de reportes de evaluación<br>• Validar evaluación autoadministrada y dirigida |
| **Efecto** | Se valida que el ciclo completo de evaluación: creación, presentación, respuesta y calificación funciona sin errores. |
| **Fuente** | Elaboración Propia (2026) |

#### Tabla 4.5 Pruebas Unitarias - Módulo Gamificación

| Objetivo | Verificar el correcto funcionamiento del módulo Gamificación de forma independiente |
|----------|------------------|
| **Acción** | • Probar asignación de puntos por actividades<br>• Validar cálculo de niveles basado en puntos<br>• Probar creación y desbloqueo de medallas<br>• Validar leaderboard (tabla de posiciones)<br>• Probar sesiones de logros desbloqueados<br>• Validar animaciones de recompensas |
| **Efecto** | Se valida que el sistema de gamificación: puntos, niveles, medallas, leaderboard y animaciones funcionan correctamente y se sincronizan con Firestore. |
| **Fuente** | Elaboración Propia (2026) |

#### Tabla 4.6 Pruebas Unitarias - Módulo Reportes

| Objetivo | Verificar el correcto funcionamiento del módulo Reportes de forma independiente |
|----------|------------------|
| **Acción** | • Probar generación de reportes por estudiante<br>• Validar reportes por grupo<br>• Probar reportes de desempeño general<br>• Validar exportación de reportes (PDF, CSV)<br>• Probar filtrado por rango de fechas<br>• Validar agregación de datos desde múltiples fuentes |
| **Efecto** | Se valida que los reportes se generan correctamente, datos se agregan sin errores y exportación funciona en los formatos requeridos. |
| **Fuente** | Elaboración Propia (2026) |

---

### 3.3.1.2. Pruebas de Integración

Las pruebas de integración aseguran la estabilidad y comunicación correcta entre los módulos del sistema.

#### Tabla 4.7 Pruebas de Integración

| Objetivo | Verificar que los módulos del sistema se integran correctamente y se comunican sin errores |
|----------|------------------|
| **Acción** | • Iniciar sesión con roles variados (admin, docente, estudiante, padre)<br>• Probar navegación entre módulos (Usuarios → Grupos → Evaluación → Reportes)<br>• Validar que datos de un módulo se reflejan correctamente en otros<br>• Probar creación de actividades en Contenidos y su aparición en Evaluación<br>• Validar que el progreso registrado en Evaluación se actualiza en el módulo Avance<br>• Probar integración con Firebase (Auth, Firestore, Cloud Storage, Cloud Functions)<br>• Validar sincronización en tiempo real de datos entre módulos<br>• Probar comportamiento offline y sincronización posterior |
| **Efecto** | Todos los módulos funcionan correctamente integrados. Roles y datos se muestran según permisos. Cambios en un módulo se reflejan inmediatamente en otros. Sincronización con Firebase funciona sin pérdida de datos. |
| **Fuente** | Elaboración Propia (2026) |

---

### 3.3.1.3. Pruebas de Compatibilidad

#### 3.3.1.3.1 Pruebas de Compatibilidad Web

Las pruebas de compatibilidad web validan el funcionamiento correcto en diferentes navegadores web.

#### Tabla 4.8 Pruebas de Compatibilidad Web

| Objetivo | Validar el funcionamiento del sistema web en diferentes navegadores |
|----------|------------------|
| **Acción** | Pruebas realizadas en:<br>• Google Chrome (última versión)<br>• Microsoft Edge (última versión)<br>• Mozilla Firefox (última versión)<br>• Safari (última versión) |
| **Efecto** | El sistema funciona correctamente en todos los navegadores soportados. Responsive design se adapta correctamente a resoluciones de escritorio. |
| **Fuente** | Elaboración Propia (2026) |

#### 3.3.1.3.2 Pruebas de Compatibilidad Móvil

#### Tabla 4.9 Pruebas de Compatibilidad Móvil

| Objetivo | Validar el funcionamiento de la aplicación móvil en distintos dispositivos Android |
|----------|------------------|
| **Acción** | Pruebas realizadas en:<br>• POCO X3 Pro<br>• Redmi Note 8 Pro<br>• Pixel 7<br>• Pixel 6 Pro<br>• Samsung A56 5G |
| **Efecto** | Compatibilidad asegurada desde Android 11 a Android 16. Interfaz responsive, touchscreen funciona correctamente, animaciones fluidas. |
| **Fuente** | Elaboración Propia (2026) |

---

### 3.3.1.4. Pruebas de Rendimiento

Las pruebas de rendimiento establecen que existe una respuesta en tiempo real de los datos, la navegación del sistema y otros aspectos que permiten al usuario interactuar de forma dinámica con la aplicación.

#### Tabla 4.10 Pruebas de Rendimiento

| Objetivo | Evaluar la velocidad de respuesta, consumo de recursos y fluidez general del sistema |
|----------|------------------|
| **Acción** | • Pruebas con múltiples usuarios simultáneos<br>• Carga y renderizado de datos volumétricos<br>• Navegación entre pantallas<br>• Carga de imágenes y animaciones<br>• Sincronización con Firebase en tiempo real<br>• Profiling de memoria y CPU<br>• Pruebas de latencia de red |
| **Efecto** | • Respuesta en menos de 2 segundos para operaciones normales<br>• 60 FPS estables en animaciones y navegación<br>• Consumo de memoria entre 150–400 MB<br>• Carga optimizada con caché local<br>• Navegación entre pantallas menor a 0.3s<br>• Sincronización Firestore menor a 1 segundo en conexión normal |
| **Fuente** | Elaboración Propia (2026) |

---

## 3.3.2. Pruebas de Caja Blanca

Las pruebas de caja blanca evalúan la estructura lógica interna del sistema, validaciones, seguridad y control de acceso.

### 3.3.2.1. Pruebas de Validación de Formularios

Las pruebas de validación de formularios permiten evaluar que los datos cumplen todas las reglas de validación y que todos los datos se graban y consultan de forma correcta.

#### Tabla 4.11 Pruebas de Validación de Formularios

| Objetivo | Validar que los formularios verifican correctamente todos los campos según reglas internas |
|----------|------------------|
| **Acción** | **Módulo Usuarios:**<br>• Correos electrónicos (formato válido, no duplicados)<br>• Contraseñas (mínimo 8 caracteres, complejidad requerida)<br>• Nombres de usuario (sin caracteres especiales, 3-20 caracteres)<br>• Teléfono (formato según país)<br><br>**Módulo Contenidos:**<br>• Títulos de contenidos (máximo 255 caracteres, no vacíos)<br>• Descripciones (validación de contenido)<br>• Archivos uploaded (tipo y tamaño válido)<br><br>**Módulo Grupos:**<br>• Nombres de grupos (no duplicados, 3-100 caracteres)<br>• Códigos de acceso (alfanuméricos, únicos)<br><br>**Módulo Evaluación:**<br>• Preguntas (no vacías, mínimo 2 opciones)<br>• Fechas límite de actividades (no en el pasado)<br>• Duración de evaluaciones (números positivos)<br><br>**Módulo Gamificación:**<br>• Puntos de actividades (números válidos)<br>• Niveles requeridos (coherencia en progresión)<br><br>**Multilingüe:**<br>• Palabras en español-inglés (validación de caracteres según idioma) |
| **Módulos Probados** | Todos (Usuarios, Contenidos, Recursos, Grupos, Evaluación, Gamificación, Reportes) |
| **Efecto** | Las validaciones implementadas garantizan que todos los campos verifican correctamente su formato, obligatoriedad, rangos y consistencia. Se evita el ingreso de datos erróneos o inválidos. Los datos se guardan correctamente en Firestore y se recuperan sin corrupción. |
| **Fuente** | Elaboración Propia (2026) |

---

### 3.3.2.2. Pruebas de Seguridad

Las pruebas de seguridad validan los diferentes accesos al sistema y el control que se tiene por los roles de acceso, garantizando que cada usuario solo acceda según su rol asignado en Firebase.

#### 3.3.2.2.1 Caso 1: Intento de Ingreso Forzado

#### Tabla 4.12 Pruebas de Seguridad - Ingreso Forzado

| Objetivo | Garantizar que el sistema no permita accesos no autorizados |
|----------|------------------|
| **Acción** | • Intentos con credenciales incorrectas<br>• Intentos con usuarios deshabilitados<br>• Intentos con códigos OTP inválidos<br>• Múltiples intentos fallidos consecutivos<br>• Fuerza bruta simulada<br>• Expiración de tokens de Firebase |
| **Efecto** | El sistema rechaza accesos inválidos y solo permite ingreso a usuarios autenticados correctamente. Firebase Auth gestiona la autenticación seguramente. Se bloquean intentos de fuerza bruta. |
| **Fuente** | Elaboración Propia (2026) |

#### 3.3.2.2.2 Caso 2: Control de Acceso por Rol

#### Tabla 4.13 Pruebas de Seguridad - Control de Acceso por Rol

| Objetivo | Validar que cada rol acceda únicamente a funciones permitidas |
|----------|------------------|
| **Acción** | **Estudiante:**<br>• Intentar acceder a funciones de docente (crear actividades, calificar)<br>• Intentar acceder a panel de administrador<br>• Intentar ver datos de otros estudiantes<br><br>**Docente:**<br>• Acceder solo a sus grupos<br>• No poder acceder a grupos de otros docentes<br>• No poder modificar configuración global del sistema<br><br>**Padre:**<br>• Ver solo datos de sus hijos vinculados<br>• No poder ver datos de otros estudiantes<br><br>**Administrador:**<br>• Acceso total a todas las funciones<br>• Validar que solo admins pueden crear otros admins |
| **Efecto** | El sistema aplica control de acceso por rol mediante Firebase Security Rules en Firestore. Cada rol accede únicamente a datos y funciones permitidas. |
| **Fuente** | Elaboración Propia (2026) |

#### 3.3.2.2.3 Caso 3: Protección de Datos Sensibles y Sesiones

#### Tabla 4.14 Pruebas de Seguridad - Protección de Datos Sensibles

| Objetivo | Verificar que el sistema maneje de forma segura la autenticación, la sesión del usuario y el acceso a datos sensibles utilizando Firebase Auth |
|----------|------------------|
| **Acción** | • Verificar que las credenciales se transmiten encriptadas (HTTPS)<br>• Intentar acceder a recursos protegidos sin estar autenticado<br>• Verificar que Firebase Auth gestione adecuadamente la sesión del usuario<br>• Validar que la sesión persista correctamente con refresh tokens<br>• Comprobar que el cierre de sesión elimine las credenciales locales (SharedPreferences/Keystore)<br>• Revisar que no se expongan datos sensibles en logs o consola<br>• Validar que los correos de usuarios no se muestren en errores públicos<br>• Probar que tokens expirados se refresca automáticamente<br>• Validar revocar sesión activa desde otro dispositivo |
| **Efecto** | El sistema mantiene la seguridad delimitando la autenticación y el manejo de sesiones a Firebase Auth. Se evita el almacenamiento de contraseñas en la aplicación. Se impiden accesos no autorizados. Se gestiona correctamente la sesión activa del usuario. Se evita la exposición de datos sensibles. |
| **Fuente** | Elaboración Propia (2026) |

#### 3.3.2.2.4 Caso 4: Moderación de Contenido Multimedia

#### Tabla 4.15 Pruebas de Seguridad - Moderación de Imágenes Inapropiadas

| Objetivo | Validar que el sistema detecte y rechace imágenes inapropiadas para menores de edad |
|----------|------------------|
| **Acción** | • Intentar subir imágenes sospechosas de contenido adulto<br>• Validar que Cloud Vision API analiza imágenes antes de almacenarse<br>• Probar que el sistema rechace imágenes con flagging de contenido explícito<br>• Validar que solo docentes/admins pueden subir imágenes<br>• Probar visualización de advertencia si imagen tiene contenido limitado<br>• Validar que imágenes moderadas se marquen en Firestore<br>• Probar escaneo automático de imágenes existentes en Cloud Storage<br>• Validar que los estudiantes no puedan subir contenido multimedia directamente |
| **Efecto** | Solo imágenes apropiadas para menores son permitidas en el sistema. Integraciones con servicios de moderación funcionan correctamente. Imágenes inapropiadas se rechazan con mensajes claros. Se mantiene un registro de moderación en Firestore para auditoría. |
| **Fuente** | Elaboración Propia (2026) |

#### 3.3.2.2.5 Caso 5: Encriptación de Datos en Tránsito y Almacenamiento

#### Tabla 4.16 Pruebas de Seguridad - Encriptación de Datos

| Objetivo | Garantizar que los datos sensibles se transmiten encriptados y se almacenan de forma segura |
|----------|------------------|
| **Acción** | • Validar conexiones HTTPS a Firebase<br>• Revisar que Firestore Security Rules apliquen encriptación en server-side<br>• Validar que datos sensibles en caché local se encrypten (usando packages como flutter_secure_storage)<br>• Probar que bases de datos locales (SQLite) usen encriptación si contienen datos sensibles<br>• Validar que archivos descargados de Cloud Storage no se guardan sin protección |
| **Efecto** | Todos los datos en tránsito se transmiten por HTTPS. Datos sensibles en reposo se encriptan correctamente. Firebase gestiona la encriptación en servidor. |
| **Fuente** | Elaboración Propia (2026) |

---

## Resumen de Módulos Probados

| Módulo | Unitarias | Integración | Validación | Seguridad | Moderación |
|--------|-----------|-------------|-----------|-----------|-----------|
| Usuarios | ✓ | ✓ | ✓ | ✓ | - |
| Contenidos y Recursos | ✓ | ✓ | ✓ | ✓ | ✓ |
| Grupos y Avance | ✓ | ✓ | ✓ | ✓ | - |
| Evaluación | ✓ | ✓ | ✓ | ✓ | - |
| Gamificación | ✓ | ✓ | ✓ | ✓ | - |
| Reportes | ✓ | ✓ | ✓ | ✓ | - |

---

## Conclusiones

La ejecución de pruebas comprehensivas aseguró:

1. **Funcionalidad**: Cada módulo funciona correctamente de forma independiente.
2. **Integración**: Los módulos se comunican sin errores y comparten datos correctamente.
3. **Seguridad**: El sistema protege contra accesos no autorizados, aplicando control por roles mediante Firebase.
4. **Compatibilidad**: La aplicación funciona en múltiples plataformas y dispositivos.
5. **Rendimiento**: El sistema responde rápidamente manteniendo fluidez en interacciones.
6. **Validación**: Los datos ingresados son validados correctamente evitando inconsistencias.
7. **Protección de Menores**: El contenido multimedia se modera para asegurar que no sea inapropiado para menores.

**Fuente**: Elaboración Propia (2026)
