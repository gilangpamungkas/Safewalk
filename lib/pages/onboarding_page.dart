import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';

/// Data model for each onboarding screen.
class _OnboardingData {
  final IconData icon;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final List<_FeatureTip> tips;

  const _OnboardingData({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.tips,
  });
}

class _FeatureTip {
  final String emoji;
  final String text;
  const _FeatureTip(this.emoji, this.text);
}

// ── 5 onboarding screens ────────────────────────────────────────────────────
const _pages = [
  _OnboardingData(
    icon: Icons.shield,
    iconBgColor: Color(0xFF1565C0),
    title: 'Welcome to SafeWalk',
    subtitle: 'Your personal safety companion for walking in London.',
    tips: [
      _FeatureTip('🗺️', 'Real-time safety scores for every route'),
      _FeatureTip('📊', 'Crime, collision & infrastructure data combined'),
      _FeatureTip('🕐', 'Risk changes by time of day — we account for it'),
    ],
  ),
  _OnboardingData(
    icon: Icons.alt_route,
    iconBgColor: Color(0xFF1976D2),
    title: 'Choose the Safest Route',
    subtitle: 'Compare multiple route options side by side.',
    tips: [
      _FeatureTip('🟢', 'Green paths = well-lit, paved, low crime'),
      _FeatureTip('🔴', 'Red paths = avoid if possible'),
      _FeatureTip('👆', 'Tap a route on the map to see its safety score'),
    ],
  ),
  _OnboardingData(
    icon: Icons.timer,
    iconBgColor: Color(0xFF1E88E5),
    title: 'Arrival Check-in',
    subtitle: 'We\'ll alert your emergency contact if you don\'t check in.',
    tips: [
      _FeatureTip('⏱️', 'Countdown starts when your walk begins'),
      _FeatureTip('✅', 'Tap "I\'m Safe" when you arrive'),
      _FeatureTip('📱', 'SMS alert sent automatically if you miss check-in'),
    ],
  ),
  _OnboardingData(
    icon: Icons.sos,
    iconBgColor: Color(0xFF1565C0),
    title: 'SOS Button',
    subtitle: 'One tap to call 999 or alert your emergency contact.',
    tips: [
      _FeatureTip('📞', 'Tap to call 999 immediately'),
      _FeatureTip('📍', 'Long press to send your location via SMS'),
      _FeatureTip('⚙️', 'Set up your emergency contact in settings'),
    ],
  ),
  _OnboardingData(
    icon: Icons.people,
    iconBgColor: Color(0xFF1976D2),
    title: 'Community Reports',
    subtitle: 'See and share real-time hazards from other walkers.',
    tips: [
      _FeatureTip('💡', 'Report poor lighting, obstructions & incidents'),
      _FeatureTip('🔵', 'Cyan markers = community reports on your route'),
      _FeatureTip('🏠', 'Save frequent destinations for quick access'),
    ],
  ),
];

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _contentController;
  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();
    _setupContentAnimation();
  }

  void _setupContentAnimation() {
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOut),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOut),
    );
    _contentController.forward();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _contentController.reset();
    _contentController.forward();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SafeWalkHomePage()),
    );
  }

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _skip() => _finish();

  @override
  void dispose() {
    _pageController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1565C0),
              Color(0xFF1E88E5),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar ────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Page counter
                    Text(
                      '${_currentPage + 1} / ${_pages.length}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                    // Skip button
                    if (!isLast)
                      TextButton(
                        onPressed: _skip,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Page content ───────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return AnimatedBuilder(
                      animation: _contentController,
                      builder: (context, child) => FadeTransition(
                        opacity: _contentFade,
                        child: SlideTransition(
                          position: _contentSlide,
                          child: child,
                        ),
                      ),
                      child: _buildPageContent(page, index),
                    );
                  },
                ),
              ),

              // ── Dot indicators ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (i) {
                    final isActive = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

              // ── Bottom buttons ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1565C0),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isLast ? 'Get Started' : 'Next',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageContent(_OnboardingData page, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // First screen uses the real app icon, rest use Material icons
          if (index == 0)
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.25),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
            )
          else
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.25),
                  width: 2,
                ),
              ),
              child: Icon(
                page.icon,
                size: 60,
                color: Colors.white,
              ),
            ),

          const SizedBox(height: 32),

          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 12),

          // Subtitle
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withOpacity(0.80),
              height: 1.5,
              fontWeight: FontWeight.w300,
            ),
          ),

          const SizedBox(height: 36),

          // Feature tips
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: page.tips.asMap().entries.map((entry) {
                final i = entry.key;
                final tip = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                      top: i == 0 ? 0 : 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tip.emoji,
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tip.text,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.90),
                            height: 1.4,
                          ),
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
  }
}