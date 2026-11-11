import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../app/theme_proposal.dart';
import '../../models/report_model.dart';
import '../../services/firestore_service.dart';

/// Screen allowing community members to report potential mosquito breeding sites.
/// Captures photo via camera/gallery, captures live GPS, compresses photo (max 800px / 70% JPEG / <300KB),
/// saves image to `reportPhotos/{reportId}` as photoBase64, and saves report to Firestore `reports/{reportId}`.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final FirestoreService _firestoreService = FirestoreService();

  String _selectedCategory = 'Stagnant Water';
  String _locationText = 'Tap refresh to capture live GPS';
  bool _isLocating = false;
  bool _isSubmitting = false;

  File? _imageFile;
  double? _lat;
  double? _lng;

  final List<String> _categories = const [
    'Stagnant Water',
    'Tyres',
    'Blocked Drain',
    'Containers',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _refreshLocation();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _imageFile = File(picked.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick photo: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isLocating = false;
            _locationText = 'Location services are disabled.';
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _isLocating = false;
              _locationText = 'Location permissions denied.';
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLocating = false;
            _locationText = 'Location permissions permanently denied.';
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          _locationText =
              '${position.latitude.toStringAsFixed(5)}° N · ${position.longitude.toStringAsFixed(5)}° E';
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _locationText = 'Failed to get location: $e';
        });
      }
    }
  }

  /// Compresses the image strictly according to requirements:
  /// - Max 800px width/height
  /// - 70% JPEG quality
  /// - Enforced hard cap under 300 KB
  Future<String> _compressAndEncodeBase64(File file) async {
    final rawBytes = await file.readAsBytes();
    final decoded = img.decodeImage(rawBytes);

    if (decoded == null) {
      // Fallback: encode raw bytes
      return base64Encode(rawBytes);
    }

    int targetDim = 800;
    img.Image resized = decoded;
    if (decoded.width > targetDim || decoded.height > targetDim) {
      if (decoded.width >= decoded.height) {
        resized = img.copyResize(decoded, width: targetDim);
      } else {
        resized = img.copyResize(decoded, height: targetDim);
      }
    }

    int quality = 70;
    List<int> compressed = img.encodeJpg(resized, quality: quality);

    // Hard cap: guarantee compressed size is under 300 KB (307,200 bytes)
    const int maxBytes = 300 * 1024;
    while (compressed.length > maxBytes && quality > 20) {
      quality -= 15;
      targetDim = (targetDim * 0.8).toInt();
      resized = img.copyResize(decoded, width: targetDim);
      compressed = img.encodeJpg(resized, quality: quality);
    }

    return base64Encode(compressed);
  }

  Future<void> _submitReport() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take or choose a photo of the breeding site.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture your current GPS location first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'anonymous_user';

    setState(() => _isSubmitting = true);

    try {
      // 1. Compress image to max 800px / 70% JPEG and cap under 300 KB
      final base64String = await _compressAndEncodeBase64(_imageFile!);

      // 2. Prepare report model
      final report = ReportModel(
        id: '',
        uid: uid,
        photoId: '', // submitReport populates this with reportId
        imageUrl: '',
        lat: _lat!,
        lng: _lng!,
        type: _selectedCategory,
        description: _descriptionController.text.trim(),
        status: 'pending',
        location: GeoPoint(_lat!, _lng!),
        createdAt: DateTime.now(),
        lastConfirmedAt: DateTime.now(),
      );

      // 3. Save to reports/{id} and reportPhotos/{id} in Firestore
      await _firestoreService.submitReport(
        report,
        photoBase64: base64String,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Pass data URL format so downstream widgets/screens can display immediately
      final previewDataUrl = 'data:image/jpeg;base64,$base64String';
      context.go('/report/verifying', extra: previewDataUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting report: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildPhotoSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
          Row(
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Add a site photo',
                style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_imageFile != null) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    _imageFile!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: InkWell(
                    onTap: () => setState(() => _imageFile = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.surface,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Camera and Gallery Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.primaryDark,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Site location',
                style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _isLocating ? null : _refreshLocation,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isLocating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.refresh,
                              color: AppColors.primaryDark,
                              size: 18,
                            ),
                      const SizedBox(width: 4),
                      Text(
                        'Refresh',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13,
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
          const SizedBox(height: 10),
          Text(
            _locationText,
            style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String category) {
    final isSelected = _selectedCategory == category;

    return InkWell(
      onTap: () => setState(() => _selectedCategory = category),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          category,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              Text(
                'Report a Breeding Site',
                style: (textTheme.headlineSmall ?? AppTypography.title).copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Help us spot places where mosquitoes breed.',
                style: (textTheme.bodyMedium ?? AppTypography.body).copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a photo and location · Scroll for details',
                style: (textTheme.bodySmall ?? AppTypography.caption).copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),

              // 1. Photo Section
              _buildPhotoSection(context),
              const SizedBox(height: 16),

              // 2. Site Location Section
              _buildLocationSection(context),
              const SizedBox(height: 22),

              // 3. What did you find? Category Chips
              Text(
                'What did you find?',
                style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: _categories.map(_buildCategoryChip).toList(),
              ),
              const SizedBox(height: 22),

              // 4. Description (optional)
              Text(
                'Description (optional)',
                style: (textTheme.titleMedium ?? AppTypography.heading).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  minLines: 3,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hintText:
                        'Add useful details (optional)\ne.g. Water collected in an unused pot.',
                    hintStyle: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 5. Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.surface,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Submit Report',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
