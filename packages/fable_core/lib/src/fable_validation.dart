/// Client validation is for UX only; server remains the security authority.
class FableValidation {
  const FableValidation._();
  static String? requiredText(String? value, {int min=1, int max=500}) {
    final v=value?.trim() ?? '';
    if(v.isEmpty) return 'required';
    if(v.runes.length<min) return 'too_short';
    if(v.runes.length>max) return 'too_long';
    return null;
  }
  static String? email(String? value) {
    final base=requiredText(value,max:254);
    if(base!=null) return base;
    final v=value!.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v) ? null : 'invalid_email';
  }
  static String? number(String? value, {double? min, double? max}) {
    if(value==null || value.trim().isEmpty) return 'required';
    final n=double.tryParse(value.trim());
    if(n==null || !n.isFinite) return 'invalid_number';
    if(min!=null && n<min) return 'below_min';
    if(max!=null && n>max) return 'above_max';
    return null;
  }
  /// Convert stable validation codes to end-user text in the requested locale.
  /// Applications can override these strings in their own localization layer.
  static String? message(String? code, {String languageCode = 'en'}) {
    if (code == null) return null;
    const ar = <String, String>{
      'required': 'هذا الحقل مطلوب',
      'too_short': 'القيمة أقصر من الحد المسموح',
      'too_long': 'القيمة أطول من الحد المسموح',
      'invalid_email': 'البريد الإلكتروني غير صالح',
      'invalid_number': 'يرجى إدخال رقم صحيح',
      'below_min': 'القيمة أقل من الحد المسموح',
      'above_max': 'القيمة أكبر من الحد المسموح',
    };
    const en = <String, String>{
      'required': 'This field is required',
      'too_short': 'The value is too short',
      'too_long': 'The value is too long',
      'invalid_email': 'Enter a valid email address',
      'invalid_number': 'Enter a valid number',
      'below_min': 'Value is below the minimum',
      'above_max': 'Value exceeds the maximum',
    };
    // Do not render an untrusted backend error string verbatim.
    return languageCode == 'ar'
        ? (ar[code] ?? 'قيمة غير صالحة')
        : (en[code] ?? 'Invalid value');
  }

  static Map<String,String> parseBackendFieldErrors(dynamic details) {
    final fields=<String,String>{};
    if(details is Map && details['fields'] is Map){
      for(final entry in (details['fields'] as Map).entries){
        if(entry.key is String && entry.value is String) fields[entry.key as String]=entry.value as String;
      }
    }
    return fields;
  }
}
