// content_assignment_guard.dart
//
// ── Por qué existe este archivo ──────────────────────────────────────────
// Regla confirmada con el usuario: si un estudiante de un grupo ya tiene
// progreso registrado sobre un content (completó o intentó al menos una
// activity, o rindió al menos un quiz de ese content), ese content ya NO
// se puede desasignar de ese grupo — bloqueo duro, sin vía de escape desde
// la UI. Se documenta como decisión de producto conocida: si el docente se
// equivocó de grupo, la única salida es soporte/consola directa, no la app.
//
// ── Por qué NO se usa teacherGroups/{groupId}/students ────────────────────
// Esa subcolección es el roster de membresía del grupo (para mostrar la
// lista de alumnos, invitar, remover). No es la fuente para "qué estudiantes
// pertenecen a este grupo" en el sentido de progreso — la fuente de verdad
// para eso es la colección raíz `students`, que ya trae un campo `groupId`
// directo y consultable (confirmado: se usa así en otras pantallas del
// proyecto, ej. student_detail_progress_screen.dart). Evita además tener
// que mantener sincronizadas dos fuentes de membresía.
//
// ── Costo de lectura ──────────────────────────────────────────────────────
// 1 query para traer los estudiantes del grupo (`students` where groupId==X)
// + 1 lectura de `students/{id}/progress` por cada estudiante encontrado,
// cortando en el primer documento cuyo contentId coincida (no se necesita
// contar cuántos — alcanza con saber si existe al menos uno). Para el
// volumen de un grupo de aula (decenas de estudiantes) esto es aceptable;
// se documenta la misma limitación de escalabilidad ya asumida en el punto
// 10 de validación de nombre de grupo duplicado (leer todo el listado en
// vez de un índice dedicado).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loringo_app/services/database/database.dart';

class ContentAssignmentGuard {
  ContentAssignmentGuard(this._db, {FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final Database _db;
  final FirebaseFirestore _firestore;

  /// Devuelve true si al menos un estudiante del [groupId] tiene algún
  /// documento de progreso (`students/{id}/progress/*`) cuyo `contentId`
  /// coincide con [contentId]. Un resultado true significa "no se puede
  /// desasignar este content de este grupo".
  Future<bool> hasStudentProgress({
    required String contentId,
    required String groupId,
  }) async {
    final studentsSnap = await _firestore
        .collection('students')
        .where('groupId', isEqualTo: groupId)
        .get();

    if (studentsSnap.docs.isEmpty) return false;

    for (final studentDoc in studentsSnap.docs) {
      final progressSnap = await _firestore
          .collection('students')
          .doc(studentDoc.id)
          .collection('progress')
          .where('contentId', isEqualTo: contentId)
          .limit(1)
          .get();

      if (progressSnap.docs.isNotEmpty) return true;
    }

    return false;
  }

  /// Versión en lote: para un [contentId] dado, devuelve el subconjunto de
  /// [groupIds] (típicamente `assignedTo` del content) que tienen progreso
  /// de estudiantes y por lo tanto deben bloquearse en el checkbox de la
  /// UI. Evita que _AssignSheet tenga que llamar hasStudentProgress() una
  /// vez por cada grupo de forma secuencial desde el widget.
  Future<Set<String>> lockedGroupIds({
    required String contentId,
    required List<String> groupIds,
  }) async {
    final locked = <String>{};
    for (final groupId in groupIds) {
      final hasProgress =
          await hasStudentProgress(contentId: contentId, groupId: groupId);
      if (hasProgress) locked.add(groupId);
    }
    return locked;
  }
}