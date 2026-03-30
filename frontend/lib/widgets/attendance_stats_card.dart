import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class AttendanceStatsWidget extends StatelessWidget {
  final int totalVisits;
  final int visitsThisMonth;
  final double? avgDurationMinutes;
  final String lastVisit;
  final bool isLoading;

  const AttendanceStatsWidget({
    super.key,
    required this.totalVisits,
    required this.visitsThisMonth,
    this.avgDurationMinutes,
    required this.lastVisit,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20.0),
        child: CircularProgressIndicator(color: AppTheme.primary),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('Total Visits', '$totalVisits')),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('This Month', '$visitsThisMonth')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Avg Duration',
                avgDurationMinutes != null ? '${avgDurationMinutes!.toStringAsFixed(0)}m' : '-',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard('Last Visit', lastVisit.isEmpty ? '-' : lastVisit)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
