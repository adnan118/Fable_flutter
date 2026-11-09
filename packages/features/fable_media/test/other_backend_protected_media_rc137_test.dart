import 'dart:async';
import 'dart:typed_data';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

class _OutsideTransport implements OtherBackendVerifiedMediaTransport {
  _OutsideTransport({this.delay});
  final Completer<MediaByteChunk>? delay;
  final _events=StreamController<MediaSessionInvalidation>.broadcast(sync:true);
  bool active=true,cancelled=false,closed=false;
  @override Stream<MediaSessionInvalidation> get invalidations=>_events.stream;
  @override bool get isAuthorized=>active;
  @override void cancelPendingReads(){cancelled=true;}
  @override Future<void> close()async{closed=true;await _events.close();}
  @override Future<MediaByteChunk> readVerifiedRange(MediaByteRange range) async{
    if(delay!=null)return delay!.future;
    return MediaByteChunk(start:range.start,totalLength:1000,mimeType:'video/mp4',
      bytes:Uint8List.fromList(List<int>.filled(range.length,42)));
  }
  void revoke(){active=false;_events.add(MediaSessionInvalidation.playbackEnded);}
}
OtherBackendMediaDeclaration _declaration({
  MediaEncryptionTier tier=MediaEncryptionTier.local,
  bool licensed=false,bool private=true,
})=>OtherBackendMediaDeclaration(
  backendId:'custom_backend_1',encryptionTier:tier,
  authorizationDeadline:DateTime.now().toUtc().add(const Duration(minutes:3)),
  privateByteStorage:private,everyRangeAuthorized:true,
  noPublicDownloadUrl:true,clientReceivesNoKey:true,
  contractVerified:true,licensedDrmVerified:licensed,
);
void main(){
  test('RC137 external adapter needs its own verified private/auth contract',(){
    expect(()=>_declaration(private:false),throwsStateError);
    expect(()=>_declaration(tier:MediaEncryptionTier.drm),throwsStateError);
    expect(_declaration(tier:MediaEncryptionTier.drm,licensed:true)
      .encryptionTier,MediaEncryptionTier.drm);
  });
  test('RC137 OTHER Backend reads through typed source; no Fable endpoint assumed',() async{
    final transport=_OutsideTransport();
    final source=OtherBackendProtectedMediaSource(
      declaration:_declaration(),transport:transport,identityRevision:()=>1);
    expect(source.backendId,'custom_backend_1');
    expect(source.encryptionTier,MediaEncryptionTier.local);
    final bytes=await source.read(MediaByteRange(start:2,length:5));
    expect(bytes.length,5);
    await source.close();expect(transport.closed,true);
  });
  test('RC137 identity switching discards delayed external reply',() async{
    final delayed=Completer<MediaByteChunk>();
    final transport=_OutsideTransport(delay:delayed);
    var revision=1;
    final source=OtherBackendProtectedMediaSource(
      declaration:_declaration(),transport:transport,identityRevision:()=>revision);
    final future=source.readChunk(MediaByteRange(start:0,length:2));
    revision=2;
    delayed.complete(MediaByteChunk(start:0,totalLength:10,mimeType:'audio/mp4',
      bytes:Uint8List.fromList([1,2])));
    await expectLater(future,throwsA(isA<MediaReadFailure>()));
    expect(source.isActive,false);
    await source.close();
  });
  test('RC137 backend revocation immediately invalidates source',() async{
    final transport=_OutsideTransport();
    final source=OtherBackendProtectedMediaSource(
      declaration:_declaration(),transport:transport,identityRevision:()=>1);
    transport.revoke();
    expect(source.isActive,false);
    expect(transport.cancelled,true);
    await expectLater(source.readChunk(MediaByteRange(start:0,length:1)),
      throwsA(isA<MediaReadFailure>()));
    await source.close();
  });
  test('RC137 outside Backend invalid Range metadata is never published',() async{
    final delayed=Completer<MediaByteChunk>();
    final transport=_OutsideTransport(delay:delayed);
    final source=OtherBackendProtectedMediaSource(
      declaration:_declaration(),transport:transport,identityRevision:()=>1);
    final future=source.readChunk(MediaByteRange(start:20,length:3));
    delayed.complete(MediaByteChunk(start:19,totalLength:100,mimeType:'video/mp4',
      bytes:Uint8List.fromList([1,2,3])));
    await expectLater(future,throwsA(isA<MediaReadFailure>()));
    expect(source.isActive,false);
    await source.close();
  });
}
