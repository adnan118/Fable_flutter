import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fable_media/fable_media.dart';

class _FakeByteSource implements MediaByteSource {
  _FakeByteSource(this.readBody);
  Future<Uint8List> Function(MediaByteRange) readBody;
  int reads=0;
  @override Future<Uint8List> read(MediaByteRange range)async{
    reads++;
    return readBody(range);
  }
}

void main(){
  test('RC114 rejects invalid range without dispatching to backend',()async{
    final source=_FakeByteSource((_)async=>Uint8List.fromList([4]));
    final read=ReadMediaRangeUseCase(source);
    for(final range in [
      const MediaByteRange(start:-1,length:2),
      const MediaByteRange(start:0,length:0),
      const MediaByteRange(start:0,length:524289),
      const MediaByteRange(start:0x7fffffffffffffff,length:3),
    ]){
      final result=await read(range);
      expect(result,isA<MediaReadFailed>());
      expect((result as MediaReadFailed).failure.kind,
        MediaReadFailureKind.invalidInput);
    }
    expect(source.reads,0);
  });
  test('RC114 returns typed immutable result without leaking source buffer',()async{
    final raw=Uint8List.fromList([9,8,7]);
    final source=_FakeByteSource((_)async=>raw);
    final result=await ReadMediaRangeUseCase(source)(
      const MediaByteRange(start:0,length:3));
    expect(result,isA<MediaReadSuccess>());
    final success=result as MediaReadSuccess;
    raw[0]=42;
    expect(success.bytes,[9,8,7]);
    final exposed=success.bytes;
    exposed[1]=55;
    expect(success.bytes,[9,8,7]);
    expect(success.length,3);
    expect(source.reads,1);
  });
  test('RC114 truncated or empty data never looks like valid success',()async{
    for(final payload in [Uint8List(0),Uint8List.fromList([1,2,3,4])]){
      final source=_FakeByteSource((_)async=>payload);
      final result=await ReadMediaRangeUseCase(source)(
        const MediaByteRange(start:0,length:3));
      expect(result,isA<MediaReadFailed>());
      expect((result as MediaReadFailed).failure.kind,
        MediaReadFailureKind.invalidResponse);
    }
  });
  test('RC114 does not silently turn typed permission failure into empty state',()async{
    final source=_FakeByteSource((_)async=>
      throw const MediaReadFailure(MediaReadFailureKind.forbidden));
    final result=await ReadMediaRangeUseCase(source)(
      const MediaByteRange(start:0,length:3));
    expect(result,isA<MediaReadFailed>());
    final failure=(result as MediaReadFailed).failure;
    expect(failure.kind,MediaReadFailureKind.forbidden);
    expect(failure.retryable,false);
  });
  test('RC114 transport faults are stable typed error without raw secret text',()async{
    final source=_FakeByteSource((_)async=>
      throw StateError('secret Authorization Bearer leaked error'));
    final result=await ReadMediaRangeUseCase(source)(
      const MediaByteRange(start:0,length:3));
    final failure=(result as MediaReadFailed).failure;
    expect(failure.kind,MediaReadFailureKind.unknown);
    expect(failure.toString(),isNot(contains('secret')));
    expect(failure.toString(),isNot(contains('Bearer')));
  });
  test('RC114 only offline/timeout/server down are automatically retryable',(){
    for(final reason in MediaReadFailureKind.values){
      final retryable=const {
        MediaReadFailureKind.offline,
        MediaReadFailureKind.timedOut,
        MediaReadFailureKind.serverUnavailable,
      }.contains(reason);
      expect(MediaReadFailure(reason).retryable,retryable);
    }
  });
  test('RC114 controller exposes typed loading->ready without transport imports',()async{
    final completion=Completer<Uint8List>();
    final source=_FakeByteSource((_)=>completion.future);
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    addTearDown(controller.dispose);
    final history=<Type>[];
    controller.addListener(()=>history.add(controller.state.runtimeType));
    final pending=controller.load(const MediaByteRange(start:0,length:3));
    expect(controller.state,isA<MediaRangeLoading>());
    expect((controller.state as MediaRangeLoading).refreshing,false);
    completion.complete(Uint8List.fromList([2,4,6]));
    await pending;
    expect(controller.state,isA<MediaRangeReady>());
    expect((controller.state as MediaRangeReady).bytes,[2,4,6]);
    expect(history,[MediaRangeLoading,MediaRangeReady]);
  });
  test('RC114 controller prevents duplicate loads and stale UI after reset',()async{
    final completion=Completer<Uint8List>();
    final source=_FakeByteSource((_)=>completion.future);
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    addTearDown(controller.dispose);
    final pending=controller.load(const MediaByteRange(start:0,length:3));
    await controller.load(const MediaByteRange(start:0,length:3));
    expect(source.reads,1);
    controller.reset();
    completion.complete(Uint8List.fromList([1,2,3]));
    await pending;
    expect(controller.state,isA<MediaRangeIdle>());
  });
  test('RC114 controller ignores late requests after dispose',()async{
    final completion=Completer<Uint8List>();
    final source=_FakeByteSource((_)=>completion.future);
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    final pending=controller.load(const MediaByteRange(start:0,length:3));
    controller.dispose();
    completion.complete(Uint8List.fromList([1,2,3]));
    await pending;
    expect(controller.state,isA<MediaRangeIdle>());
  });
  test('RC114 typed failure feeds presentation without JSON or error strings',()async{
    final source=_FakeByteSource((_)async=>
      throw const MediaReadFailure(MediaReadFailureKind.unauthenticated));
    final controller=MediaRangeController(ReadMediaRangeUseCase(source));
    addTearDown(controller.dispose);
    await controller.load(const MediaByteRange(start:0,length:3));
    expect(controller.state,isA<MediaRangeFailureState>());
    expect((controller.state as MediaRangeFailureState).reason,
      MediaReadFailureKind.unauthenticated);
  });
}
