import 'package:flutter/material.dart';

import '../config/api_endpoints.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class GatDetailsScreen extends StatefulWidget {
  const GatDetailsScreen({super.key});

  @override
  State<GatDetailsScreen> createState() => _GatDetailsScreenState();
}

class _GatDetailsScreenState extends State<GatDetailsScreen> {
  List<Map<String, dynamic>> _gats = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGats();
  }

  Future<void> _loadGats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final gats = await ApiService.fetchGats();
      setState(() {
        _gats = gats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = ApiEndpoints.genericApiFailureMessage;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gat Details'),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: AppColors.textLight,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accentYellow),
            )
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.primaryMaroon),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadGats,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.primaryMaroon,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _gats.isEmpty
          ? const Center(
              child: Text(
                'No gats found',
                style: TextStyle(color: AppColors.primaryMaroon, fontSize: 16),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadGats,
              color: AppColors.accentYellow,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _gats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final gat = _gats[index];
                  return Card(
                    color: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryMaroon,
                        child: Text(
                          '${gat['id'] ?? index + 1}',
                          style: const TextStyle(
                            color: AppColors.accentYellow,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        gat['name'] ?? '-',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        'Gat Pramukh: ${gat['gat_pramukh_name'] ?? '-'}',
                        style: const TextStyle(
                          color: AppColors.primaryMaroon,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
