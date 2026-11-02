import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'offline_sync_engine.dart';

/// Executes the same verified foreground sync on launch/resume.
/// No background guarantee, and no work when the Backend identity is absent.
final class FableForegroundSyncObserver extends WidgetsBindingObserver {
  FableForegroundSyncObserver({required this.engine,required this.executor}){
    WidgetsBinding.instance.addObserver(this);
  }
  final FableOfflineSyncEngine engine;
  final FableOfflineCommandExecutor executor;
  bool _running=false;
  bool _closed=false;
  Future<int> onAppOpened()async{
    if(_closed||_running)return 0;
    _running=true;
    try{return await engine.flush(executor);}
    finally{_running=false;}
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed)unawaited(onAppOpened());
  }
  void dispose(){_closed=true;WidgetsBinding.instance.removeObserver(this);}
}

/// Opt-in platform scheduling. The host must supply a top-level
/// @pragma('vm:entry-point') dispatcher that bootstraps its verified Backend
/// and authenticates the exact account from secure storage IN THAT ISOLATE.
/// Workers MUST NOT assume the foreground isolate's credentials survive.
final class FableBestEffortWorkScheduler {
  FableBestEffortWorkScheduler({required this.taskIdentifier,
    String? uniqueName}):uniqueName=uniqueName??taskIdentifier;
  final String taskIdentifier,uniqueName;
  bool _initialized=false;
  static final _identifier=RegExp(r'^[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)+$');

  Future<void> initialize(void Function() callbackDispatcher)async{
    if(!_identifier.hasMatch(taskIdentifier))
      throw ArgumentError('Task identifier must match registered iOS identifier');
    await Workmanager().initialize(callbackDispatcher);
    _initialized=true;
  }
  Future<void> schedule({Duration frequency=const Duration(hours:6)})async{
    if(!_initialized)throw StateError('Initialize verified background dispatcher first');
    if(frequency<const Duration(minutes:15))
      throw ArgumentError('Background periodic work cannot be scheduled below 15 minutes');
    await Workmanager().registerPeriodicTask(uniqueName,taskIdentifier,
      frequency:frequency,
      constraints:Constraints(networkType:NetworkType.connected),
      existingWorkPolicy:ExistingPeriodicWorkPolicy.update,
      backoffPolicy:BackoffPolicy.exponential,
      backoffPolicyDelay:const Duration(minutes:5),
    );
  }
  Future<void> cancel()async{
    if(!_initialized)return;
    await Workmanager().cancelByUniqueName(uniqueName);
  }
}

/// Useful for a host callback dispatcher. Return false when credentials,
/// Backend capability, scope or network are not verifiable. A worker can't
/// invent an operation just to report success to the scheduler.
Future<bool> runFableVerifiedBackgroundSync({
  required FableOfflineSyncEngine? engine,
  required FableOfflineCommandExecutor? executor,
})async{
  if(engine==null||executor==null)return false;
  try{
    await engine.flush(executor);
    return true;
  }catch(_){
    return false;
  }
}
