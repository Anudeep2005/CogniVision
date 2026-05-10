import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import '../providers/auth_provider.dart';

import '../services/location_service.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final LocationService _locationService = LocationService();
  String _pairingToken = "COGN-782-X92"; // Mock token for now

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  void _startLocationTracking() {
    final auth = context.read<AuthProvider>();
    if (auth.user != null) {
      _locationService.startTracking(auth.user!.id);
    }
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    super.dispose();
  }

  void _regenerateToken() {
    setState(() {
      _pairingToken = "COGN-${(100 + (999 - 100) * (0.5)).toInt()}-Y${(10 + (99 - 10) * (0.8)).toInt()}";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pairing token regenerated")),
    );
  }

  void _triggerSOS() {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("EMERGENCY SOS TRIGGERED! Notifications sent to guardians."),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Companion Dashboard",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildWelcomeHeader(user?.email.split('@')[0] ?? "User"),
            const SizedBox(height: 30),
            _buildSOSButton(),
            const SizedBox(height: 40),
            Text(
              "Guardian Pairing",
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            _buildPairingCard(context),
            const SizedBox(height: 40),
            Text(
              "Connected Guardians",
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            _buildGuardianList(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(String name) {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: const Color(0xFF6366F1).withOpacity(0.2),
          child: const Icon(Icons.person_rounded, color: Color(0xFF6366F1), size: 30),
        ),
        const SizedBox(width: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome back,",
              style: GoogleFonts.outfit(fontSize: 16, color: Colors.white54),
            ),
            Text(
              name,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSOSButton() {
    return Semantics(
      button: true,
      label: "Emergency SOS Button",
      hint: "Press and hold to alert all guardians of an emergency.",
      child: GestureDetector(
        onLongPress: _triggerSOS,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.emergency_rounded, color: Colors.white, size: 60),
              const SizedBox(height: 15),
              Text(
                "EMERGENCY SOS",
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Hold to Alert Guardians",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPairingCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: "cognivision://pair?token=$_pairingToken&user=user_id_123",
              version: QrVersions.auto,
              size: 180.0,
            ),
          ),
          const SizedBox(height: 25),
          Text(
            "Unique Connection Token",
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _pairingToken,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF6366F1),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white38, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _pairingToken));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Token copied to clipboard")),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Share.share("Connect with me on Cognivision! My pairing token is: $_pairingToken");
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text("Share"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _regenerateToken,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text("Reset"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuardianList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _buildGuardianTile("Guardian One", "Active", Colors.greenAccent),
          const Divider(color: Colors.white10, height: 20),
          _buildGuardianTile("Guardian Two", "Last active 10m ago", Colors.white38),
        ],
      ),
    );
  }

  Widget _buildGuardianTile(String name, String status, Color statusColor) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.white10,
          child: const Icon(Icons.shield_rounded, color: Colors.white54, size: 20),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              Text(
                status,
                style: TextStyle(color: statusColor, fontSize: 12),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: Colors.white24),
      ],
    );
  }
}
