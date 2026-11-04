/// A request for a bounded, server-confirmed segment of one protected asset.
///
/// There is intentionally no URL, auth token, Dio, Flutter or Backend contract
/// type in this value object. The selected MediaByteSource owns the session.
final class MediaByteRange {
  const MediaByteRange({required this.start,required this.length});
  final int start;
  final int length;
  static const int maxLength=512*1024;

  bool get isValid =>
      start>=0 && length>0 && length<=maxLength &&
      start<=0x7fffffffffffffff-length;
}
