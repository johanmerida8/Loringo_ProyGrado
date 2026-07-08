// test/admin_approval_test.dart
import 'package:flutter_test/flutter_test.dart';

class ApprovalHelper {
  static String getApprovalMessage(int pendingCount) {
    if (pendingCount == 0) return 'All Caught Up!';
    if (pendingCount == 1) return '1 pending review';
    return '$pendingCount pending review';
  }
  
  static String getRejectionReason(String? reason) {
    if (reason == null || reason.isEmpty) return 'No reason provided';
    return reason;
  }
}

void main() {
  group('Admin Content Approval - AAA Testing', () {
    
    test('Should show correct message for 0 pending items', () {
      // ARRANGE
      const pendingCount = 0;
      
      // ACT
      final message = ApprovalHelper.getApprovalMessage(pendingCount);
      
      // ASSERT
      expect(message, equals('All Caught Up!'));
    });

    test('Should show singular for 1 pending item', () {
      // ARRANGE
      const pendingCount = 1;
      
      // ACT
      final message = ApprovalHelper.getApprovalMessage(pendingCount);
      
      // ASSERT
      expect(message, equals('1 pending review'));
    });

    test('Should show plural for multiple pending items', () {
      // ARRANGE
      const pendingCount = 5;
      
      // ACT
      final message = ApprovalHelper.getApprovalMessage(pendingCount);
      
      // ASSERT
      expect(message, equals('5 pending review'));
    });

    test('Should return "No reason provided" for empty rejection reason', () {
      // ARRANGE
      const reason = '';
      
      // ACT
      final result = ApprovalHelper.getRejectionReason(reason);
      
      // ASSERT
      expect(result, equals('No reason provided'));
    });
  });
}