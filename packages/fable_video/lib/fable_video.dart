import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:fable_smart_media/fable_smart_media.dart';

/// Progressive/HLS playback through the native platform backend. Does NOT claim
/// persistent HLS segment caching, offline DRM, ABR policy overrides or prefetch queues.
class FableVideo extends StatefulWidget {
  const FableVideo({super.key,required this.url,this.poster,this.autoplay=false});
  final Uri url;final FableMediaDescriptor? poster;final bool autoplay;
  @override State<FableVideo> createState()=>_FableVideoState();
}
class _FableVideoState extends State<FableVideo> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Object? _error;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_load();}
  Future<void> _load()async{
    if(widget.url.scheme!='https'){if(mounted)setState(()=>_error=StateError('HTTPS video required'));return;}
    final controller=VideoPlayerController.networkUrl(widget.url);
    _controller=controller;
    try{
      await controller.initialize();
      if(widget.autoplay)await controller.play();
      if(mounted)setState((){});
    }catch(e){if(mounted)setState(()=>_error=e);}
  }
  @override void didUpdateWidget(covariant FableVideo old){super.didUpdateWidget(old);
    if(widget.url!=old.url){_controller?.dispose();_controller=null;_error=null;_load();}
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state!=AppLifecycleState.resumed)_controller?.pause();
  }
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_controller?.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final c=_controller;
    if(_error!=null)return const Center(child:Text('Video unavailable'));
    if(c==null||!c.value.isInitialized){
      if(widget.poster!=null)return FableMedia(descriptor:widget.poster!);
      return const Center(child:CircularProgressIndicator());
    }
    return AspectRatio(aspectRatio:c.value.aspectRatio,child:Stack(fit:StackFit.expand,children:[
      VideoPlayer(c),Align(alignment:Alignment.bottomCenter,child:VideoProgressIndicator(c,allowScrubbing:true)),
      Center(child:IconButton(iconSize:52,tooltip:c.value.isPlaying?'Pause':'Play',
        onPressed:()async{if(c.value.isPlaying){await c.pause();}else{await c.play();}if(mounted)setState((){});},
        icon:Icon(c.value.isPlaying?Icons.pause_circle:Icons.play_circle,color:Colors.white)))
    ]));
  }
}
