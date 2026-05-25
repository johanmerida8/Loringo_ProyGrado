/// Stub translation service — always returns English.
/// Replace with a real implementation when multilingual support is needed.
class TeacherUITranslations {
  static const Map<String, String> _en = {
    // General
    'error': 'Error',
    'cancel': 'Cancel',
    'close': 'Close',
    'retry': 'Retry',
    'menu': 'Menu',
    'add': 'Add',
    'edit': 'Edit',
    'delete': 'Delete',
    'update': 'Update',

    // Auth
    'signOut': 'Sign Out',
    'signOutConfirm': 'Are you sure you want to sign out?',
    'noUserAuthenticated': 'No user authenticated',

    // Teacher Panel / Drawer
    'teacherPanel': 'Teacher Panel',
    'classroomManagement': 'Classroom Management',

    // Groups
    'myGroups': 'My Groups',
    'myGroupsLabel': 'My Groups',
    'createGroup': 'Create Group',
    'createEdit': 'Create',
    'noGroupsCreated': 'No groups yet',
    'noGroupsYet': 'No groups yet',
    'tapToCreateFirst': 'Tap + to create your first group',
    'createFirstGroup': 'Create your first group',
    'groupCreatedWithCode': 'Group created! Code: ',
    'errorCreatingGroup': 'Error creating group: ',
    'deleteGroup': 'Delete Group',
    'deleteGroupConfirm': 'Are you sure you want to delete this group?',

    // Group form
    'groupName': 'Group Name',
    'egGrade1': 'e.g. Grade 1',
    'description': 'Description',
    'groupColor': 'Group Color',
    'groupNameRequired': 'Group name is required',

    // Content
    'content': 'content',
    'contents': 'contents',

    // Students
    'studentsLabel': 'students',
    'manageStudents': 'Manage Students',
    'addStudentsHint': 'Enter student email to add',
    'addStudent': 'Add Student',
    'emailRequired': 'Email is required',
    'studentNotFound': 'Student not found',
    'studentAdded': 'Student added successfully',
    'noStudentsYet': 'No students yet',

    // Navigation tabs
    'groups': 'Groups',
    'assignUnits': 'Assign Units',
    'progress': 'Progress',
    'settings': 'Settings',
    'studentProgress': 'Student Progress',

    // Settings / Account
    'language': 'Language',
    'selectLanguage': 'Select Language',
    'account': 'Account',
    'emailLabel': 'Email',
    'joinedDate': 'Joined',
    'languageUpdated': 'Language updated to ',

    // Activity screens (screen_one – screen_five)
    'continueBtnText': 'Continue',
    'check': 'Check',
    'selectCorrectImage': 'Select the correct image',
    'selectCorrectPhrase': 'Select the correct phrase',
  };

  /// Returns the English string for [key].
  /// [language] is accepted for API compatibility but ignored until
  /// real translation support is added.
  static String get(String key, [String language = 'English']) {
    return _en[key] ?? key;
  }
}
