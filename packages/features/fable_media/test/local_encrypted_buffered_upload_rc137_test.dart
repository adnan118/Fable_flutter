import 'dart:io';
import 'package:dio/dio.dart';
import 'package:fable_core/fable_core.dart';
import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

const _id='123e4567-e89b-42d3-a456-426614174000';
class _Gateway implements BackendApiGateway {
  Object? lastBody;
  String? lastOperation;
  @override Future<Response<dynamic>> execute(String operationId,{
    Map<String,dynamic>? path,Map<String,dynamic>? query,Object? body,
    CancelToken? cancelToken,String? ifMatch,
  })async{
    lastOperation=operationId;lastBody=body;
    return Response<dynamic>(requestOptions:RequestOptions(path:'/media'),
      data:{'success':true,'data':{
        'id':_id,'access':{'type':'protected',
          'url':null,'playbackEndpoint':'/media/$_id/playback'},
      }});
  }
  @override void dispose(){}
}
class _Policy implements MediaMetadataReadPort {
  _Policy(this.tier,{this.verified=true,this.max=1024});
  final MediaEncryptionTier tier;
  final bool verified;
  final int max;
  @override Future<MediaAssetMetadata> metadata(String id)async=>
      throw UnimplementedError();
  @override Future<MediaRuntimeCapabilities> runtimeContract()async=>
      MediaRuntimeCapabilities(schemaVersion:12,
        driver:MediaStorageDriver.local,maxUploadBytes:max,
        maxParallelParts:1,acceptedMimeTypes:['image/png'],
        resumableLargeUpload:false,directPresignedMultipart:false,
        serverAuthoritativeProgress:true,
        encryptionTier:tier,encryptionTierVerified:verified);
}
FableContract _catalog()=>FableContract(
  contractHash:List.filled(64,'a').join(),
  operations:{'media.upload':FableOperation(
    'media.upload','POST','/media',List.filled(64,'b').join(),
    requiresAuth:true,enforceAuth:true)},
  featureIds:const {'media'},projectName:'rc137-local',
  selectionMode:'explicit',
);
void main(){
  test('RC137 Fable LOCAL only uses the verified buffered POST operation',()async{
    final directory=await Directory.systemTemp.createTemp('fable-local-upload-');
    final file=File('${directory.path}/tiny.png');
    await file.writeAsBytes([137,80,78,71]);
    final gateway=_Gateway();
    final uploader=FableLocalEncryptedBufferedUploader(
      gateway:gateway,catalog:_catalog(),
      runtime:_Policy(MediaEncryptionTier.local),
      identityRevision:()=>1,isSessionCurrent:()=>true);
    try {
      final id=await uploader.upload(file:file,kind:'IMAGE',mimeType:'image/png');
      expect(id,_id);expect(gateway.lastOperation,'media.upload');
      expect(gateway.lastBody,isA<FormData>());
      final form=gateway.lastBody as FormData;
      expect(form.fields.any((entry)=>entry.key=='kind'&&entry.value=='IMAGE'),true);
      expect(form.files.length,1);
    } finally {await directory.delete(recursive:true);}
  });
  test('RC137 stops if backend did not verify LOCAL tier',()async{
    final gateway=_Gateway();
    final uploader=FableLocalEncryptedBufferedUploader(
      gateway:gateway,catalog:_catalog(),
      runtime:_Policy(MediaEncryptionTier.none),
      identityRevision:()=>1,isSessionCurrent:()=>true);
    final dir=await Directory.systemTemp.createTemp();
    final file=File('${dir.path}/x.png');await file.writeAsBytes([1,2]);
    try{
      await expectLater(uploader.upload(file:file,kind:'IMAGE',mimeType:'image/png'),
        throwsStateError);
      expect(gateway.lastOperation,isNull);
    }finally{await dir.delete(recursive:true);}
  });
}
