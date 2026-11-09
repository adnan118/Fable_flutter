import 'package:fable_media/fable_media.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String,Object?> runtime(String tier,{bool? drmEnabled,
    bool? encryptedAtRest,bool? requiresLicense}) => {
  'schemaVersion':12,'driver':'local','storagePolicy':'OPTIMIZED_PRIMARY',
  'protection':{
    'enabled':true,'forcePrivate':true,'directPublicUrls':false,
    'directDownload':false,'requireAuthorizationGrant':true,
    'encryptionTier':tier,
    'encryption':{
      'tier':tier,'atRestEncrypted':encryptedAtRest??tier=='LOCAL',
      'requiresExternalLicense':requiresLicense??tier=='DRM',
      'clientSideKeyRequired':false,'algorithm':tier=='LOCAL'?'AES-256-GCM':tier=='DRM'?'CMAF-CBCS':'NONE',
      'localUploadStrategy':tier=='LOCAL'?'BUFFERED_PROXY_ONLY':null,
    },
    'drm':{'enabled':drmEnabled??tier=='DRM','queryTokensAllowed':false},
  },
  'limits':{'maxUploadBytes':20971520,'maxParallelParts':1},
  'features':{'resumableLargeUpload':tier!='LOCAL',
    'directPresignedMultipart':false,'serverAuthoritativeProgress':true,
    'signedS3Downloads':false},
  'acceptedMimeTypes':['image/jpeg','video/mp4'],
};
void main(){
  test('RC136 presents all three levels and keeps secrets entirely on Backend',(){
    expect(MediaEncryptionTier.values.length,3);
    for(final level in MediaEncryptionTier.values){
      expect(level.labelAr.isNotEmpty,true);
      expect(level.explanationAr.isNotEmpty,true);
      expect(level.clientReceivesEncryptionKey,false);
    }
  });
  test('RC136 validates honest NONE / LOCAL / DRM Backend contract',(){
    for(final level in ['NONE','LOCAL','DRM']){
      final selected=decodeFableRuntimeCapabilities(runtime(level));
      expect(selected.encryptionTier.name.toUpperCase(),level);
      expect(selected.encryptionTierVerified,true);
    }
  });
  test('RC136 rejects dishonest encryption claims and unknown tiers',(){
    expect(()=>decodeFableRuntimeCapabilities(runtime('LOCAL',
      encryptedAtRest:false)),throwsFormatException);
    expect(()=>decodeFableRuntimeCapabilities(runtime('LOCAL',
      requiresLicense:true)),throwsFormatException);
    expect(()=>decodeFableRuntimeCapabilities(runtime('DRM',
      drmEnabled:false)),throwsFormatException);
    expect(()=>decodeFableRuntimeCapabilities(runtime('WRONG')),
      throwsFormatException);
  });
  test('RC136 legacy runtime is not claimed as verified LOCAL',(){
    final old=runtime('NONE');
    final p=Map<String,Object?>.from(old['protection'] as Map);
    p.remove('encryptionTier');p.remove('encryption');
    old['protection']=p;
    final selected=decodeFableRuntimeCapabilities(old);
    expect(selected.encryptionTier,MediaEncryptionTier.none);
    expect(selected.encryptionTierVerified,false);
  });
}
