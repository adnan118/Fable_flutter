import 'package:flutter_test/flutter_test.dart';
import 'package:fable_push_notifications/fable_push_notifications.dart';
void main(){
  test('Fable push operation bindings are explicit (not inferred for other backends)',(){
    const b=PushDeviceBindings.fable();
    expect(b.register,'push.device.register');
    expect(b.unregister,'push.device.unregister');
    const other=PushDeviceBindings(register:'my.backend.pushRegister',unregister:'my.backend.pushRemove');
    expect(other.register,isNot(b.register));
  });
}
