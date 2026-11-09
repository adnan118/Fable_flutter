import 'package:flutter_test/flutter_test.dart';
import 'package:fable_core/fable_core.dart';
import '../lib/src/generated/feature_registry.dart';

const _digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
FableContract project({
  Set<String>? enabled,
  Map<String,FableOperation>? operations,
  bool legacy=false,
}) => FableContract(
  contractHash:_digest,
  projectName:'stage4-verified-project',
  selectionMode:'advisory',
  featureIds:installedFeatures.map((feature)=>feature.id).toSet(),
  operations:operations??{
    'auth.login':const FableOperation('auth.login','POST','/auth/login',_digest,
      requiresAuth:false,enforceAuth:true),
    'account.me':const FableOperation('account.me','GET','/account/me',_digest,
      requiresAuth:true,enforceAuth:true),
    'notifications.inbox':const FableOperation('notifications.inbox','GET',
      '/notifications/inbox',_digest,requiresAuth:true,enforceAuth:true),
    'notifications.read':const FableOperation('notifications.read','POST',
      '/notifications/{id}/read',_digest,requiresAuth:true,enforceAuth:true),
    'languages.list':const FableOperation('languages.list','GET','/languages',
      _digest,requiresAuth:false,enforceAuth:true),
    'content.page.read':const FableOperation('content.page.read','GET',
      '/content/pages/{slug}',_digest,requiresAuth:false,enforceAuth:true),
    'content.publicChanges':const FableOperation('content.publicChanges','GET',
      '/content/pages/changes',_digest,requiresAuth:false,enforceAuth:true),
    'content.page.accept':const FableOperation('content.page.accept','POST',
      '/content/pages/{pageId}/accept',_digest,requiresAuth:true,enforceAuth:true),
  },
  frontendSetup:legacy?null:{
    'decisions':{'frontendFeatures':{'enabled':
      (enabled??{'auth','profile','notifications','localization','content'}).toList()}}
  },
);
void main(){
  test('RC142 all original 17 Dart capabilities stay installed',(){
    final ids=installedFeatures.map((f)=>f.id).toSet();
    expect(ids.length,17);
    expect(ids,containsAll({'auth','profile','notifications','media',
      'localization','support','social','biometrics','realtime','deeplinks',
      'messaging','location','payments','offline','analytics','content','access_control'}));
  });
  test('RC142 only five actual Fable consumer screens are advertised',(){
    final bound=project();
    final runnable=installedFeatures.where((f)=>f.canLaunchFable(bound))
      .map((f)=>f.id).toSet();
    expect(runnable,{'auth','profile','notifications','localization','content'});
    expect(bound.isFeatureAvailable('media'),false);
    expect(installedFeatures.firstWhere((f)=>f.id=='payments')
      .canLaunchFable(bound),false);
  });
  test('RC142 missing Backend decision never means enabled on a legacy export',(){
    final legacy=project(legacy:true);
    expect(legacy.backendVisibleFeatureIds,isNull);
    expect(installedFeatures.where((f)=>f.canLaunchFable(legacy)),isEmpty);
    expect(legacy.isFeatureAvailable('auth'),false);
    expect(legacy.isFeatureAvailable('payments'),false);
  });
  test('RC142 Backend-disabled feature stays hidden despite installed package',(){
    final decisions=project(enabled:{'auth','profile','notifications'});
    final visible=installedFeatures.where((f)=>f.canLaunchFable(decisions))
      .map((f)=>f.id).toSet();
    expect(visible,{'auth','profile','notifications'});
    expect(decisions.isFeatureAvailable('localization'),false);
  });
  test('RC142 a malformed operation cannot unlock a capability screen',(){
    final good=project();
    final wrong={...good.operations,
      'auth.login':const FableOperation('auth.login','GET','/auth/login',_digest,
        requiresAuth:false,enforceAuth:true),
      'account.me':const FableOperation('account.me','POST','/account/me',_digest,
        requiresAuth:true,enforceAuth:true),
      'notifications.read':const FableOperation('notifications.read','GET',
        '/notifications/{id}/read',_digest,requiresAuth:true,enforceAuth:true),
      'languages.list':const FableOperation('languages.list','POST','/languages',_digest,
        requiresAuth:false,enforceAuth:true),
      'content.page.accept':const FableOperation('content.page.accept','GET',
        '/content/pages/{pageId}/accept',_digest,requiresAuth:true,enforceAuth:true),
    };
    final broken=project(operations:wrong);
    expect(installedFeatures.where((f)=>f.canLaunchFable(broken)),isEmpty);
  });
}
