import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

/// Full-screen immersive player for review videos (customer side).
class ReviewVideoPlayerPage extends StatefulWidget {
  const ReviewVideoPlayerPage({
    super.key,
    required this.videoUrl,
    required this.reviewerName,
    required this.rating,
  });

  final String videoUrl;
  final String reviewerName;
  final int rating;

  @override
  State<ReviewVideoPlayerPage> createState() => _ReviewVideoPlayerPageState();
}

class _ReviewVideoPlayerPageState extends State<ReviewVideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  bool _muted = true;
  bool _isScrubbing = false;
  double _scrubValue = 0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final uri = Uri.tryParse(widget.videoUrl);
      if (uri == null) {
        setState(() {
          _loading = false;
          _error = 'Invalid video URL';
        });
        return;
      }
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.setVolume(0);
      controller.addListener(_onVideoTick);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
        _muted = true;
      });
      await controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to play this video.';
      });
    }
  }

  void _onVideoTick() {
    if (!mounted || _isScrubbing) return;
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _reviewerInitials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'R';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    final nextMuted = !_muted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() => _muted = nextMuted);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final safeRating = widget.rating.clamp(0, 5);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(child: CupertinoActivityIndicator(color: Colors.white))
          else if (_error != null)
            Center(
              child: Text(
                _error!,
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            )
          else if (controller != null && controller.value.isInitialized)
            GestureDetector(
              onTap: _togglePlayPause,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),

          // Top gradient + controls
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.close, color: Colors.white, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                'Close',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Review video',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 72),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Center play/pause
          if (!_loading && _error == null && controller != null)
            Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),

          // Bottom gradient + reviewer + scrub
          if (!_loading && _error == null && controller != null && controller.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: const Color(0xFF5D4037),
                                child: Text(
                                  _reviewerInitials(widget.reviewerName),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.reviewerName,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < safeRating ? Icons.star : Icons.star_border,
                                    size: 14,
                                    color: const Color(0xFFFFC107),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              _formatDuration(controller.value.position),
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: SliderComponentShape.noOverlay,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: _isScrubbing
                                      ? _scrubValue
                                      : controller.value.duration.inMilliseconds == 0
                                          ? 0
                                          : controller.value.position.inMilliseconds /
                                              controller.value.duration.inMilliseconds,
                                  onChangeStart: (_) {
                                    setState(() => _isScrubbing = true);
                                  },
                                  onChanged: (v) {
                                    setState(() => _scrubValue = v);
                                  },
                                  onChangeEnd: (v) async {
                                    final target = controller.value.duration * v;
                                    await controller.seekTo(target);
                                    if (mounted) {
                                      setState(() => _isScrubbing = false);
                                    }
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _formatDuration(controller.value.duration),
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            IconButton(
                              onPressed: _toggleMute,
                              icon: Icon(
                                _muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
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
}
