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
import 'package:path_provider/path_provider.dart';
import 'dart:math';

// ==================== THEME MANAGER ====================
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

// ==================== DATABASE HELPER ====================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('account_manager.db');
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

  Future<List<Map<String, dynamic>>> fetchAccounts({
    String query = '',
    String sortOption = 'terbaru',
    List<String>? filterTags,
    List<String>? filterPlatforms,
    bool? filter2FA,
    String? filterYear,
    bool? filterHasAvatar,
    bool? filterHasCustomIcon,
  }) async {
    final db = await instance.database;

    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (query.isNotEmpty) {
      whereClauses.add('(name LIKE ? OR identifier LIKE ? OR tags LIKE ?)');
      whereArgs.addAll(['%$query%', '%$query%', '%$query%']);
    }

    if (filterTags != null && filterTags.isNotEmpty) {
      String tagConditions = filterTags.map((_) => 'tags LIKE ?').join(' OR ');
      whereClauses.add('($tagConditions)');
      for (var tag in filterTags) {
        whereArgs.add('%$tag%');
      }
    }

    if (filterPlatforms != null && filterPlatforms.isNotEmpty) {
      String platformConditions = filterPlatforms.map((_) => 'name = ?').join(' OR ');
      whereClauses.add('($platformConditions)');
      for (var p in filterPlatforms) {
        whereArgs.add(p);
      }
    }

    if (filter2FA == true) {
      whereClauses.add('a2f = 1');
    }

    if (filterYear != null && filterYear.isNotEmpty) {
      whereClauses.add('account_year = ?');
      whereArgs.add(filterYear);
    }

    if (filterHasAvatar == true) {
      whereClauses.add("avatar_path IS NOT NULL AND avatar_path != ''");
    } else if (filterHasAvatar == false) {
      whereClauses.add("(avatar_path IS NULL OR avatar_path = '')");
    }

    if (filterHasCustomIcon == true) {
      whereClauses.add("custom_icon_path IS NOT NULL AND custom_icon_path != ''");
    } else if (filterHasCustomIcon == false) {
      whereClauses.add("(custom_icon_path IS NULL OR custom_icon_path = '')");
    }

    String whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    String orderBy;
    switch (sortOption) {
      case 'terlama':
        orderBy = 'updated_at ASC';
        break;
      case 'platform-az':
        orderBy = 'name COLLATE NOCASE ASC';
        break;
      case 'username-az':
        orderBy = 'identifier COLLATE NOCASE ASC';
        break;
      default: // 'terbaru'
        orderBy = 'updated_at DESC';
    }

    final sql = 'SELECT * FROM accounts $whereString ORDER BY $orderBy';
    return await db.rawQuery(sql, whereArgs);
  }

  Future<int> deleteAccount(int id) async {
    final db = await instance.database;
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await instance.database;
    return await db.query('accounts');
  }

  static Future<String?> saveBase64Image(String base64String) async {
    try {
      final bytes = base64Decode(base64String);
      final dir = await getApplicationDocumentsDirectory();
      final filename = 'avatar_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.png';
      final file = File(p.join(dir.path, filename));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      debugPrint('Gagal menyimpan base64: $e');
      return null;
    }
  }

  Future<void> importAccounts(List<dynamic> accountsList) async {
    final db = await instance.database;
    Batch batch = db.batch();
    for (var acc in accountsList) {
      Map<String, dynamic> row = Map<String, dynamic>.from(acc);
      row.remove('id');

      if (row['avatar_base64'] != null && row['avatar_base64'].toString().isNotEmpty) {
        final path = await DatabaseHelper.saveBase64Image(row['avatar_base64']);
        if (path != null) {
          row['avatar_path'] = path;
        }
        row.remove('avatar_base64');
      }

      batch.insert('accounts', row);
    }
    await batch.commit(noResult: true);
  }
}

// ==================== SPLASH SCREEN ====================
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = ThemeManager.appColor.value;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [themeColor, themeColor.withOpacity(0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: themeColor.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.security_rounded, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 24),
            Text(
              'Account Manager',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: themeColor,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kelola Akun Anda dengan Aman',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== MAIN APP ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeManager.loadTheme();
  runApp(const AccountManagerApp());
}

class AccountManagerApp extends StatelessWidget {
  const AccountManagerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: ThemeManager.appColor,
      builder: (context, color, child) {
        return MaterialApp(
          title: 'Account Manager',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFF4F6F9),
            colorScheme: ColorScheme.fromSeed(seedColor: color, primary: color),
            fontFamily: 'Roboto',
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}

// ==================== DASHBOARD ====================
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

  // Filter state
  List<String> _selectedTags = [];
  List<String> _selectedPlatforms = [];
  bool _filter2FA = false;
  String _filterYear = '';
  bool? _filterHasAvatar; // null = tidak filter, true = harus ada, false = harus tidak ada
  bool? _filterHasCustomIcon;
  bool _filterBirthdayMonth = false;

  final TextEditingController _yearFilterController = TextEditingController();

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
    _yearFilterController.dispose();
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

  Future<List<String>> _getAllTags() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT DISTINCT tags FROM accounts WHERE tags IS NOT NULL AND tags != ""',
    );
    Set<String> tags = {};
    for (var row in result) {
      String raw = row['tags'] as String;
      tags.addAll(raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
    return tags.toList()..sort();
  }

  Future<List<String>> _getAllPlatforms() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      'SELECT DISTINCT name FROM accounts WHERE name IS NOT NULL AND name != ""',
    );
    return result.map((row) => row['name'] as String).toList()..sort();
  }

  Future<void> _refreshAccounts() async {
    final data = await DatabaseHelper.instance.fetchAccounts(
      query: _searchQuery,
      sortOption: _sortOption,
      filterTags: _selectedTags.isNotEmpty ? _selectedTags : null,
      filterPlatforms: _selectedPlatforms.isNotEmpty ? _selectedPlatforms : null,
      filter2FA: _filter2FA ? true : null,
      filterYear: _filterYear.isNotEmpty ? _filterYear : null,
      filterHasAvatar: _filterHasAvatar,
      filterHasCustomIcon: _filterHasCustomIcon,
    );

    if (_filterBirthdayMonth) {
      final currentMonth = DateTime.now().month;
      final filtered = data.where((acc) {
        final dob = acc['dob'] as String?;
        if (dob == null || dob.isEmpty) return false;
        // Coba ekstrak bulan dari format umum seperti "yyyy-MM-dd" atau "dd/MM/yyyy"
        try {
          DateTime? parsed;
          if (dob.contains('-')) {
            parsed = DateTime.tryParse(dob);
          } else if (dob.contains('/')) {
            final parts = dob.split('/');
            if (parts.length == 3) {
              // Asumsi dd/MM/yyyy
              parsed = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
            }
          }
          return parsed?.month == currentMonth;
        } catch (_) {
          return false;
        }
      }).toList();
      if (mounted) setState(() { _accounts = filtered; });
    } else {
      if (mounted) setState(() { _accounts = data; });
    }
  }

  void _showUnifiedFilterSheet(BuildContext context) async {
    final allTags = await _getAllTags();
    final allPlatforms = await _getAllPlatforms();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final themeColor = Theme.of(context).colorScheme.primary;
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Judul
                    Row(
                      children: [
                        const Text('Filter & Urutkan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              _selectedTags.clear();
                              _selectedPlatforms.clear();
                              _filter2FA = false;
                              _yearFilterController.clear();
                              _filterYear = '';
                              _filterHasAvatar = null;
                              _filterHasCustomIcon = null;
                              _filterBirthdayMonth = false;
                              _sortOption = 'terbaru';
                            });
                          },
                          child: const Text('Reset Semua'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Bagian Urutkan
                    const Text('Urutkan', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Terbaru'),
                          selected: _sortOption == 'terbaru',
                          selectedColor: themeColor.withOpacity(0.2),
                          onSelected: (_) => setSheetState(() => _sortOption = 'terbaru'),
                        ),
                        ChoiceChip(
                          label: const Text('Terlama'),
                          selected: _sortOption == 'terlama',
                          selectedColor: themeColor.withOpacity(0.2),
                          onSelected: (_) => setSheetState(() => _sortOption = 'terlama'),
                        ),
                        ChoiceChip(
                          label: const Text('Platform A-Z'),
                          selected: _sortOption == 'platform-az',
                          selectedColor: themeColor.withOpacity(0.2),
                          onSelected: (_) => setSheetState(() => _sortOption = 'platform-az'),
                        ),
                        ChoiceChip(
                          label: const Text('Username A-Z'),
                          selected: _sortOption == 'username-az',
                          selectedColor: themeColor.withOpacity(0.2),
                          onSelected: (_) => setSheetState(() => _sortOption = 'username-az'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Bagian Filter Platform
                    const Text('Platform', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: allPlatforms.map((platform) {
                        final selected = _selectedPlatforms.contains(platform);
                        return FilterChip(
                          label: Text(platform),
                          selected: selected,
                          selectedColor: themeColor.withOpacity(0.2),
                          checkmarkColor: themeColor,
                          onSelected: (val) {
                            setSheetState(() {
                              if (val) {
                                _selectedPlatforms.add(platform);
                              } else {
                                _selectedPlatforms.remove(platform);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Bagian Tag
                    const Text('Tag', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: allTags.map((tag) {
                        final selected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag),
                          selected: selected,
                          selectedColor: themeColor.withOpacity(0.2),
                          checkmarkColor: themeColor,
                          onSelected: (val) {
                            setSheetState(() {
                              if (val) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Filter 2FA
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hanya akun dengan 2FA'),
                      value: _filter2FA,
                      activeColor: themeColor,
                      onChanged: (val) => setSheetState(() => _filter2FA = val),
                    ),
                    const SizedBox(height: 8),

                    // Tahun Akun
                    TextField(
                      controller: _yearFilterController,
                      decoration: InputDecoration(
                        labelText: 'Tahun Akun',
                        hintText: 'contoh: 2022',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        suffixIcon: _filterYear.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _yearFilterController.clear();
                                  setSheetState(() => _filterYear = '');
                                },
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        _filterYear = val.trim();
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 16),

                    // Filter Avatar
                    Row(
                      children: [
                        const Text('Avatar', style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _filterHasAvatar == null,
                          onSelected: (_) => setSheetState(() => _filterHasAvatar = null),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Ada'),
                          selected: _filterHasAvatar == true,
                          onSelected: (_) => setSheetState(() => _filterHasAvatar = true),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Tidak'),
                          selected: _filterHasAvatar == false,
                          onSelected: (_) => setSheetState(() => _filterHasAvatar = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter Ikon Kustom
                    Row(
                      children: [
                        const Text('Ikon Kustom', style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _filterHasCustomIcon == null,
                          onSelected: (_) => setSheetState(() => _filterHasCustomIcon = null),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Ada'),
                          selected: _filterHasCustomIcon == true,
                          onSelected: (_) => setSheetState(() => _filterHasCustomIcon = true),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Tidak'),
                          selected: _filterHasCustomIcon == false,
                          onSelected: (_) => setSheetState(() => _filterHasCustomIcon = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter Ulang Tahun Bulan Ini
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ulang tahun bulan ini'),
                      value: _filterBirthdayMonth,
                      activeColor: themeColor,
                      onChanged: (val) => setSheetState(() => _filterBirthdayMonth = val),
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _refreshAccounts();
                        },
                        child: const Text('Terapkan', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
    final hasFilter = _selectedTags.isNotEmpty ||
        _selectedPlatforms.isNotEmpty ||
        _filter2FA ||
        _filterYear.isNotEmpty ||
        _filterHasAvatar != null ||
        _filterHasCustomIcon != null ||
        _filterBirthdayMonth;

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
                    const Text('Account Manager', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
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
                  icon: const Icon(Icons.settings_outlined, size: 22, color: Colors.black87),
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
              // Tombol Filter & Urutkan (dengan teks)
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: hasFilter ? themeColor.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hasFilter ? themeColor : Colors.black.withOpacity(0.1)),
                ),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: hasFilter ? themeColor : Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  icon: Icon(Icons.filter_list, size: 20, color: hasFilter ? themeColor : Colors.black54),
                  label: const Text('Filter & Sort'),
                  onPressed: () => _showUnifiedFilterSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== SETTINGS ====================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
            child: Text('PERSONALISASI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.color_lens_outlined, color: Colors.black87)),
              title: const Text('Tema Aplikasi', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemeSelectionScreen())),
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('DATA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.storage_outlined, color: Colors.black87)),
              title: const Text('Manajemen Data', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const DataManagementScreen()));
                if (result == true) {
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== THEME SELECTION ====================
class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({Key? key}) : super(key: key);

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
        title: const Text('Tema Aplikasi', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('PILIH WARNA UTAMA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
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
        ],
      ),
    );
  }
}

// ==================== DATA MANAGEMENT ====================
class DataManagementScreen extends StatelessWidget {
  const DataManagementScreen({Key? key}) : super(key: key);

  static const int maxClipboardExport = 100;

  Future<List<Map<String, dynamic>>> _prepareExportData() async {
    final data = await DatabaseHelper.instance.getAllAccounts();
    final enhancedData = <Map<String, dynamic>>[];
    for (var acc in data) {
      final Map<String, dynamic> entry = Map<String, dynamic>.from(acc);
      if (entry['avatar_path'] != null && entry['avatar_path'].toString().isNotEmpty) {
        final file = File(entry['avatar_path']);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          entry['avatar_base64'] = base64Encode(bytes);
        }
      }
      enhancedData.add(entry);
    }
    return enhancedData;
  }

  Future<void> _exportToFile(BuildContext context) async {
    try {
      final data = await _prepareExportData();
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

      if (outputFile != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data berhasil diekspor ke file')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    }
  }

  Future<void> _copyJsonToClipboard(BuildContext context) async {
    try {
      final data = await _prepareExportData();
      if (data.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada data untuk disalin')));
        }
        return;
      }
      if (data.length > maxClipboardExport) {
        _showClipboardLimitDialog(context, data.length);
        return;
      }
      final jsonData = jsonEncode(data);
      await Clipboard.setData(ClipboardData(text: jsonData));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON berhasil disalin ke clipboard')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyalin: $e')));
      }
    }
  }

  void _showClipboardLimitDialog(BuildContext context, int count) {
    final themeColor = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: themeColor, size: 28),
            ),
            const SizedBox(width: 12),
            const Text('Data Terlalu Besar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Text(
          'Anda memiliki $count akun. Salin ke clipboard hanya mendukung maksimal $maxClipboardExport akun.',
          style: const TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromFile(BuildContext context) async {
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data berhasil diimpor dari file')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengimpor: Pastikan format file JSON valid')));
      }
    }
  }

  Future<void> _showClipboardImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    final themeColor = Theme.of(context).colorScheme.primary;

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.paste_outlined, color: themeColor, size: 28),
            ),
            const SizedBox(width: 12),
            const Text('Impor Akun', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tempelkan data JSON yang telah disalin ke kolom di bawah ini.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'Tempel JSON di sini...',
                  hintStyle: const TextStyle(color: Colors.black26),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themeColor, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: themeColor),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Masukkan data JSON terlebih dahulu')),
                );
                return;
              }
              try {
                dynamic decoded = jsonDecode(text);
                List<dynamic> jsonData;
                if (decoded is Map) {
                  jsonData = [decoded];
                } else if (decoded is List) {
                  jsonData = decoded;
                } else {
                  throw FormatException();
                }
                await DatabaseHelper.instance.importAccounts(jsonData);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Data berhasil diimpor')),
                  );
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gagal: JSON tidak valid')),
                  );
                }
              }
            },
            child: const Text('Impor'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Data', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('EKSPOR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.save_alt_outlined, color: Colors.black87)),
                  title: const Text('Simpan ke File', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Ekspor akun sebagai file JSON', style: TextStyle(fontSize: 12)),
                  onTap: () => _exportToFile(context),
                ),
                const Divider(height: 1, color: Colors.black12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.copy_outlined, color: Colors.black87)),
                  title: const Text('Salin JSON ke Clipboard', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Salin seluruh data dalam format JSON (maks 100 akun)', style: TextStyle(fontSize: 12)),
                  onTap: () => _copyJsonToClipboard(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('IMPOR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1)),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black.withOpacity(0.05))),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.file_open_outlined, color: Colors.black87)),
                  title: const Text('Impor dari File', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Pulihkan akun dari file JSON', style: TextStyle(fontSize: 12)),
                  onTap: () => _importFromFile(context),
                ),
                const Divider(height: 1, color: Colors.black12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: const CircleAvatar(backgroundColor: Color(0xFFF8F9FA), child: Icon(Icons.paste_outlined, color: Colors.black87)),
                  title: const Text('Tempel dari Clipboard', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Impor JSON yang sudah disalin', style: TextStyle(fontSize: 12)),
                  onTap: () => _showClipboardImportDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ACCOUNT CARD ====================
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

  void _copyAccountJson() {
    final Map<String, dynamic> acc = widget.account;
    final jsonString = jsonEncode([acc]);
    Clipboard.setData(ClipboardData(text: jsonString));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data akun disalin ke clipboard')));
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
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.parse(isoString));
  }

  Future<void> _confirmDelete() async {
    final acc = widget.account;
    final String identifier = acc['identifier'];
    final themeColor = Theme.of(context).colorScheme.primary;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: themeColor, size: 28),
            ),
            const SizedBox(width: 12),
            const Text('Hapus Akun?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
            children: [
              const TextSpan(text: 'Anda yakin ingin menghapus akun '),
              TextSpan(
                text: '"$identifier"',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const TextSpan(text: '?\nData yang dihapus tidak dapat dikembalikan.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteAccount(acc['id']);
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Akun "$identifier" dihapus'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = widget.account;
    final List<String> tags = (acc['tags'] ?? '').toString().split(',').where((e) => e.trim().isNotEmpty).toList();
    final String displayName = (acc['name'] == null || acc['name'].toString().trim().isEmpty) ? 'AKUN' : acc['name'].toString().toUpperCase();
    final themeColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                  _buildBadge(acc['account_year'], bgColor: themeColor.withOpacity(0.1), textColor: themeColor),
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
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: themeColor, width: 1.5),
                  ),
                  child: ClipOval(
                    child: acc['avatar_path'] != null && acc['avatar_path'].toString().isNotEmpty
                        ? Image.file(File(acc['avatar_path']), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.person_outline, color: themeColor))
                        : Icon(Icons.person_outline, color: themeColor),
                  ),
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
                  border: Border.all(color: themeColor.withOpacity(0.5), width: 1.5),
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
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 4),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: widget.secondsRemaining / 30,
                                    backgroundColor: Colors.black12,
                                    color: themeColor,
                                    minHeight: 3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: themeColor.withOpacity(0.1),
                                  border: Border.all(color: themeColor, width: 1.5),
                                ),
                                child: Center(
                                  child: Text(
                                    '${widget.secondsRemaining}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: themeColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                      decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(8)),
                      child: IconButton(
                        icon: const Icon(Icons.share_outlined, color: Color(0xFF0284C7)),
                        onPressed: _copyAccountJson,
                        tooltip: 'Salin data akun',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(color: const Color(0xFFFFE4E6), borderRadius: BorderRadius.circular(8)),
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFE11D48)),
                        onPressed: _confirmDelete,
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

// ==================== ACCOUNT FORM ====================
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Secret Key 2FA tidak boleh kosong')));
        return;
      }
      try {
        OTP.generateTOTPCodeString(secretKey, DateTime.now().millisecondsSinceEpoch, algorithm: Algorithm.SHA1, isGoogle: true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Secret Key 2FA tidak valid')));
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
              _buildTextField(controller: _tagsController, hint: 'Tag (pisahkan koma)', icon: Icons.sports_esports_outlined),
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
