import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

// ============================================================
//  الإعدادات العامة
// ============================================================
const String kBaseUrl = 'https://ysf3laa.github.io/Create-card/';

const FirebaseOptions kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyClMLZwXm2sHhVA6QIF_Qq_r6wMkWoZMoc',
  appId: '1:183579389817:web:afb7f82b6c70a1ed1149a8',
  messagingSenderId: '183579389817',
  projectId: 'birthday-card-ede5c',
  storageBucket: 'birthday-card-ede5c.firebasestorage.app',
  authDomain: 'birthday-card-ede5c.firebaseapp.com',
);

const Color kPrimary = Color(0xFFFF4757);
const Color kPrimaryLight = Color(0xFFFF6B81);

String buildShareLink(String id) {
  if (kIsWeb) {
    final u = Uri.base;
    return '${u.origin}${u.path}?id=$id';
  }
  return '$kBaseUrl?id=$id';
}

String? extractYoutubeId(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final m = RegExp(r'(?:youtu\.be\/|v\/|embed\/|watch\?v=|&v=)([^#&?]{11})')
      .firstMatch(url);
  return m?.group(1);
}

Uint8List? dataUrlToBytes(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  final i = dataUrl.indexOf(',');
  if (i == -1) return null;
  try {
    return base64Decode(dataUrl.substring(i + 1));
  } catch (_) {
    return null;
  }
}

/// ترجع Widget أو null لو مفيش صورة
Widget? dataImage(String? dataUrl, {BoxFit fit = BoxFit.cover}) {
  final b = dataUrlToBytes(dataUrl);
  if (b == null) return null;
  return Image.memory(b, fit: fit);
}

// ============================================================
//  نقطة البداية
// ============================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: kFirebaseOptions);
  final String? id = kIsWeb ? Uri.base.queryParameters['id'] : null;
  runApp(CardMakerApp(initialCardId: id));
}

class CardMakerApp extends StatelessWidget {
  const CardMakerApp({super.key, this.initialCardId});
  final String? initialCardId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'صانع البطاقات التفاعلية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
        useMaterial3: true,
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: (initialCardId != null && initialCardId!.isNotEmpty)
          ? ViewerFlow(cardId: initialCardId!)
          : const CreatorScreen(),
    );
  }
}

// ============================================================
//  شاشة الإنشاء
// ============================================================
class CreatorScreen extends StatefulWidget {
  const CreatorScreen({super.key});
  @override
  State<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends State<CreatorScreen> {
  final _name = TextEditingController();
  final _message = TextEditingController();
  final _youtube = TextEditingController();
  final _pin = TextEditingController();
  String _template = 'envelope';
  String? _imageDataUrl;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _message.dispose();
    _youtube.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  static String? _compress(Uint8List bytes) {
    final img = imglib.decodeImage(bytes);
    if (img == null) return null;
    const maxBytes = 800 * 1024;
    var dim = 1000;
    var q = 72;
    String encode() {
      final w = math.min(img.width, dim);
      final resized = imglib.copyResize(img, width: w);
      return base64Encode(imglib.encodeJpg(resized, quality: q));
    }
    var out = encode();
    while (out.length > maxBytes && q > 35) {
      q -= 12;
      out = encode();
    }
    while (out.length > maxBytes && dim > 320) {
      dim = (dim * 0.75).round();
      out = encode();
    }
    return 'data:image/jpeg;base64,$out';
  }

  Future<void> _pickImage() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (x == null) return;
      setState(() => _loading = true);
      final bytes = await x.readAsBytes();
      final result = await compute(_compress, bytes);
      if (!mounted) return;
      if (result == null) {
        _snack('❌ صيغة الصورة غير مدعومة، استخدم JPG أو PNG');
      } else {
        setState(() => _imageDataUrl = result);
        _snack('✅ تم ضغط الصورة (${(result.length / 1024).round()} KB)');
      }
    } catch (_) {
      if (mounted) _snack('❌ فشل اختيار الصورة');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final name = _name.text.trim();
    final message = _message.text.trim();
    final pin = _pin.text.trim();
    if (name.isEmpty || message.isEmpty) {
      _snack('⚠️ اكتب الاسم والرسالة الأول');
      return;
    }
    if (pin.isNotEmpty && (pin.length != 4 || int.tryParse(pin) == null)) {
      _snack('⚠️ رمز PIN لازم يكون 4 أرقام');
      return;
    }
    final payload = <String, dynamic>{
      'name': name,
      'message': message,
      'template': _template,
      'youtube': _youtube.text.trim(),
      'pin': pin,
      'image': _imageDataUrl ?? '',
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (jsonEncode(payload).length > 950000) {
      _snack('⚠️ حجم البيانات كبير، استخدم صورة أصغر');
      return;
    }
    setState(() => _loading = true);
    try {
      final ref =
          await FirebaseFirestore.instance.collection('cards').add(payload);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ShareScreen(link: buildShareLink(ref.id))),
      );
    } catch (e) {
      _snack('❌ خطأ أثناء الحفظ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openById() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فتح بطاقة'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'الصق الرابط أو الـ ID'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('فتح')),
        ],
      ),
    );
    if (res == null || res.isEmpty) return;
    final m = RegExp(r'id=([\w-]+)').firstMatch(res);
    final id = m?.group(1) ?? res;
    if (!mounted) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => ViewerFlow(cardId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final Widget? preview = dataImage(_imageDataUrl, fit: BoxFit.contain);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text('✨ صانع البطاقات التفاعلية'),
        actions: [
          IconButton(
            tooltip: 'فتح بطاقة بالرابط',
            icon: const Icon(Icons.link),
            onPressed: _openById,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFA8C0FF), Color(0xFF3F2B96)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _template,
                    decoration:
                        const InputDecoration(labelText: 'اختر القالب التفاعلي'),
                    items: const [
                      DropdownMenuItem(
                          value: 'envelope',
                          child: Text('💌 ظرف حب ثلاثي الأبعاد')),
                      DropdownMenuItem(
                          value: 'musicbox', child: Text('🎵 صندوق الموسيقى')),
                      DropdownMenuItem(
                          value: 'polaroid',
                          child: Text('📸 معرض ذكريات بولارويد')),
                    ],
                    onChanged: (v) =>
                        setState(() => _template = v ?? 'envelope'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'اسم المُهدى إليه'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _message,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(labelText: 'رسالتك الخاصة'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('اختيار صورة (اختياري)'),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: preview,
                    ),
                  ],
                  if (_template == 'musicbox') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _youtube,
                      decoration: const InputDecoration(
                          labelText: 'رابط موسيقى يوتيوب (اختياري)'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pin,
                    maxLength: 4,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'رمز PIN (اختياري - 4 أرقام)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: kPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: _loading ? null : _generate,
                    child: const Text('🚀 إنشاء ومشاركة البطاقة',
                        style: TextStyle(fontSize: 17)),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  شاشة المشاركة
// ============================================================
class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key, required this.link});
  final String link;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎉 تم الإنشاء')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.card_giftcard, size: 70, color: kPrimary),
              const SizedBox(height: 12),
              const Text('تم إنشاء بطاقتك بنجاح!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F2F6),
                  border: Border.all(color: kPrimary),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(link, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ تم نسخ الرابط')));
                },
                icon: const Icon(Icons.copy),
                label: const Text('نسخ الرابط'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('➕ إنشاء بطاقة جديدة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  تحميل البطاقة + بوابة PIN
// ============================================================
class ViewerFlow extends StatefulWidget {
  const ViewerFlow({super.key, required this.cardId});
  final String cardId;
  @override
  State<ViewerFlow> createState() => _ViewerFlowState();
}

class _ViewerFlowState extends State<ViewerFlow> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('cards')
          .doc(widget.cardId)
          .get();
      if (!mounted) return;
      if (!snap.exists) {
        setState(() => _error = 'البطاقة غير موجودة أو تم حذفها');
        return;
      }
      final data = snap.data()!;
      final pin = (data['pin'] ?? '') as String;
      if (pin.isNotEmpty) {
        final ok = await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => PinScreen(pin: pin)));
        if (ok == true && mounted) {
          setState(() => _data = data);
        } else if (mounted) {
          setState(() => _error = 'تم إلغاء فتح البطاقة');
        }
      } else {
        setState(() => _data = data);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'خطأ في التحميل: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('بطاقة')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 60, color: kPrimary),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('رجوع'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_data == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: kPrimary)));
    }
    return ViewerScreen(data: _data!);
  }
}

class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.pin});
  final String pin;
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _input = '';
  bool _err = false;

  void _enter(String n) {
    if (_input.length >= 4) return;
    setState(() {
      _input += n;
      _err = false;
    });
    if (_input.length == 4) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        if (_input == widget.pin) {
          Navigator.pop(context, true);
        } else {
          setState(() {
            _err = true;
            _input = '';
          });
        }
      });
    }
  }

  Widget _key(String label, VoidCallback onTap) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(18),
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 20)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2F3542),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 60, color: Colors.white),
            const SizedBox(height: 8),
            const Text('🔒 هذه البطاقة محمية',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const Text('أدخل رمز PIN المكون من 4 أرقام',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                4,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _input.length ? kPrimary : Colors.transparent,
                    border: Border.all(color: kPrimary, width: 2),
                  ),
                ),
              ),
            ),
            if (_err)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('رمز PIN غير صحيح',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 28),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.4,
              padding: const EdgeInsets.symmetric(horizontal: 60),
              children: [
                for (var i = 1; i <= 9; i++) _key('$i', () => _enter('$i')),
                _key('C', () => setState(() => _input = '')),
                _key('0', () => _enter('0')),
                _key('⌫', () => setState(() => _input = _input.isEmpty
                    ? ''
                    : _input.substring(0, _input.length - 1))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
//  شاشة العرض + القوالب
// ============================================================
class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final template = data['template'] as String? ?? 'envelope';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        title: const Text('🎁 بطاقة خاصة لك'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'إلى: ${data['name'] ?? ''} ❤️',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: kPrimary),
          ),
          const SizedBox(height: 16),
          if (template == 'envelope') EnvelopeView(data: data),
          if (template == 'musicbox') MusicBoxView(data: data),
          if (template == 'polaroid') PolaroidView(data: data),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreatorScreen())),
            child: const Text('✨ اصنع بطاقتك الخاصة مجاناً'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => launchUrl(Uri.parse(kBaseUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('زيارة الموقع'),
          ),
        ],
      ),
    );
  }
}

// ---------- قالب الظرف ----------
class EnvelopeView extends StatefulWidget {
  const EnvelopeView({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<EnvelopeView> createState() => _EnvelopeViewState();
}

class _EnvelopeViewState extends State<EnvelopeView> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: SizedBox(
        height: 430,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _open ? _letter() : _closed(),
        ),
      ),
    );
  }

  Widget _closed() => Container(
        key: const ValueKey('closed'),
        width: 300,
        height: 200,
        decoration: BoxDecoration(
          color: kPrimaryLight,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 14, offset: Offset(0, 8))
          ],
        ),
        child: Stack(
          children: [
            CustomPaint(size: const Size(300, 100), painter: _FlapPainter(kPrimary)),
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('💌', style: TextStyle(fontSize: 44)),
                  Text('اضغط للفتح',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _letter() {
    final Widget? img = dataImage(widget.data['image'] as String?);
    return Container(
      key: const ValueKey('open'),
      constraints: const BoxConstraints(maxHeight: 430),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 8))
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(widget.data['message'] ?? '',
              style: const TextStyle(height: 1.8, fontSize: 16)),
          if (img != null) ...[
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
          ],
          const SizedBox(height: 10),
          const Text('اضغط للقفل 🔒',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FlapPainter extends CustomPainter {
  final Color color;
  _FlapPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FlapPainter old) => old.color != color;
}

// ---------- قالب صندوق الموسيقى ----------
class MusicBoxView extends StatefulWidget {
  const MusicBoxView({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<MusicBoxView> createState() => _MusicBoxViewState();
}

class _MusicBoxViewState extends State<MusicBoxView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  YoutubePlayerController? _yt;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
  }

  @override
  void dispose() {
    _spin.dispose();
    _yt?.close();
    super.dispose();
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    final ytId = extractYoutubeId(widget.data['youtube'] as String?);
    if (_playing) {
      _spin.repeat();
      if (ytId != null && _yt == null) {
        _yt = YoutubePlayerController.fromVideoId(
          videoId: ytId,
          autoPlay: true,
        );
      }
    } else {
      _spin.stop();
      _yt?.close();
      _yt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget? img = dataImage(widget.data['image'] as String?);
    return Column(
      children: [
        GestureDetector(
          onTap: _toggle,
          child: RotationTransition(
            turns: _spin,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF111111),
                border: Border.all(color: kPrimary, width: 4),
              ),
              child: Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration:
                      const BoxDecoration(shape: BoxShape.circle, color: kPrimary),
                  child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text('اضغط على القرص للتشغيل / الإيقاف',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
          ),
          child: Column(
            children: [
              Text(widget.data['message'] ?? '',
                  style: const TextStyle(height: 1.8, fontSize: 16)),
              if (img != null) ...[
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(10), child: img),
              ],
            ],
          ),
        ),
        if (_yt != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child:
                SizedBox(height: 220, child: YoutubePlayer(controller: _yt!)),
          ),
      ],
    );
  }
}

// ---------- قالب البولارويد ----------
class PolaroidView extends StatelessWidget {
  const PolaroidView({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final lines = (data['message'] as String? ?? '')
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final captions = lines.length >= 3
        ? lines
        : [data['message'] ?? '', 'أحبك', 'إلى الأبد'];
    final transforms = [
      (-5.0, 0.0, 0.0),
      (3.0, 40.0, 40.0),
      (-2.0, 80.0, 80.0),
    ];
    return SizedBox(
      height: 430,
      child: Stack(
        children: [
          for (var i = 0; i < 3; i++)
            Positioned(
              top: 20 + transforms[i].$3,
              left: 20 + transforms[i].$2,
              child: Transform.rotate(
                angle: transforms[i].$1 * math.pi / 180,
                child: GestureDetector(
                  onTap: () => _zoom(context, captions[i]),
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 150,
                          width: 180,
                          child: dataImage(data['image'] as String?) ??
                              Container(
                                color: const Color(0xFFDDDDDD),
                                alignment: Alignment.center,
                                child: const Text('صورة',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(captions[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _zoom(BuildContext context, String caption) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: dataImage(data['image'] as String?, fit: BoxFit.contain) ??
                    const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              Text(caption, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}