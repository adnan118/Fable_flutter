import 'package:flutter_test/flutter_test.dart';
import 'package:fable_realtime/fable_realtime.dart';
void main(){
  test('financial hints invalidate stale UI before authoritative refetch',()async{
    final sequence=<String>[];
    final coordinator=FableVerifiedRefreshCoordinator(
      onSensitiveDataInvalidated:(area)=>sequence.add('stale:${area.name}'),
      refetch:(area)async=>sequence.add('refetch:${area.name}'));
    await coordinator.invalidate(const FableChangeHint(FableChangeArea.prices));
    expect(sequence,['stale:prices','refetch:prices']);
    await coordinator.dispose();
  });
  test('content hint is public-only and does not stale payment state',()async{
    var changed=false;var fetched=false;
    final c=FableVerifiedRefreshCoordinator(
      onSensitiveDataInvalidated:(_)=>changed=true,
      refetch:(_)async=>fetched=true);
    await c.invalidate(const FableChangeHint(FableChangeArea.content));
    expect(changed,false);expect(fetched,true);
    await c.dispose();
  });
}
