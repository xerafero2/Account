import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:otp/otp.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class ThemeManager {
  static final ValueNotifier<Color> appColor = ValueNotifier(const Color(0xFF1E40AF));

  static Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final colorVal = prefs.getInt('theme_color');
    if (colorVal != null) {
      appColor.value = Color(colorVal);
    }
  }

  static Future<void> setTheme(Color color) async {
    appColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', color.value);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeManager.loadTheme();
  runApp(const SocialMediaManagerApp());
}

class SocialMediaManagerApp extends StatelessWidget {
  const SocialMediaManagerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeManager.appColor,
      builder: (context, color, child) {
        return MaterialApp(
          title: 'AccountManager',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFF4F6F9),
            colorScheme: ColorScheme.fromSeed(seedColor: color, primary: color),
            fontFamily: 'Roboto',
          ),
          home: const DashboardScreen(),
        );
      },
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('account_manager_v6.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        identifier TEXT NOT NULL,
        password TEXT NOT NULL,
        a2f INTEGER NOT NULL,
        secret_key TEXT,
        created_at TEXT,
        updated_at TEXT,
        custom_icon_path TEXT,
        avatar_path TEXT,
        dob TEXT,
        account_year TEXT,
        tags TEXT
      )
    ''');
  }

  Future<int> insertAccount(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('accounts', row);
  }

  Future<int> updateAccount(Map<String, dynamic> row) async {
    final db = await instance.database;
    int id = row['id'];
    return await db.update('accounts', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> fetchAccounts({String query = '', String sortOption = 'terbaru'}) async {
    try {
      final db = await instance.database;
      String orderBy = 'updated_at DESC';

      if (sortOption == 'terlama') {
        orderBy = 'updated_at ASC';
      } else if (sortOption == 'a-z') {
        orderBy = 'name COLLATE NOCASE ASC';
      }

      if (query.isEmpty) {
        return await db.query('accounts', orderBy: orderBy);
      } else {
        return await db.query(
          'accounts',
          where: 'name LIKE ? OR identifier LIKE ? OR tags LIKE ?',
          whereArgs: ['%$query%', '%$query%', '%$query%'],
          orderBy: orderBy,
        );
      }
    } catch (e) {
      debugPrint('ERROR fetching accounts: $e');
      return [];
    }
  }

  Future<int> deleteAccount(int id) async {
    final db = await instance.database;
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await instance.database;
    return await db.query('accounts');
  }

  Future<void> importAccounts(List<dynamic> accountsList) async {
    final db = await instance.database;
    Batch batch = db.batch();
    for (var acc in accountsList) {
      Map<String, dynamic> row = Map<String, dynamic>.from(acc);
      row.remove('id');
      batch.insert('accounts', row);
    }
    await batch.commit(noResult: true);
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _accounts = [];
  Timer? _globalTimer;
  int _secondsRemaining = 30;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortOption = 'terbaru';

  @override
  void initState() {
    super.initState();
    _refreshAccounts();
    _startGlobalTimer();
  }

  @override
  void dispose() {
    _globalTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startGlobalTimer() {
    _globalTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          int epochSeconds = (DateTime.now().millisecondsSinceEpoch / 1000).floor();
          _secondsRemaining = 30 - (epochSeconds % 30);
        });
      }
    });
  }

  Future<void> _refreshAccounts() async {
    final data = await DatabaseHelper.instance.fetchAccounts(query: _searchQuery, sortOption: _sortOption);
    if (mounted) setState(() { _accounts = data; });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildCleanHeader(context),
              Expanded(
                child: _accounts.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isEmpty ? 'Belum ada akun yang disimpan' : 'Tidak ada akun yang cocok',
                          style: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w500),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _accounts.length,
                        itemBuilder: (context, index) {
                          final acc = _accounts[index];
                          return AccountCard(
                            key: ValueKey('card_${acc['id']}_${acc['name']}_${acc['identifier']}_${acc['password']}_${acc['custom_icon_path']}_${acc['avatar_path']}_${acc['tags']}_${acc['updated_at']}'),
                            account: acc,
                            index: index + 1,
                            secondsRemaining: _secondsRemaining,
                            onRefresh: _refreshAccounts,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Akun', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const AccountFormScreen()));
            if (result == true) _refreshAccounts();
          },
        ),
      ),
    );
  }

  Widget _buildCleanHeader(BuildContext context) {
    final themeColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [themeColor, themeColor.withOpacity(0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: themeColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))
                  ]
                ),
                child: const Icon(Icons.security_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AccountManager', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('${_accounts.length} Akun tersimpan', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(12)
                ),
                child: IconButton(
                  icon: const Icon(Icons.color_lens_rounded, size: 22, color: Colors.black87),
                  onPressed: () async {
                    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                    if (result == true) {
                      _refreshAccounts();
                    }
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      _searchQuery = value;
                      _refreshAccounts();
                    },
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      hintText: 'Cari platform, username, atau tag...',
                      hintStyle: TextStyle(color: Colors.black38, fontSize: 14, fontWeight: FontWeight.normal),
                      prefixIcon: Icon(Icons.search, color: Colors.black38, size: 20),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.1)),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.tune, color: themeColor),
                  tooltip: 'Urutkan Akun',
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  position: PopupMenuPosition.under,
                  onSelected: (value) {
                    setState(() { _sortOption = value; });
                    _refreshAccounts();
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'terbaru',
                      child: Row(
                        children: [
                          Icon(Icons.access_time, size: 20, color: _sortOption == 'terbaru' ? themeColor : Colors.black54),
                          const SizedBox(width: 12),
                          Text('Terbaru Ditambahkan', style: TextStyle(fontWeight: _sortOption == 'terbaru' ? FontWeight.bold : FontWeight.normal, color: _sortOption == 'terbaru' ? themeColor : Colors.black87)),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'terlama',
                      child: Row(
                        children: [
                          Icon(Icons.history, size: 20, color: _sortOption == 'terlama' ? themeColor : Colors.black54),
                          const SizedBox(width: 12),
                          Text('Terlama Ditambahkan', style: TextStyle(fontWeight: _sortOption == 'terlama' ? FontWeight.bold : FontWeight.normal, color: _sortOption == 'terlama' ? themeColor : Colors.black87)),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'a-z',
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha, size: 20, color: _sortOption == 'a-z' ? themeColor : Colors.black54),
                          const SizedBox(width: 12),
                          Text('Abjad (A - Z)', style: TextStyle(fontWeight: _sortOption == 'a-z' ? FontWeight.bold : FontWeight.normal, color: _sortOption == 'a-z' ? themeColor : Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  Future<void> _exportData(BuildContext context) async {
    try {
      final data = await DatabaseHelper.instance.getAllAccounts();
      if (data.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada data untuk diekspor')));
        }
        return;
      }

      final jsonData = jsonEncode(data);
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'account_manager_backup_$timestamp.json';
      
      final bytes = Uint8List.fromList(utf8.encode(jsonData));
      
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Backup Akun',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes, 
      );

      if (outputFile != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data berhasil diekspor')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengekspor data: $e')));
      }
    }
  }

  Future<void> _importData(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(jsonString);

      await DatabaseHelper.instance.importAccounts(jsonData);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data berhasil diimpor')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengimpor: Pastikan format file JSON valid')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> themes = [
      {'name': 'Biru Profesional (Default)', 'color': const Color(0xFF1E40AF)},
      {'name': 'Ungu Modern', 'color': const Color(0xFF6C4DFF)},
      {'name': 'Hijau Emerald', 'color': const Color(0xFF059669)},
      {'name': 'Merah Ruby', 'color': const Color(0xFFDC2626)},
      {'name': 'Hitam Elegan', 'color': const Color(0xFF1F2937)},
      {'name': 'Oranye Senja', 'color': const Color(0xFFEA580C)},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('TEMA APLIKASI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: themes.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
              itemBuilder: (context, index) {
                final t = themes[index];
                final Color tColor = t['color'];
                final bool isSelected = ThemeManager.appColor.value.value == tColor.value;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(backgroundColor: tColor, radius: 18),
                  title: Text(t['name'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                  trailing: isSelected ? Icon(Icons.check_circle, color: tColor) : null,
                  onTap: () {
                    ThemeManager.setTheme(tColor);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('MANAJEMEN DATA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.upload_file_outlined, color: Colors.black87)),
                  title: const Text('Ekspor Data', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Simpan akun sebagai file JSON', style: TextStyle(fontSize: 12)),
                  onTap: () => _exportData(context),
                ),
                const Divider(height: 1, color: Colors.black12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.download_outlined, color: Colors.black87)),
                  title: const Text('Impor Data', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Pulihkan akun dari file JSON', style: TextStyle(fontSize: 12)),
                  onTap: () => _importData(context),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class AccountCard extends StatefulWidget {
  final Map<String, dynamic> account;
  final int index;
  final int secondsRemaining;
  final VoidCallback onRefresh;

  const AccountCard({Key? key, required this.account, required this.index, required this.secondsRemaining, required this.onRefresh}) : super(key: key);

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  bool _isPasswordVisible = false;

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label tersalin', style: const TextStyle(fontWeight: FontWeight.w500)), duration: const Duration(seconds: 1)));
  }

  String _getTotp() {
    try {
      return OTP.generateTOTPCodeString(widget.account['secret_key'], DateTime.now().millisecondsSinceEpoch, length: 6, interval: 30, algorithm: Algorithm.SHA1, isGoogle: true);
    } catch (e) {
      return 'ERROR ';
    }
  }

  Widget _buildPlatformIcon(String? iconPath, String name, double size) {
    if (iconPath != null && iconPath.isNotEmpty) {
      if (iconPath.startsWith('assets/')) {
        return ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: Image.asset(iconPath, width: size, height: size, fit: BoxFit.cover));
      } else {
        return ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: Image.file(File(iconPath), width: size, height: size, fit: BoxFit.cover));
      }
    }
    return Icon(Icons.public, color: Colors.black54, size: size * 0.8);
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Tidak tersedia';
    return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(isoString));
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.account;
    final List<String> tags = (acc['tags'] ?? '').toString().split(',').where((e) => e.trim().isNotEmpty).toList();
    final String displayName = (acc['name'] == null || acc['name'].toString().trim().isEmpty) ? 'AKUN' : acc['name'].toString().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildBadge(widget.index.toString(), isOutline: true),
                if (acc['account_year'] != null && acc['account_year'].toString().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _buildBadge(acc['account_year'], bgColor: Theme.of(context).colorScheme.primary.withOpacity(0.1), textColor: Theme.of(context).colorScheme.primary),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
                  child: Row(
                    children: [
                      _buildPlatformIcon(acc['custom_icon_path'], displayName, 16),
                      const SizedBox(width: 6),
                      Text(displayName, style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)),
                  clipBehavior: Clip.hardEdge,
                  child: acc['avatar_path'] != null && acc['avatar_path'].toString().isNotEmpty
                      ? Image.file(File(acc['avatar_path']), fit: BoxFit.cover)
                      : Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(acc['identifier'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18, color: Colors.black54),
                            onPressed: () => _copyToClipboard(acc['identifier'], 'Username/Email'),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black.withOpacity(0.05))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isPasswordVisible ? acc['password'] : '••••••••',
                                style: TextStyle(fontSize: 14, fontFamily: 'monospace', letterSpacing: _isPasswordVisible ? 0 : 2, color: Colors.black87),
                              ),
                            ),
                            IconButton(
                              icon: Icon(_isPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: Colors.black54),
                              onPressed: () => setState(() { _isPasswordVisible = !_isPasswordVisible; }),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_outlined, size: 18, color: Colors.black54),
                              onPressed: () => _copyToClipboard(acc['password'], 'Password'),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
          
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Colors.black12)),

          if ((acc['dob'] != null && acc['dob'].toString().isNotEmpty) || tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (acc['dob'] != null && acc['dob'].toString().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cake_outlined, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(acc['dob'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const Icon(Icons.sports_esports_outlined, color: Colors.black45, size: 18),
                        ...tags.map((t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(6)),
                          child: Text(t.trim(), style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500)),
                        )).toList(),
                      ],
                    )
                  ]
                ],
              ),
            ),

          if (acc['a2f'] == 1 && acc['secret_key'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('2-FACTOR CODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black54, letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text(
                            _getTotp(),
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFDC2626), letterSpacing: 4),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: widget.secondsRemaining / 30,
                              backgroundColor: Colors.black12,
                              color: const Color(0xFFDC2626),
                              minHeight: 3,
                            ),
                          )
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, color: Colors.black54),
                      onPressed: () => _copyToClipboard(_getTotp().replaceAll(' ', ''), 'Token 2FA'),
                    )
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.black.withOpacity(0.1)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => AccountFormScreen(account: acc)));
                          if (result == true) widget.onRefresh();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(8)),
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFE11D48)),
                        onPressed: () async {
                          await DatabaseHelper.instance.deleteAccount(acc['id']);
                          widget.onRefresh();
                        },
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dibuat: ${_formatDate(acc['created_at'])}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                    Text('Update: ${_formatDate(acc['updated_at'])}', style: const TextStyle(fontSize: 10, color: Colors.black38)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBadge(String text, {bool isOutline = false, Color? bgColor, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOutline ? Colors.transparent : (bgColor ?? Colors.white),
        border: Border.all(color: isOutline ? Colors.black12 : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor ?? Colors.black54)),
    );
  }
}

class AccountFormScreen extends StatefulWidget {
  final Map<String, dynamic>? account;
  const AccountFormScreen({Key? key, this.account}) : super(key: key);

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  bool isA2fEnabled = false;
  bool isPasswordVisible = false;
  String? selectedIconPath;
  String? selectedAvatarPath;
  String? createdAt;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _secretKeyController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  final List<String> _builtInIcons = [
    'assets/icons/facebook.png',
    'assets/icons/instagram.png',
    'assets/icons/google.png',
    'assets/icons/x.png',
    'assets/icons/tiktok.png',
  ];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      _nameController.text = widget.account!['name'] ?? '';
      _identifierController.text = widget.account!['identifier'];
      _passwordController.text = widget.account!['password'];
      isA2fEnabled = widget.account!['a2f'] == 1;
      _secretKeyController.text = widget.account!['secret_key'] ?? '';
      _dobController.text = widget.account!['dob'] ?? '';
      _yearController.text = widget.account!['account_year'] ?? '';
      _tagsController.text = widget.account!['tags'] ?? '';
      selectedIconPath = widget.account!['custom_icon_path'];
      selectedAvatarPath = widget.account!['avatar_path'];
      createdAt = widget.account!['created_at'];
    }
  }

  Future<void> _pickImage(bool isAvatar) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (isAvatar) {
          selectedAvatarPath = image.path;
        } else {
          selectedIconPath = image.path;
        }
      });
    }
  }

  Future<void> _saveAccount() async {
    final name = _nameController.text.trim();
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();
    String secretKey = _secretKeyController.text.trim().replaceAll(' ', '');

    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username/Email dan Password wajib diisi')));
      return;
    }

    if (isA2fEnabled) {
      if (secretKey.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal: Secret Key tidak boleh kosong saat A2F aktif')));
        return;
      }
      try {
        OTP.generateTOTPCodeString(secretKey, DateTime.now().millisecondsSinceEpoch, algorithm: Algorithm.SHA1, isGoogle: true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal: Secret Key 2FA tidak valid')));
        return;
      }
    }

    final nowIso = DateTime.now().toIso8601String();

    final row = {
      'name': name,
      'identifier': identifier,
      'password': password,
      'a2f': isA2fEnabled ? 1 : 0,
      'secret_key': isA2fEnabled ? secretKey : null,
      'created_at': createdAt ?? nowIso,
      'updated_at': nowIso,
      'custom_icon_path': selectedIconPath,
      'avatar_path': selectedAvatarPath,
      'dob': _dobController.text.trim(),
      'account_year': _yearController.text.trim(),
      'tags': _tagsController.text.trim(),
    };

    if (widget.account == null) {
      await DatabaseHelper.instance.insertAccount(row);
    } else {
      row['id'] = widget.account!['id'];
      await DatabaseHelper.instance.updateAccount(row);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _buildIconPreview() {
    if (selectedIconPath != null && selectedIconPath!.isNotEmpty) {
      if (selectedIconPath!.startsWith('assets/')) {
        return Image.asset(selectedIconPath!, fit: BoxFit.cover);
      } else {
        return Image.file(File(selectedIconPath!), fit: BoxFit.cover);
      }
    }
    return Icon(Icons.public, size: 36, color: Theme.of(context).colorScheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.account != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.close, color: Colors.black87), onPressed: () => Navigator.pop(context)),
          title: Text(isEdit ? 'Edit Akun' : 'Tambah Akun', style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w700)),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: _saveAccount,
                child: Text('Simpan', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    border: Border.all(color: Colors.black.withOpacity(0.05)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _buildIconPreview(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    GestureDetector(
                      onTap: () => _pickImage(false),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12, style: BorderStyle.solid),
                        ),
                        child: const Icon(Icons.add_photo_alternate_outlined, color: Colors.black54),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() { selectedIconPath = null; }),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selectedIconPath == null ? Theme.of(context).colorScheme.primary : Colors.black12, width: selectedIconPath == null ? 2 : 1),
                        ),
                        child: const Icon(Icons.public, color: Colors.black54, size: 24),
                      ),
                    ),
                    ..._builtInIcons.map((path) => GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedIconPath = path;
                          String platformName = path.split('/').last.split('.').first;
                          if (platformName.toLowerCase() == 'x') {
                            platformName = 'X (Twitter)';
                          } else {
                            platformName = platformName[0].toUpperCase() + platformName.substring(1);
                          }
                          _nameController.text = platformName;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(6),
                        width: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedIconPath == path ? Theme.of(context).colorScheme.primary : Colors.black12,
                            width: selectedIconPath == path ? 2 : 1,
                          ),
                        ),
                        child: Image.asset(path),
                      ),
                    )).toList()
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(controller: _nameController, hint: 'Singkatan / Platform (Opsional)', icon: Icons.public),
              const SizedBox(height: 16),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _pickImage(true),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: selectedAvatarPath != null
                          ? Image.file(File(selectedAvatarPath!), fit: BoxFit.cover)
                          : const Icon(Icons.add_a_photo_outlined, color: Colors.black38, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(controller: _identifierController, hint: 'Email atau Username'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                hint: 'Password Akun',
                icon: Icons.lock_outline,
                isPassword: true,
                isVisible: isPasswordVisible,
                onVisibilityToggle: () => setState(() { isPasswordVisible = !isPasswordVisible; }),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _dobController, hint: 'Tgl Lahir')),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField(controller: _yearController, hint: 'Tahun Buat', keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(controller: _tagsController, hint: 'Kategori / Game (pisahkan koma)', icon: Icons.sports_esports_outlined),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Aktifkan 2-Factor Code', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                        Switch(value: isA2fEnabled, activeColor: Theme.of(context).colorScheme.primary, onChanged: (val) => setState(() { isA2fEnabled = val; })),
                      ],
                    ),
                    if (isA2fEnabled) ...[
                      const Divider(height: 24),
                      _buildTextField(controller: _secretKeyController, hint: 'Masukkan Secret Key Base32'),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saveAccount,
                  child: Text(isEdit ? 'Simpan Perubahan' : 'Simpan Akun Baru', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, IconData? icon, bool isPassword = false, bool isVisible = false, VoidCallback? onVisibilityToggle, TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.1))),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isVisible,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          prefixIcon: icon != null ? Icon(icon, color: Colors.black38, size: 20) : null,
          suffixIcon: isPassword
              ? IconButton(icon: Icon(isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.black38, size: 20), onPressed: onVisibilityToggle)
              : null,
        ),
      ),
    );
  }
}
