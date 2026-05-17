import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../config/api_endpoints.dart';
import '../models/user_analysis.dart';
import '../services/authorized_api_service.dart';
import '../theme/app_colors.dart';

class UserAnalysisScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const UserAnalysisScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<UserAnalysisScreen> createState() => _UserAnalysisScreenState();
}

class _UserAnalysisScreenState extends State<UserAnalysisScreen>
    with SingleTickerProviderStateMixin {
  UserAnalysis? _data;
  bool _isLoading = true;
  String? _error;
  bool _isGeneratingPdf = false;
  late TabController _tabController;

  static const _tabs = [
    Tab(icon: Icon(Icons.person), text: 'Profile'),
    Tab(icon: Icon(Icons.groups), text: 'GAT'),
    Tab(icon: Icon(Icons.calendar_today), text: 'Attendance'),
    Tab(icon: Icon(Icons.build), text: 'Maintenance'),
    Tab(icon: Icon(Icons.inventory_2), text: 'Stock Used'),
    Tab(icon: Icon(Icons.folder), text: 'Documents'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _fetchAnalysis();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalysis() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await AuthorizedApiService.sendWithAutoRefresh(
        null,
        (token) => http
            .get(
              Uri.parse(ApiEndpoints.userAnalysis(widget.userId)),
              headers: ApiEndpoints.authorizedHeaders(token),
            )
            .timeout(const Duration(seconds: 20)),
      );

      if (response == null) {
        throw Exception('Authentication failed. Please log in again.');
      }

      if (response.statusCode != 200) {
        throw Exception('Server error (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected response format');
      }

      setState(() {
        _data = UserAnalysis.fromJson(decoded);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadPdf() async {
    final data = _data;
    if (data == null) return;

    setState(() => _isGeneratingPdf = true);
    try {
      final pdfBytes = await _buildPdf(data);
      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'User_Analysis_${data.profile.fullName.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF generation failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<Uint8List> _buildPdf(UserAnalysis data) async {
    final doc = pw.Document();
    final profile = data.profile;
    final gat = data.gat;
    final attendance = data.attendance;
    final maintenance = data.maintenance;
    final documents = data.documents;
    final stockUsage = data.stockUsage ?? UserAnalysisStockUsage.empty;

    // Load profile photo if available
    pw.ImageProvider? profileImage;
    if (profile.profilePhotoUrl != null &&
        profile.profilePhotoUrl!.isNotEmpty) {
      try {
        profileImage = await networkImage(profile.profilePhotoUrl!);
      } catch (_) {
        profileImage = null;
      }
    }

    // Load pathak logo from assets
    pw.ImageProvider? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logos/splash_logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    // Load document photos (approved only)
    final approvedDocs = documents.items
        .where((d) => d.status.trim().toLowerCase() == 'approved')
        .toList();
    final docImages = <int, pw.ImageProvider>{};
    for (final item in approvedDocs) {
      if (item.photoUrl != null && item.photoUrl!.isNotEmpty) {
        try {
          docImages[item.itemId] = await networkImage(item.photoUrl!);
        } catch (_) {}
      }
    }

    const headerColor = PdfColor.fromInt(0xFF702D2C);
    const accentColor = PdfColor.fromInt(0xFFFFD600);
    const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
    const white = PdfColors.white;

    pw.Widget _sectionHeader(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: headerColor,
      child: pw.Text(
        title,
        style: pw.TextStyle(
          color: white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );

    pw.Widget _infoRow(String label, String? value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 160,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value?.isNotEmpty == true ? value! : '—',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );

    pw.Widget _statusBadge(String status) {
      PdfColor bg;
      switch (status.toLowerCase()) {
        case 'approved':
        case 'completed':
          bg = const PdfColor.fromInt(0xFF4CAF50);
          break;
        case 'pending':
          bg = const PdfColor.fromInt(0xFFFF9800);
          break;
        case 'rejected':
          bg = const PdfColor.fromInt(0xFFF44336);
          break;
        default:
          bg = PdfColors.grey;
      }
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          status.toUpperCase(),
          style: pw.TextStyle(
            color: white,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          // ── Header ──
          pw.Container(
            color: headerColor,
            padding: const pw.EdgeInsets.all(16),
            child: pw.Row(
              children: [
                if (profileImage != null)
                  pw.Container(
                    width: 70,
                    height: 70,
                    decoration: const pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                    ),
                    child: pw.ClipOval(
                      child: pw.Image(profileImage, fit: pw.BoxFit.cover),
                    ),
                  ),
                if (profileImage != null) pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        profile.fullName,
                        style: pw.TextStyle(
                          color: accentColor,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        profile.role.replaceAll('_', ' ').toUpperCase(),
                        style: pw.TextStyle(
                          color: white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        profile.phoneNumber,
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        width: 52,
                        height: 52,
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'User Analysis Report',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 9,
                      ),
                    ),
                    pw.Text(
                      'Generated: ${_formatDate(DateTime.now().toIso8601String())}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ── Profile ──
          _sectionHeader('Profile'),
          pw.SizedBox(height: 4),
          pw.Container(
            color: lightGrey,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              children: [
                _infoRow('Instrument', profile.instrument),
                _infoRow('Joining Year', profile.joiningYear),
                _infoRow('Gender', profile.sex),
                _infoRow('Blood Group', profile.bloodGroup),
                _infoRow('Emergency Contact', profile.emergencyContactName),
                _infoRow('Emergency Phone', profile.emergencyContactPhone),
                _infoRow('Groups', profile.groups.join(', ')),
                _infoRow('Active', profile.isActive ? 'Yes' : 'No'),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ── GAT ──
          _sectionHeader('GAT Details'),
          pw.SizedBox(height: 4),
          if (gat != null)
            pw.Container(
              color: lightGrey,
              padding: const pw.EdgeInsets.all(10),
              child: pw.Column(
                children: [
                  _infoRow('GAT Name', gat.gatName),
                  _infoRow('Position', gat.position.toUpperCase()),
                  _infoRow('GAT Pramukh', gat.gatPramukhName),
                  _infoRow('Pramukh Phone', gat.gatPramukhPhone),
                  _infoRow('Member Since', _formatDate(gat.memberSince)),
                  _infoRow('Total Members', gat.totalGatMembers.toString()),
                ],
              ),
            )
          else
            pw.Padding(
              padding: const pw.EdgeInsets.all(10),
              child: pw.Text(
                'No GAT assigned.',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          pw.SizedBox(height: 16),

          // ── Attendance Summary ──
          _sectionHeader('Attendance Summary'),
          pw.SizedBox(height: 4),
          pw.Container(
            color: lightGrey,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    _statBox(
                      'Total Days',
                      attendance.totalDays.toString(),
                      headerColor,
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Present',
                      attendance.totalPresent.toString(),
                      const PdfColor.fromInt(0xFF4CAF50),
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Late',
                      attendance.totalLate.toString(),
                      const PdfColor.fromInt(0xFFFF9800),
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Absent',
                      attendance.totalAbsent.toString(),
                      const PdfColor.fromInt(0xFFF44336),
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Percentage',
                      '${attendance.attendancePercentage.toStringAsFixed(1)}%',
                      const PdfColor.fromInt(0xFF2196F3),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                // Monthly table
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.5,
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: headerColor),
                      children: [
                        'Month',
                        'Total',
                        'Present',
                        'Late',
                        'Absent',
                      ].map((h) => _tableHeader(h)).toList(),
                    ),
                    ...attendance.monthly.map(
                      (m) => pw.TableRow(
                        children: [
                          _tableCell(m.monthDisplay),
                          _tableCell(m.totalDays.toString()),
                          _tableCell(
                            m.present.toString(),
                            color: const PdfColor.fromInt(0xFF4CAF50),
                          ),
                          _tableCell(
                            m.late.toString(),
                            color: const PdfColor.fromInt(0xFFFF9800),
                          ),
                          _tableCell(
                            m.absent.toString(),
                            color: const PdfColor.fromInt(0xFFF44336),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ── Maintenance ──
          _sectionHeader('Maintenance'),
          pw.SizedBox(height: 4),
          pw.Container(
            color: lightGrey,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    _statBox(
                      'Assigned',
                      maintenance.totalAssigned.toString(),
                      headerColor,
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Completed',
                      maintenance.totalCompleted.toString(),
                      const PdfColor.fromInt(0xFF4CAF50),
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Pending',
                      maintenance.totalPending.toString(),
                      const PdfColor.fromInt(0xFFFF9800),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                if (maintenance.records.isNotEmpty)
                  pw.Table(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey300,
                      width: 0.5,
                    ),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(1.5),
                      2: const pw.FlexColumnWidth(1.5),
                      3: const pw.FlexColumnWidth(1.5),
                      4: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: headerColor),
                        children: [
                          'Event',
                          'Date',
                          'Work Type',
                          'Status',
                          'Approved By',
                        ].map((h) => _tableHeader(h)).toList(),
                      ),
                      ...maintenance.records.map(
                        (r) => pw.TableRow(
                          children: [
                            _tableCell(r.eventTitle),
                            _tableCell(_formatDate(r.eventDate)),
                            _tableCell(r.workType.replaceAll('_', ' ')),
                            _tableCell(r.status.toUpperCase()),
                            _tableCell(r.approvedBy ?? '—'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ── Stock Usage ──
          _sectionHeader('Stock Usage'),
          pw.SizedBox(height: 4),
          pw.Container(
            color: lightGrey,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    _statBox(
                      'Events',
                      stockUsage.totalEventsWithUsage.toString(),
                      headerColor,
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Total Used',
                      stockUsage.totalQuantityUsed.toString(),
                      const PdfColor.fromInt(0xFFE64A19),
                    ),
                    pw.SizedBox(width: 8),
                    _statBox(
                      'Items',
                      stockUsage.items.length.toString(),
                      const PdfColor.fromInt(0xFF3F51B5),
                    ),
                  ],
                ),
                if (stockUsage.items.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Table(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey300,
                      width: 0.5,
                    ),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(1.5),
                      2: const pw.FlexColumnWidth(1.5),
                      3: const pw.FlexColumnWidth(1),
                      4: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: headerColor),
                        children: [
                          'Item',
                          'Category',
                          'Event',
                          'Date',
                          'Qty',
                        ].map((h) => _tableHeader(h)).toList(),
                      ),
                      ...stockUsage.items.expand((item) {
                        if (item.usageHistory.isEmpty) {
                          return [
                            pw.TableRow(
                              children: [
                                _tableCell(item.itemName),
                                _tableCell(item.category),
                                _tableCell('—'),
                                _tableCell('—'),
                                _tableCell(
                                  item.totalQuantityUsed.toString(),
                                  color: const PdfColor.fromInt(0xFFE64A19),
                                ),
                              ],
                            ),
                          ];
                        }
                        return item.usageHistory.map(
                          (h) => pw.TableRow(
                            children: [
                              _tableCell(item.itemName),
                              _tableCell(item.category),
                              _tableCell(h.eventTitle),
                              _tableCell(_formatDate(h.eventDate)),
                              _tableCell(
                                h.quantityUsed.toString(),
                                color: const PdfColor.fromInt(0xFFE64A19),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // ── Documents ──
          _sectionHeader('Documents'),
          pw.SizedBox(height: 4),
          pw.Container(
            color: lightGrey,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              children: approvedDocs.isEmpty
                  ? [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'No approved documents.',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                    ]
                  : approvedDocs.map((doc) {
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 10),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (docImages.containsKey(doc.itemId))
                              pw.Container(
                                width: 80,
                                height: 60,
                                child: pw.Image(
                                  docImages[doc.itemId]!,
                                  fit: pw.BoxFit.cover,
                                ),
                              )
                            else
                              pw.Container(
                                width: 80,
                                height: 60,
                                color: PdfColors.grey300,
                                child: pw.Center(
                                  child: pw.Text(
                                    'No Photo',
                                    style: const pw.TextStyle(
                                      fontSize: 8,
                                      color: PdfColors.grey600,
                                    ),
                                  ),
                                ),
                              ),
                            pw.SizedBox(width: 12),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Row(
                                    children: [
                                      pw.Text(
                                        doc.typeDisplay,
                                        style: pw.TextStyle(
                                          fontWeight: pw.FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                      pw.SizedBox(width: 8),
                                      _statusBadge(doc.status),
                                    ],
                                  ),
                                  pw.SizedBox(height: 2),
                                  _infoRow(
                                    'Assigned',
                                    _formatDate(doc.assignedAt),
                                  ),
                                  if (doc.returnedAt != null)
                                    _infoRow(
                                      'Returned',
                                      _formatDate(doc.returnedAt),
                                    ),
                                  if (doc.notes != null &&
                                      doc.notes!.isNotEmpty)
                                    _infoRow('Notes', doc.notes),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _statBox(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 14,
              ),
            ),
            pw.Text(
              label,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _tableHeader(String text) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
    ),
  );

  pw.Widget _tableCell(String text, {PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        color: color,
        fontWeight: color != null ? pw.FontWeight.bold : null,
      ),
    ),
  );

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  // ────────────────────────────────────────────────────────────
  //  Flutter UI
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: Colors.white,
        title: Text(
          widget.userName,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_data != null)
            _isGeneratingPdf
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    tooltip: 'Download PDF',
                    onPressed: _downloadPdf,
                  ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchAnalysis,
          ),
        ],
        bottom: _data != null
            ? TabBar(
                controller: _tabController,
                tabs: _tabs,
                labelColor: AppColors.accentYellow,
                unselectedLabelColor: Colors.white70,
                indicatorColor: AppColors.accentYellow,
                isScrollable: true,
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryMaroon),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMaroon,
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    return TabBarView(
      controller: _tabController,
      children: [
        _ProfileTab(profile: data.profile),
        _GatTab(gat: data.gat),
        _AttendanceTab(attendance: data.attendance),
        _MaintenanceTab(maintenance: data.maintenance),
        _StockUsageTab(
          stockUsage: data.stockUsage ?? UserAnalysisStockUsage.empty,
        ),
        _DocumentsTab(documents: data.documents),
      ],
    );
  }
}

// ── Profile Tab ────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final UserAnalysisProfile profile;
  const _ProfileTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Avatar
          CircleAvatar(
            radius: 50,
            backgroundColor: AppColors.primaryMaroon,
            backgroundImage: profile.profilePhotoUrl != null
                ? NetworkImage(profile.profilePhotoUrl!)
                : null,
            child: profile.profilePhotoUrl == null
                ? Text(
                    (profile.firstName.isNotEmpty ? profile.firstName[0] : '?')
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 36,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            profile.fullName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryMaroon,
            ),
          ),
          const SizedBox(height: 4),
          _RoleBadge(role: profile.role),
          const SizedBox(height: 20),
          _InfoCard(
            title: 'Personal Details',
            rows: [
              _InfoRow('Phone', profile.phoneNumber),
              _InfoRow('Instrument', profile.instrument ?? '—'),
              _InfoRow('Joining Year', profile.joiningYear ?? '—'),
              _InfoRow('Gender', profile.sex ?? '—'),
              _InfoRow('Blood Group', profile.bloodGroup ?? '—'),
              _InfoRow(
                'Active',
                profile.isActive ? 'Yes' : 'No',
                valueColor: profile.isActive ? Colors.green : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Emergency Contact',
            rows: [
              _InfoRow('Name', profile.emergencyContactName ?? '—'),
              _InfoRow('Phone', profile.emergencyContactPhone ?? '—'),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Groups / Roles',
            rows: profile.groups
                .map((g) => _InfoRow('', g.replaceAll('_', ' ').toUpperCase()))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── GAT Tab ────────────────────────────────────────────────────────────────

class _GatTab extends StatelessWidget {
  final UserAnalysisGat? gat;
  const _GatTab({required this.gat});

  @override
  Widget build(BuildContext context) {
    if (gat == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('No GAT assigned', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SummaryChips(
            chips: [
              _Chip(
                label: gat!.gatName,
                icon: Icons.groups,
                color: AppColors.primaryMaroon,
              ),
              _Chip(
                label: '${gat!.totalGatMembers} Members',
                icon: Icons.people,
                color: Colors.blueGrey,
              ),
              _Chip(
                label: gat!.position.toUpperCase(),
                icon: Icons.badge,
                color: gat!.position == 'gat_pramukh'
                    ? Colors.amber.shade800
                    : Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoCard(
            title: 'GAT Details',
            rows: [
              _InfoRow('GAT Name', gat!.gatName),
              _InfoRow(
                'Position',
                gat!.position.replaceAll('_', ' ').toUpperCase(),
              ),
              _InfoRow('Member Since', _fmtDate(gat!.memberSince)),
              _InfoRow('Total Members', gat!.totalGatMembers.toString()),
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'GAT Pramukh',
            rows: [
              _InfoRow('Name', gat!.gatPramukhName),
              _InfoRow('Phone', gat!.gatPramukhPhone ?? '—'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Attendance Tab ─────────────────────────────────────────────────────────

class _AttendanceTab extends StatelessWidget {
  final UserAnalysisAttendance attendance;
  const _AttendanceTab({required this.attendance});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Summary chips
          Row(
            children: [
              _AttendanceStat(
                label: 'Present',
                count: attendance.totalPresent,
                color: Colors.green,
              ),
              _AttendanceStat(
                label: 'Late',
                count: attendance.totalLate,
                color: Colors.orange,
              ),
              _AttendanceStat(
                label: 'Absent',
                count: attendance.totalAbsent,
                color: Colors.red,
              ),
              _AttendanceStat(
                label: 'Total',
                count: attendance.totalDays,
                color: AppColors.primaryMaroon,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Percentage bar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Attendance Rate',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${attendance.attendancePercentage.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryMaroon,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: attendance.attendancePercentage / 100,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      color: attendance.attendancePercentage >= 75
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Monthly table
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Monthly Breakdown',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                    4: FlexColumnWidth(1.2),
                  },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        color: AppColors.primaryMaroon,
                      ),
                      children: ['Month', 'Total', 'Present', 'Late', 'Absent']
                          .map(
                            (h) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                              child: Text(
                                h,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    ...attendance.monthly.asMap().entries.map((entry) {
                      final i = entry.key;
                      final m = entry.value;
                      return TableRow(
                        decoration: BoxDecoration(
                          color: i.isOdd ? Colors.grey.shade100 : Colors.white,
                        ),
                        children: [
                          _attendanceCell(m.monthDisplay, isBold: true),
                          _attendanceCell(m.totalDays.toString()),
                          _attendanceCell(
                            m.present.toString(),
                            color: Colors.green.shade700,
                          ),
                          _attendanceCell(
                            m.late.toString(),
                            color: Colors.orange.shade700,
                          ),
                          _attendanceCell(
                            m.absent.toString(),
                            color: Colors.red.shade700,
                          ),
                        ],
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attendanceCell(String text, {Color? color, bool isBold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
}

// ── Maintenance Tab ────────────────────────────────────────────────────────

class _MaintenanceTab extends StatelessWidget {
  final UserAnalysisMaintenance maintenance;
  const _MaintenanceTab({required this.maintenance});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _AttendanceStat(
                label: 'Assigned',
                count: maintenance.totalAssigned,
                color: AppColors.primaryMaroon,
              ),
              _AttendanceStat(
                label: 'Completed',
                count: maintenance.totalCompleted,
                color: Colors.green,
              ),
              _AttendanceStat(
                label: 'Pending',
                count: maintenance.totalPending,
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (maintenance.records.isEmpty)
            const Center(child: Text('No maintenance records.'))
          else
            ...maintenance.records.map((r) => _MaintenanceCard(record: r)),
        ],
      ),
    );
  }
}

class _MaintenanceCard extends StatelessWidget {
  final MaintenanceRecord record;
  const _MaintenanceCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.eventTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                _StatusBadge(status: record.status),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _MetaChip(
                  icon: Icons.calendar_today,
                  label: _fmtDate(record.eventDate),
                ),
                _MetaChip(
                  icon: Icons.build,
                  label: record.workType.replaceAll('_', ' '),
                ),
                if (record.instrumentName != null)
                  _MetaChip(
                    icon: Icons.music_note,
                    label: record.instrumentName!,
                  ),
              ],
            ),
            if (record.notes != null && record.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                record.notes!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (record.approvedBy != null) ...[
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Approved by ${record.approvedBy}  •  ${_fmtDate(record.approvedAt)}',
                    style: const TextStyle(fontSize: 11, color: Colors.green),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Documents Tab ──────────────────────────────────────────────────────────

// ── Stock Usage Tab ───────────────────────────────────────────────────────

class _StockUsageTab extends StatelessWidget {
  final UserAnalysisStockUsage stockUsage;
  const _StockUsageTab({required this.stockUsage});

  @override
  Widget build(BuildContext context) {
    if (stockUsage.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No stock usage recorded.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary row
        Row(
          children: [
            _AttendanceStat(
              label: 'Events',
              count: stockUsage.totalEventsWithUsage,
              color: AppColors.primaryMaroon,
            ),
            const SizedBox(width: 8),
            _AttendanceStat(
              label: 'Total Used',
              count: stockUsage.totalQuantityUsed,
              color: Colors.deepOrange,
            ),
            const SizedBox(width: 8),
            _AttendanceStat(
              label: 'Items',
              count: stockUsage.items.length,
              color: Colors.indigo,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...stockUsage.items.map((item) => _StockUsageItemCard(item: item)),
      ],
    );
  }
}

class _StockUsageItemCard extends StatelessWidget {
  final StockUsageItem item;
  const _StockUsageItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.primaryMaroon,
            size: 20,
          ),
        ),
        title: Text(
          item.itemName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          '${item.category[0].toUpperCase()}${item.category.substring(1)} · ${item.eventsCount} event${item.eventsCount == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.deepOrange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'x${item.totalQuantityUsed}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        children: item.usageHistory.map((h) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.event_note, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    h.eventTitle,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  _fmtDate(h.eventDate),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'x${h.quantityUsed}',
                    style: const TextStyle(
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Documents Tab ──────────────────────────────────────────────────────────

class _DocumentsTab extends StatelessWidget {
  final UserAnalysisDocuments documents;
  const _DocumentsTab({required this.documents});

  @override
  Widget build(BuildContext context) {
    final approved = documents.items
        .where((d) => d.status.trim().toLowerCase() == 'approved')
        .toList();
    if (approved.isEmpty) {
      return const Center(child: Text('No approved documents found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: approved.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _DocumentCard(item: approved[i]),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentItem item;
  const _DocumentCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo thumbnail
            GestureDetector(
              onTap: item.photoUrl != null
                  ? () => _showPhotoDialog(context, item)
                  : null,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: item.photoUrl != null
                    ? Image.network(
                        item.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, color: Colors.grey),
                      )
                    : const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.typeDisplay,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _StatusBadge(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (item.assignedAt != null)
                    _MetaChip(
                      icon: Icons.date_range,
                      label: 'Assigned: ${_fmtDate(item.assignedAt)}',
                    ),
                  if (item.returnedAt != null)
                    _MetaChip(
                      icon: Icons.assignment_return,
                      label: 'Returned: ${_fmtDate(item.returnedAt)}',
                    ),
                  if (item.notes != null && item.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.notes!,
                      style: TextStyle(
                        fontSize: 11,
                        color: item.status == 'rejected'
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoDialog(BuildContext context, DocumentItem item) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(item.typeDisplay),
              backgroundColor: AppColors.primaryMaroon,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            InteractiveViewer(
              child: Image.network(item.photoUrl!, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoRow> rows;
  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.primaryMaroon,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: rows.map((r) => r.build(context)).toList()),
          ),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: TextStyle(
              fontSize: 12,
              color: valueColor,
              fontWeight: label.isEmpty ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryMaroon),
      ),
      child: Text(
        role.replaceAll('_', ' ').toUpperCase(),
        style: const TextStyle(
          color: AppColors.primaryMaroon,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        bg = Colors.green;
        break;
      case 'pending':
        bg = Colors.orange;
        break;
      case 'rejected':
        bg = Colors.red;
        break;
      default:
        bg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AttendanceStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _AttendanceStat({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChips extends StatelessWidget {
  final List<_Chip> chips;
  const _SummaryChips({required this.chips});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((c) => c.build(context)).toList(),
    );
  }
}

class _Chip {
  final String label;
  final IconData icon;
  final Color color;
  const _Chip({required this.label, required this.icon, required this.color});

  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, color: Colors.white, size: 16),
    label: Text(label, style: const TextStyle(color: Colors.white)),
    backgroundColor: color,
  );
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

String _fmtDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  try {
    final dt = DateTime.parse(raw);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  } catch (_) {
    return raw;
  }
}
