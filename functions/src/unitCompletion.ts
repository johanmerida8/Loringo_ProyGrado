// functions/src/unitCompletion.ts
//
// The "has this student finished the whole unit?" rule behind the teacher's
// "Unit completed" milestone push (notifyStudentPerformance.ts). Kept as a
// pure, framework-free function -- same approach as groupCode.ts -- so it
// can be unit-tested with Node's built-in runner (unitCompletion.test.ts)
// without Firestore; notifyStudentPerformance.ts only gathers the ids.
//
// Mirrors the client's unit-completion rule (database.dart's
// getChildActivityStatusList / student_activities_screen.dart): every
// activity in every lesson of the unit is completed and, if the unit has
// any Unit Quiz, at least one of them is too. Lesson Quizzes don't count.

/**
 * Whether a unit is fully completed.
 * @param {Set<string>} completedIds Ids of the student's completed
 * progress docs (activities and quizzes share the progress collection).
 * @param {string[]} activityIds Every activity id in the unit.
 * @param {string[]} unitQuizIds Every Unit Quiz id in the unit.
 * @return {boolean} true if the unit counts as completed.
 */
export function isUnitDone(
  completedIds: Set<string>,
  activityIds: string[],
  unitQuizIds: string[]
): boolean {
  // A unit with no activities has nothing to "complete" yet.
  if (activityIds.length === 0) return false;
  if (!activityIds.every((id) => completedIds.has(id))) return false;
  if (unitQuizIds.length === 0) return true;
  return unitQuizIds.some((id) => completedIds.has(id));
}
