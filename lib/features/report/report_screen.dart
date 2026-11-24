import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';
import '../../services/report_write_plan.dart';
import '../ai_validation/capture_result.dart';
import '../ai_validation/capture_service.dart';
import '../ai_validation/geohash.dart' as geohash;
import '../ai_validation/report_check_controller.dart';
import '../ai_validation/report_decision.dart' show kStillPresentMessage;
import '../ai_validation/report_outcome.dart';
import '../map/location_preview_map.dart';

/// Shows the "UI FLOW" stage bar and the Simulate Approved/Rejected buttons.
/// Off by default; enable with: flutter run --dart-define=DEMO_CONTROLS=true
const bool _demoControls = bool.fromEnvironment('DEMO_CONTROLS');

/// The step states of the AI report verification workflow:
/// 1. [form]         - Image 1: "Report a Breeding Site"
/// 2. [checking]     - Image 2: "AI is Checking Your Report"
/// 3. [approved]     - Image 3: "Report Verified Successfully"
/// 4. [rejected]     - Image 4: "Report Not Approved"
/// 5. [stillPresent] - the site is already reported; it was marked as still
///    present instead of creating a new report (no points)
enum ReportFlowStep {
  form,
  checking,
  approved,
  rejected,
  stillPresent,
}

/// Progress of saving the checked report to Firestore.
enum _SaveStatus { idle, saving, saved, failed }

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.onDecision});

  /// Called once when the AI check ends in a final decision (approved, still
  /// present or rejected). The screen saves the result itself; do not save it
  /// again from here.
  /// Not called when the check itself fails (the user gets a retry instead).
  final ReportDecisionCallback? onDecision;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  ReportFlowStep _currentStep = ReportFlowStep.form;

  // Animation controller for the AI scanning beam
  late final AnimationController _scanController;
  late final Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanAnimation = CurvedAnimation(
      parent: _scanController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  // Live camera photo + GPS fix from captureReportPhoto(); null until taken.
  CaptureResult? _capture;
  bool _capturing = false;

  Future<void> _takePhoto() async {
    setState(() => _capturing = true);
    final result = await captureReportPhoto();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      if (result.isOk) _capture = result;
    });
    if (!result.isOk && !result.wasCancelled) _showMessage(result.message!);
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // AI check state. _outcome is set when a final decision was made;
  // _checkError is set when the check itself failed (offer a retry).
  final ReportCheckController _checker = ReportCheckController();
  ReportOutcome? _outcome;
  CheckPhase _checkPhase = CheckPhase.validating;
  String? _checkError;
  int _checkToken = 0; // ignores results of a check that was abandoned

  void _submitReport() {
    if (_capture?.isOk != true) return;
    setState(() {
      _currentStep = ReportFlowStep.checking;
    });
    _runCheck();
  }

  Future<void> _runCheck() async {
    final capture = _capture;
    if (capture == null || !capture.isOk) return;
    final token = ++_checkToken;
    setState(() {
      _outcome = null;
      _checkError = null;
      _checkPhase = CheckPhase.validating;
    });

    final result = await _checker.check(
      capture,
      onPhase: (phase) {
        if (mounted && token == _checkToken) {
          setState(() => _checkPhase = phase);
        }
      },
    );
    if (!mounted || token != _checkToken) return;

    if (!result.isSuccess) {
      if (kDebugMode) debugPrint('Report check failed: ${result.detail}');
      setState(() => _checkError = result.userMessage);
      return;
    }
    final outcome = result.outcome!;
    setState(() {
      _outcome = outcome;
      _currentStep = outcome.eligible
          ? ReportFlowStep.approved
          : outcome.isStillPresent
              ? ReportFlowStep.stillPresent
              : ReportFlowStep.rejected;
    });
    _beginSave(outcome);
    widget.onDecision?.call(outcome);
  }

  // Saving the checked report (separate from the AI check, so Retry only
  // re-runs the save). One report id and one compressed photo per outcome: a
  // retry reuses both, so it can never create a second report or award a second
  // set of points.
  _SaveStatus _saveStatus = _SaveStatus.idle;
  String? _reportId;
  String? _photoBase64;
  int _saveToken = 0; // ignores the result of a save that was abandoned

  void _beginSave(ReportOutcome outcome) {
    _reportId = null;
    _photoBase64 = null;
    _saveOutcome(outcome);
  }

  void _retrySave() {
    final outcome = _outcome;
    if (outcome != null) _saveOutcome(outcome);
  }

  /// Compresses to max 800px / 70% JPEG, capped under 300 KB, as Base64.
  String _compressToBase64(Uint8List jpegBytes) {
    try {
      final decoded = img.decodeImage(jpegBytes);
      if (decoded == null) return base64Encode(jpegBytes);
      int targetDim = 800;
      img.Image resized = decoded;
      if (decoded.width > targetDim || decoded.height > targetDim) {
        resized = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: targetDim)
            : img.copyResize(decoded, height: targetDim);
      }
      int quality = 70;
      List<int> compressed = img.encodeJpg(resized, quality: quality);
      const int maxBytes = 300 * 1024;
      while (compressed.length > maxBytes && quality > 20) {
        quality -= 15;
        targetDim = (targetDim * 0.8).toInt();
        resized = img.copyResize(decoded, width: targetDim);
        compressed = img.encodeJpg(resized, quality: quality);
      }
      return base64Encode(compressed);
    } catch (_) {
      return base64Encode(jpegBytes);
    }
  }

  Future<void> _saveOutcome(ReportOutcome outcome) async {
    final token = ++_saveToken;
    setState(() => _saveStatus = _SaveStatus.saving);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Not signed in');

      final existingReportId = outcome.existingReportId;
      if (outcome.isStillPresent && existingReportId != null) {
        // Already reported: update that report only. No new report, no photo,
        // no points. _reportId is reused as this confirmation's id, so Retry
        // cannot count the confirmation twice.
        final service = FirestoreService();
        await service.markReportStillPresent(
          existingReportId,
          confirmationId: _reportId ??= service.newReportId(),
        );
        if (!mounted || token != _saveToken) return;
        setState(() => _saveStatus = _SaveStatus.saved);
        return;
      }

      final capture = outcome.capture;
      final lat = capture.latitude!;
      final lng = capture.longitude!;
      final category = outcome.validation.category.wireValue;
      final isEligible = outcome.eligible;

      final service = FirestoreService();
      final reportId = _reportId ??= service.newReportId();
      // Only a valid report stores its photo (in reportPhotos).
      final photo = isEligible
          ? (_photoBase64 ??= _compressToBase64(capture.jpegBytes!))
          : null;

      final report = ReportModel(
        id: reportId,
        uid: user.uid,
        lat: lat,
        lng: lng,
        type: category,
        status: isEligible ? reportStatusValid : reportStatusRejected,
        location: GeoPoint(lat, lng),
        // Precision 9 with our encoder, so the duplicate check can find it.
        geohash: geohash.encode(lat, lng, 9),
        createdAt: DateTime.now(),
        lastConfirmedAt: DateTime.now(),
        aiCategory: category,
        aiConfidence: outcome.validation.confidence,
        aiReason: outcome.validation.reason,
      );

      await service.submitReport(
        report,
        photoBase64: photo,
        reportId: reportId,
      );
      if (!mounted || token != _saveToken) return;
      setState(() => _saveStatus = _SaveStatus.saved);
    } catch (e) {
      if (kDebugMode) debugPrint('Saving the report failed: $e');
      if (!mounted || token != _saveToken) return;
      setState(() => _saveStatus = _SaveStatus.failed);
    }
  }

  void _resetToForm() {
    _checkToken++; // abandon any check still running
    _saveToken++; // and ignore the result of any save still running
    setState(() {
      _capture = null;
      _outcome = null;
      _checkError = null;
      _saveStatus = _SaveStatus.idle;
      _reportId = null;
      _photoBase64 = null;
      _currentStep = ReportFlowStep.form;
    });
  }

  /// The captured photo, or a plain placeholder when there is none.
  Widget _buildPhotoImage(double height) {
    final bytes = _capture?.jpegBytes;
    Widget placeholder() => Container(
          height: height,
          color: AppColors.primaryLight,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_outlined,
            size: 48,
            color: AppColors.primary,
          ),
        );
    if (bytes != null) {
      return Image.memory(
        bytes,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder(),
      );
    }
    return placeholder();
  }

  /// Coordinates and accuracy of the capture (sample text when demoing).
  String _captureCaption() {
    final c = _capture;
    if (c == null || !c.isOk) return 'Sample campus garden · 13 Oct, 9:41 AM';
    return '${c.latitude!.toStringAsFixed(5)}, '
        '${c.longitude!.toStringAsFixed(5)} · ±${c.accuracyMeters!.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Demo-only stage bar (flutter run --dart-define=DEMO_CONTROLS=true)
            if (_demoControls) _buildStageSwitcherBar(),

            // Active step content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _buildCurrentStepContent(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStepContent(BuildContext context) {
    switch (_currentStep) {
      case ReportFlowStep.form:
        return _buildFormStep(context);
      case ReportFlowStep.checking:
        return _buildCheckingStep(context);
      case ReportFlowStep.approved:
        return _buildApprovedStep(context);
      case ReportFlowStep.rejected:
        return _buildRejectedStep(context);
      case ReportFlowStep.stillPresent:
        return _buildStillPresentStep(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Quick Stage Switcher Bar
  // ---------------------------------------------------------------------------
  Widget _buildStageSwitcherBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'UI FLOW',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStepPill('1. Report', ReportFlowStep.form),
                  const SizedBox(width: 6),
                  _buildStepPill('2. Checking', ReportFlowStep.checking),
                  const SizedBox(width: 6),
                  _buildStepPill('3. Approved', ReportFlowStep.approved),
                  const SizedBox(width: 6),
                  _buildStepPill('4. Rejected', ReportFlowStep.rejected),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => context.push('/profile/reports'),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt, size: 14, color: AppColors.primaryDark),
                  SizedBox(width: 4),
                  Text(
                    'Reports',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(String label, ReportFlowStep step) {
    final isSelected = _currentStep == step;
    return InkWell(
      onTap: () => setState(() => _currentStep = step),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 1: Report a Breeding Site (Image 1)
  // ---------------------------------------------------------------------------
  Widget _buildFormStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Header Title & Subtitle
        Text(
          'Report a Breeding Site',
          style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A clear photo helps AI validate your report.',
          style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),

        // Card 1: Site photo
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Site photo',
                    style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    _capture == null ? 'No photo yet' : '1 photo added',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Live photo preview (placeholder until a photo is taken)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _capture == null
                    ? Container(
                        height: 170,
                        color: AppColors.primaryLight,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      )
                    : Image.memory(
                        _capture!.jpegBytes!,
                        height: 170,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(height: 14),

              // Take Live Photo Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _capturing ? null : _takePhoto,
                  icon: _capturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 20),
                  label: Text(
                    _capture != null ? 'Retake Live Photo' : 'Take Live Photo',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.border, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 2: Location card with a real map preview
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            children: [
              // Read-only OpenStreetMap preview of the captured location
              LocationPreviewMap(
                latitude: _capture?.latitude,
                longitude: _capture?.longitude,
                accuracyMeters: _capture?.accuracyMeters,
              ),

              // Location info row
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primaryDark,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _capture == null
                                ? 'Location not added yet'
                                : 'Location added',
                            style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _capture == null
                                ? 'Take a photo to add your location'
                                : '${_capture!.latitude!.toStringAsFixed(5)}, '
                                    '${_capture!.longitude!.toStringAsFixed(5)}'
                                    ' · ±${_capture!.accuracyMeters!.round()} m',
                            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Water guidance section
        Text(
          'Make the water clearly visible',
          style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Photograph standing water, discarded tyres, open containers or blocked drains in good light.',
          style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        // Submit Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            // Enabled only after a camera photo with a valid GPS fix.
            onPressed: _capture?.isOk == true ? _submitReport : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              disabledForegroundColor: AppColors.textSecondary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Submit Report',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Footnote (demo only: the balance here is not real)
        if (_demoControls) ...[
          Center(
            child: Text(
              'Demo report',
              style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 2: AI is Checking Your Report (Image 2)
  // ---------------------------------------------------------------------------
  Widget _buildCheckingStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Top Tag
        const Text(
          'REPORT VALIDATION',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),

        // Title
        Text(
          'AI is Checking Your\nReport',
          style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        Text(
          "We're checking your image for a possible mosquito breeding site.",
          style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),

        // Photo with Scanner Viewfinder Reticle Overlay
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _buildPhotoImage(210),
            ),

            // Viewfinder + scan line only while checking (hidden on error)
            if (_checkError == null) ...[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CustomPaint(
                  painter: _ViewfinderReticlePainter(),
                ),
              ),
            ),

            // Animated Horizontal Scan Line
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _scanAnimation,
                builder: (context, _) {
                  return FractionallySizedBox(
                    alignment: Alignment(0, (_scanAnimation.value * 2) - 1),
                    heightFactor: 0.05,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white,
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // Location & Time under image
        Row(
          children: [
            const Icon(
              Icons.location_on_outlined,
              color: AppColors.primaryDark,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _captureCaption(),
              style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Analyzing card (live progress, or an error with retry)
        _buildAnalyzingCard(textTheme),
        const SizedBox(height: 14),

        // Points Info Highlight Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: AppColors.primaryDark,
                size: 22,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Each valid report earns $kPointsPerValidReport points. Your balance updates after your report is saved.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: AppColors.primaryDark,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Demo-only: jump to an outcome without running the AI check.
        if (_demoControls) ..._buildDemoControls(textTheme),
        const SizedBox(height: 20),
      ],
    );
  }

  /// "Analyzing site details" card: progress while the check runs, or the
  /// error with Try again / Retake photo when the check could not complete.
  Widget _buildAnalyzingCard(TextTheme textTheme) {
    final error = _checkError;
    final validating = _checkPhase == CheckPhase.validating;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: error != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppColors.errorText,
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Check not completed',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _runCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Try again',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _resetToForm,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Retake photo',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analyzing site details',
                  style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Indeterminate progress: the AI gives no percentage.
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: const LinearProgressIndicator(
                    minHeight: 7,
                    backgroundColor: AppColors.primaryLight,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 16),

                _buildChecklistItem(
                  icon: Icons.check_circle_outline,
                  iconColor: AppColors.primaryDark,
                  text: 'Photo received',
                  textColor: AppColors.textPrimary,
                ),
                const SizedBox(height: 12),
                _buildChecklistItem(
                  icon: validating ? Icons.crop_free : Icons.check_circle_outline,
                  iconColor: AppColors.primaryDark,
                  text: 'Checking for standing water',
                  textColor: AppColors.textPrimary,
                  busy: validating,
                ),
                const SizedBox(height: 12),
                _buildChecklistItem(
                  icon: validating ? Icons.access_time : Icons.crop_free,
                  iconColor:
                      validating ? AppColors.textSecondary : AppColors.primaryDark,
                  text: 'Checking if this site is already reported',
                  textColor:
                      validating ? AppColors.textSecondary : AppColors.textPrimary,
                  busy: !validating,
                ),
              ],
            ),
    );
  }

  /// Approved view: the buttons that leave the screen are enabled once the
  /// report is saved (or in the demo, where nothing is saved).
  bool get _canLeaveApproved =>
      _outcome == null || _saveStatus == _SaveStatus.saved;

  /// The points banner on the Approved view. "points added" is shown only after
  /// the save succeeded; if it failed the banner says so and offers Retry (which
  /// re-runs only the save) and Retake photo.
  Widget _buildPointsBanner() {
    final failed = _outcome != null && _saveStatus == _SaveStatus.failed;
    final saving = _outcome != null &&
        (_saveStatus == _SaveStatus.saving || _saveStatus == _SaveStatus.idle);

    final String title;
    final String subtitle;
    if (_outcome == null) {
      // Demo controls only: illustrative text, nothing is saved.
      title = '+$kPointsPerValidReport Points Earned';
      subtitle = 'Points added to your balance.';
    } else if (failed) {
      title = "Couldn't save your report";
      subtitle = 'Your points were not added. Check your connection and try '
          'again.';
    } else if (saving) {
      title = 'Saving your report…';
      subtitle = 'Your points are added once it is saved.';
    } else {
      title = '+$kPointsPerValidReport points added';
      subtitle = 'Your report is saved.';
    }

    final color = failed ? AppColors.errorText : AppColors.primaryDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: failed ? AppColors.errorBg : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              saving
                  ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: color,
                      ),
                    )
                  : Icon(
                      failed ? Icons.error_outline : Icons.spa_outlined,
                      color: color,
                      size: 26,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        color: color.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _retrySave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: _resetToForm,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.primaryDark,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Retake photo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildDemoControls(TextTheme textTheme) {
    return [
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _currentStep = ReportFlowStep.approved),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Simulate Approved'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep = ReportFlowStep.rejected),
              icon: const Icon(Icons.close, size: 18, color: AppColors.errorText),
              label: const Text(
                'Simulate Rejected',
                style: TextStyle(color: AppColors.errorText),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.errorText),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          'Demo controls on · Illustrative states only',
          style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    ];
  }

  Widget _buildChecklistItem({
    required IconData icon,
    required Color iconColor,
    required String text,
    required Color textColor,
    bool busy = false,
  }) {
    return Row(
      children: [
        busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                ),
              )
            : Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 3: Report Verified Successfully (Image 3)
  // ---------------------------------------------------------------------------
  Widget _buildApprovedStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Tag
        const Text(
          'REPORT RESULT · APPROVED',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),

        // Big Green Checkmark Icon Badge
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check,
            color: AppColors.primaryDark,
            size: 32,
          ),
        ),
        const SizedBox(height: 14),

        // Title
        Text(
          'Report Verified\nSuccessfully',
          style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        Text(
          'Thank you for helping make your community safer.',
          style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 18),

        // Card with Image & Detected Site Type
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: _buildPhotoImage(170),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DETECTED SITE TYPE',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _outcome?.validation.category.label ??
                          'Discarded tyre with standing water',
                      style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (_outcome != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _outcome!.decision.reason,
                        style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _captureCaption(),
                      style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Points banner: saving / saved (points added) / save failed
        _buildPointsBanner(),
        const SizedBox(height: 20),

        // Action Buttons (only once the report is saved, so an unsaved report
        // cannot be left behind by accident)
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _canLeaveApproved ? () => context.go('/map') : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'View on Map',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _canLeaveApproved ? _resetToForm : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Submit Another Report',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Footnote
        Center(
          child: Text(
            _outcome == null
                ? 'Illustrative report · Fictional location'
                : 'Checked by AI from a live photo and GPS location',
            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 4: Report Not Approved (Image 4)
  // ---------------------------------------------------------------------------
  Widget _buildRejectedStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Tag
        Text(
          _outcome == null
              ? 'REPORT RESULT · REJECTED ALTERNATIVE'
              : 'REPORT RESULT · NOT APPROVED',
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),

        // Subtitle
        Text(
          _outcome == null
              ? 'An alternative outcome.'
              : 'We checked your photo and location.',
          style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),

        // Card 1: Report Not Approved
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The photo that was checked
              if (_capture?.jpegBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _buildPhotoImage(150),
                ),
                const SizedBox(height: 14),
              ],

              // Red Signal Slash Icon
              const Icon(
                Icons.portable_wifi_off_outlined,
                color: AppColors.errorText,
                size: 38,
              ),
              const SizedBox(height: 14),

              Text(
                'Report Not Approved',
                style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                _outcome?.decision.reason ??
                    'This photo does not clearly show standing water. No points were awarded.',
                style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _resetToForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Retake photo',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 2: 0 Points Earned Highlight
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.errorText.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.errorText,
                size: 26,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '0 Points Earned',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.errorText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _outcome == null
                          ? 'Your points balance remains unchanged.'
                          : 'This photo was not approved for points.',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Card 3: For your next report
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For your next report',
                style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              _buildTipItem(
                icon: Icons.fact_check_outlined,
                text: 'Photograph the site itself, not a screen or printout.',
              ),
              const SizedBox(height: 12),
              _buildTipItem(
                icon: Icons.camera_alt_outlined,
                text: 'Use a sharp, well-lit photo that clearly shows standing water.',
              ),
              const SizedBox(height: 12),
              _buildTipItem(
                icon: Icons.location_on_outlined,
                text: 'Confirm the location matches the photo.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Footnote
        Center(
          child: Text(
            _outcome == null
                ? 'Illustrative rejection · Not part of the approved path'
                : (_saveStatus == _SaveStatus.failed
                    ? "This result couldn't be recorded. You can still retake "
                        'the photo.'
                    : 'Retake the photo to try again'),
            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STEP 5: Already reported, marked as still present
  // ---------------------------------------------------------------------------
  Widget _buildStillPresentStep(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final failed = _saveStatus == _SaveStatus.failed;
    final saving =
        _saveStatus == _SaveStatus.saving || _saveStatus == _SaveStatus.idle;
    final color = failed ? AppColors.errorText : AppColors.primaryDark;

    final String bannerTitle;
    final String bannerSubtitle;
    if (failed) {
      bannerTitle = "Couldn't update the report";
      bannerSubtitle = 'Check your connection and try again.';
    } else if (saving) {
      bannerTitle = 'Updating the existing report…';
      bannerSubtitle = 'This only takes a moment.';
    } else {
      bannerTitle = 'Marked as still present';
      bannerSubtitle = 'No new report was created, so no points were added.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          'REPORT RESULT · ALREADY REPORTED',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryDark,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.update,
            color: AppColors.primaryDark,
            size: 30,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Site Already\nReported',
          style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _outcome?.decision.reason ?? kStillPresentMessage,
          style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: _buildPhotoImage(170),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _captureCaption(),
                  style: (textTheme.bodySmall ?? AppTypography.caption)
                      .copyWith(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: failed ? AppColors.errorBg : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
          ),
          child: Row(
            children: [
              saving
                  ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: color,
                      ),
                    )
                  : Icon(
                      failed ? Icons.error_outline : Icons.check_circle_outline,
                      color: color,
                      size: 26,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bannerTitle,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bannerSubtitle,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        color: color.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (failed) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _retrySave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ] else ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : () => context.go('/map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'View on Map',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: saving ? null : _resetToForm,
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primaryDark,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              failed ? 'Retake photo' : 'Report a Different Site',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTipItem({
    required IconData icon,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryDark, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for the camera reticle corner brackets in Step 2
class _ViewfinderReticlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const cornerLength = 24.0;

    // Top-Left ┌
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLength), paint);

    // Top-Right ┐
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - cornerLength, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, cornerLength), paint);

    // Bottom-Left └
    canvas.drawLine(Offset(0, size.height), Offset(cornerLength, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - cornerLength), paint);

    // Bottom-Right ┘
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - cornerLength, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - cornerLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
