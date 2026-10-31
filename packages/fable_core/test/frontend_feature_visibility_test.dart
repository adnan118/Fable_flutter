import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:fable_core/fable_core.dart';
import 'package:flutter_test/flutter_test.dart';

String _hash(Object value)=>sha256.convert(utf8.encode(jsonEncode(value))).toString();
FableContract build({bool conflicting=false,bool stale=false,bool legacy=false}) {
  const digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final setup=<String,dynamic>{
    'schemaVersion':1,'kind':'fable.frontend-setup-decisions',
    'projectId':'my-project',
    'steps':<Object>[],
    'decisions':<String,dynamic>{
      'frontendFeatures':{
        'schemaVersion':1,'source':'backend-installed-capabilities',
        'enabled':['auth','profile','localization','access_control'],
        'disabled':conflicting?['auth','notifications','payments']:['notifications','payments'],
      }
    },
  };
  final handoff=<String,dynamic>{
    'schemaVersion':1,'kind':'fable.flutter-handoff','client':'flutter',
    'backend':{'project':{'id':'my-project','name':'my-app'},'contractHash':digest},
    'selection':{'mode':'advisory','features':null},
    if(!legacy)'frontendSetup':{
      ...setup,
      if(stale)'projectId':'other-project'
    },
  };
  handoff['manifestHash']=_hash(handoff);
  final contract=<String,dynamic>{
    'contractHash':digest,'project':{'id':'my-project','name':'my-app'},
    if(!legacy)'core':{'frontendSetup':setup},
  };
  return FableContract.fromMaps(handoff,contract,{'paths':<String,Object>{}});
}

void main(){
  test('Backend decides visibility of home and notification destinations',(){
    final c=build();
    expect(c.isFeatureAvailable('auth'),true);
    expect(c.isFeatureAvailable('access_control'),true);
    expect(c.isFeatureAvailable('payments'),false);
    expect(c.isFeatureAvailable('notifications'),false);
    expect(c.backendVisibleFeatureIds,contains('profile'));
  });
  test('Inconsistent or stale handoff does not render disabled features',(){
    expect(()=>build(conflicting:true),throwsFormatException);
    expect(()=>build(stale:true),throwsFormatException);
  });
  test('Legacy contract does not fabricate a feature inventory',(){
    final c=build(legacy:true);
    expect(c.backendVisibleFeatureIds,isNull);
    expect(c.isFeatureAvailable('notifications'),true);
  });
}
