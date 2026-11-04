import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

class _FakeProtectedSource implements SessionBoundMediaByteSource {
  _FakeProtectedSource(this.readBody);
  final Future<Uint8List> Function(MediaByteRange) readBody;
  final StreamController<MediaSessionInvalidation> _events=
      StreamController<MediaSessionInvalidation>.broadcast(sync:true);
  bool _active=true;
  int reads=0;
  int cancellations=0;

  @override bool get isActive=>_active;
  @override Stream<MediaSessionInvalidation> get invalidations=>_events.stream;
  @override Future<Uint8List> read(MediaByteRange range){
    reads++;
    return readBody(range);
  }
  @override void cancelPendingReads(){cancellations++;}
  void invalidate(MediaSessionInvalidation reason){
    _active=false;
    _events.add(reason);
  }
  @override Future<void> close()async{
    if(!_active)return _events.close();
    invalidate(MediaSessionInvalidation.sourceClosed);
    await _events.close();
  }
}

void main(){
  test('RC117 domain use case refuses stale session without dispatching bytes',()async{
    final source=_FakeProtectedSource((_)async=>Uint8List.fromList([1,2,3]));
    addTearDown(source.close);
    source.invalidate(MediaSessionInvalidation.accountChanged);
    final result=await ReadMediaRangeUseCase(source)(
      const MediaByteRange(start:0,length:3));
    expect(result,isA<MediaReadFailed>());
    expect((result as MediaReadFailed).failure.kind,
      MediaReadFailureKind.sessionChanged);
    expect(source.reads,0);
  });

  test('RC117 account replacement synchronously purges already-ready UI bytes',()async{
    final source=_FakeProtectedSource((_)async=>Uint8List.fromList([1,2,3]));
    addTearDown(source.close);
    final state=MediaRangeController(ReadMediaRangeUseCase(source));
    addTearDown(state.dispose);
    await state.load(const MediaByteRange(start:0,length:3));
    expect(state.state,isA<MediaRangeReady>());
    source.invalidate(MediaSessionInvalidation.accountChanged);
    expect(state.state,isA<MediaRangeIdle>());
    expect(source.cancellations,1);
    await state.load(const MediaByteRange(start:0,length:3));
    expect(state.state,isA<MediaRangeFailureState>());
    expect((state.state as MediaRangeFailureState).reason,
      MediaReadFailureKind.sessionChanged);
    expect(source.reads,1);
  });

  test('RC117 late result cannot repopulate UI after account invalidation',()async{
    final block=Completer<Uint8List>();
    final source=_FakeProtectedSource((_)=>block.future);
    addTearDown(source.close);
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    addTearDown(controller.dispose);
    final request=controller.load(const MediaByteRange(start:0,length:3));
    expect(controller.state,isA<MediaRangeLoading>());
    source.invalidate(MediaSessionInvalidation.accountChanged);
    expect(controller.state,isA<MediaRangeIdle>());
    block.complete(Uint8List.fromList([7,8,9]));
    await request;
    expect(controller.state,isA<MediaRangeIdle>());
    expect(source.cancellations,1);
  });

  test('RC117 credential rotation and server end each purge displayed data',()async{
    for(final reason in [
      MediaSessionInvalidation.credentialsRotated,
      MediaSessionInvalidation.playbackEnded,
    ]){
      final source=_FakeProtectedSource((_)async=>Uint8List.fromList([4]));
      final controller=MediaRangeController(ReadMediaRangeUseCase(source));
      try{
        await controller.load(const MediaByteRange(start:0,length:1));
        expect(controller.state,isA<MediaRangeReady>());
        source.invalidate(reason);
        expect(controller.state,isA<MediaRangeIdle>());
      }finally{
        controller.dispose();
        await source.close();
      }
    }
  });

  test('RC117 reset and dispose cancel pending source reads and ignore completions',()async{
    final block=Completer<Uint8List>();
    final source=_FakeProtectedSource((_)=>block.future);
    addTearDown(source.close);
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    final reading=controller.load(const MediaByteRange(start:0,length:3));
    controller.reset();
    expect(source.cancellations,1);
    controller.dispose();
    expect(source.cancellations,2);
    block.complete(Uint8List.fromList([2,3,4]));
    await reading;
    expect(controller.state,isA<MediaRangeIdle>());
  });

  test('RC117 source close emits a safe signal and UI closes without stale bytes',()async{
    final source=_FakeProtectedSource((_)async=>Uint8List.fromList([4]));
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    addTearDown(controller.dispose);
    await controller.load(const MediaByteRange(start:0,length:1));
    expect(controller.state,isA<MediaRangeReady>());
    await source.close();
    expect(controller.state,isA<MediaRangeIdle>());
    final result=await ReadMediaRangeUseCase(source)(
      const MediaByteRange(start:0,length:1));
    expect(result,isA<MediaReadFailed>());
    expect((result as MediaReadFailed).failure.kind,
      MediaReadFailureKind.sessionChanged);
  });
}
