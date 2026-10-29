import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';

void main() {
  test('only safe account fields are represented', () {
    final summary=FableAccountSummary.fromMap({
      'id':'user-1','displayName':'Example','email':'example@example.org',
      'passwordHash':'must-never-be-presented','roles':['admin'],
    });
    expect(summary.id,'user-1');
    expect(summary.displayName,'Example');
    expect(summary.email,'example@example.org');
    expect(summary.toString().contains('must-never-be-presented'),false);
  });
  test('reject invalid response shape and control character injection',(){
    expect(()=>FableAccountSummary.fromMap({'id':''}),throwsFormatException);
    expect(()=>FableAccountSummary.fromMap({'id':'user','email':123}),throwsFormatException);
    expect(()=>FableAccountSummary.fromMap({'id':'user','displayName':'x\u0001y'}),throwsFormatException);
  });
}
