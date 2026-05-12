import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../flutterfire_ai_live_api_demo.dart';
import '../providers.dart';
import '../ui_components/ui_components.dart';

import '../services/global_voice_service.dart';
import '../gps_features/user/user_home_screen.dart';
import '../face_features/home_screen.dart' as face_home;

class MainNavigationWrapper extends ConsumerStatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  ConsumerState<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends ConsumerState<MainNavigationWrapper> {
  int _currentIndex = 0;
  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    _voiceService.init();
    _voiceService.onTabChange = (index) => _onTabChanged(index);

    // Initial state setup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentIndex == 0) {
        ref.read(vertexActiveProvider.notifier).state = true;
      }
    });
  }

  final List<Widget> _screens = [
    const FlutterFireAILiveAPIDemo(),
    const UserHomeScreen(),
    const face_home.HomeScreen(),
  ];

  void _onTabChanged(int index) {
    if (!mounted) return;
    
    setState(() => _currentIndex = index);
    
    // Sync Voice Service
    _voiceService.currentIndex = index;

    // Handover Logic
    if (index == 0) {
      // Entering Vertex: Release Global Mic completely
      _voiceService.shutdown();
      ref.read(vertexActiveProvider.notifier).state = true;
    } else {
      // Leaving Vertex: Reactivate Global Mic for GPS/Face
      ref.read(vertexActiveProvider.notifier).state = false;
      _voiceService.init(); // Ensure mic is ready
      
      // Proactive listen on Map
      if (index == 1) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (_currentIndex == 1 && !_voiceService.isListening) {
            _voiceService.startListening();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _currentIndex != 0 
          ? FloatingActionButton(
              onPressed: () {
                if (_voiceService.isListening) {
                  _voiceService.stopListening();
                } else {
                  _voiceService.startListening();
                }
                setState(() {});
              },
              backgroundColor: _voiceService.isListening 
                  ? Colors.redAccent 
                  : Theme.of(context).colorScheme.primary,
              child: Icon(
                _voiceService.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
              ),
            )
          : null,
      bottomNavigationBar: BottomBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.auto_awesome_rounded, 'Vertex'),
            _buildNavItem(1, Icons.explore_rounded, 'GPS'),
            _buildNavItem(2, Icons.face_rounded, 'Face'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _onTabChanged(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isSelected 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            size: 28,
          ),
          const SizedBox(height: 4),
          textLabel(label, isSelected),
        ],
      ),
    );
  }

  Widget textLabel(String label, bool isSelected) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected 
            ? Theme.of(context).colorScheme.primary 
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
      ),
    );
  }
}
