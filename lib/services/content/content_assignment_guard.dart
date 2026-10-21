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
// ── Por qué ahora SÍ se usa teacherGroups/{groupId}/students ───────────────
// El progreso ya no vive bajo la raíz `students/{id}/progress` — vive
// anidado bajo la propia membresía del grupo
// (`teacherGroups/{groupId}/students/{studentId}/progress`), así que el
// roster de membresía es ahora la fuente natural y directa: ya no hace
// falta cruzar con la colección raíz `students` en absoluto.
//
// ── Costo de lectura ──────────────────────────────────────────────────────
// 1 query para traer el roster del grupo (`teacherGroups/{groupId}/students`)
// + 1 lectura de progreso anidado por cada estudiante encontrado, cortando
// en el primer documento cuyo contentId coincida (no se necesita contar
// cuántos — alcanza con saber si existe al menos uno). Para el volumen de
// un grupo de aula (decenas de estudiantes) esto es aceptable; se documenta
// la misma limitación de escalabilidad ya asumida en el punto 10 de
// validación de nombre de grupo duplicado (leer todo el listado en vez de
// un índice dedicado).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loringo_app/services/database/database.dart';

class ContentAssignmentGuard {
  ContentAssignmentGuard(this._db, {FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final Database _db;
  final FirebaseFirestore _firestore;

  /// Devuelve true si al menos un miembro del roster de [groupId] tiene
  /// algún documento de progreso
  /// (`teacherGroups/{groupId}/students/{id}/progress/*`) cuyo `contentId`
  /// coincide con [contentId]. Un resultado true significa "no se puede
  /// desasignar este content de este grupo".
  Future<bool> hasStudentProgress({
    required String contentId,
    required String groupId,
  }) async {
    final rosterSnap = await _firestore
        .collection('teacherGroups')
        .doc(groupId)
        .collection('students')
        .get();

    if (rosterSnap.docs.isEmpty) return false;

    for (final rosterDoc in rosterSnap.docs) {
      final progressSnap = await rosterDoc.reference
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