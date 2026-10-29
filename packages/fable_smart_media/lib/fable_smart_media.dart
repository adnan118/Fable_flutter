export 'fable_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';
import 'package:fable_design_system/fable_design_system.dart';

enum FableMediaKind {raster,animatedRaster,svg,lottie,video,unknown}
class FableMediaDescriptor {
  const FableMediaDescriptor({required this.source,this.mimeType,this.kind,this.blurHash,
    this.trustedRemoteVector=false,this.asset=false});
  final String source;
  final String? mimeType,blurHash;
  final FableMediaKind? kind;
  final bool trustedRemoteVector,asset;
}
class FableMediaResolver {
  static FableMediaKind resolve(FableMediaDescriptor desc){
    if(desc.kind!=null)return desc.kind!;
    switch(desc.mimeType?.split(';').first.trim().toLowerCase()){
      case 'image/svg+xml':return FableMediaKind.svg;
      case 'application/json':case 'application/vnd.lottie+json':return FableMediaKind.lottie;
      case 'image/gif':case 'image/apng':return FableMediaKind.animatedRaster;
      case 'video/mp4':case 'application/vnd.apple.mpegurl':case 'application/x-mpegurl':return FableMediaKind.video;
      case 'image/jpeg':case 'image/png':case 'image/webp':case 'image/avif':return FableMediaKind.raster;
    }
    final path=Uri.tryParse(desc.source)?.path.toLowerCase()??'';
    if(path.endsWith('.svg'))return FableMediaKind.svg;
    if(path.endsWith('.json')||path.endsWith('.lottie'))return FableMediaKind.lottie;
    if(path.endsWith('.gif')||path.endsWith('.apng'))return FableMediaKind.animatedRaster;
    if(path.endsWith('.mp4')||path.endsWith('.m3u8'))return FableMediaKind.video;
    if(RegExp(r'\.(jpg|jpeg|png|webp|avif)$').hasMatch(path))return FableMediaKind.raster;
    return FableMediaKind.unknown;
  }
  static bool isSafeNetworkSource(String source){final url=Uri.tryParse(source);
    return url!=null && url.scheme=='https' && url.host.isNotEmpty && url.userInfo.isEmpty;
  }
}
class FableMedia extends StatelessWidget {
  const FableMedia({super.key,required this.descriptor,this.fit=BoxFit.cover,this.semanticsLabel,
    this.onVideoTap});
  final FableMediaDescriptor descriptor;final BoxFit fit;final String? semanticsLabel;
  final VoidCallback? onVideoTap;
  @override Widget build(BuildContext context){
    final d=descriptor,kind=FableMediaResolver.resolve(d);
    if(!d.asset&&!FableMediaResolver.isSafeNetworkSource(d.source))return _error();
    switch(kind){
      case FableMediaKind.raster:
      case FableMediaKind.animatedRaster:
        if(d.asset)return Image.asset(d.source,fit:fit,semanticLabel:semanticsLabel,errorBuilder:(_,__,___)=>_error());
        return CachedNetworkImage(imageUrl:d.source,fit:fit,
          placeholder:(context,url)=>_placeholder(),errorWidget:(context,url,e)=>_error());
      case FableMediaKind.svg:
        if(d.asset)return SvgPicture.asset(d.source,fit:fit,semanticsLabel:semanticsLabel);
        if(!d.trustedRemoteVector)return _error();
        return SvgPicture.network(d.source,fit:fit,semanticsLabel:semanticsLabel);
      case FableMediaKind.lottie:
        if(!d.asset&&!d.trustedRemoteVector)return _error();
        return d.asset?Lottie.asset(d.source,fit:fit):Lottie.network(d.source,fit:fit);
      case FableMediaKind.video:
        return InkWell(onTap:onVideoTap,child:Center(child:Icon(Icons.play_circle_outline,
          size:54,color:Theme.of(context).colorScheme.primary)));
      case FableMediaKind.unknown:return _error();
    }
  }
  Widget _placeholder(){
    final hash=descriptor.blurHash;
    if(hash!=null && hash.isNotEmpty){
      return BlurHash(hash:hash,duration:const Duration(milliseconds:150));
    }
    return const FableSkeleton(height:120);
  }
  Widget _error()=>const Center(child:Icon(Icons.broken_image_outlined,semanticLabel:'Media unavailable'));
}
