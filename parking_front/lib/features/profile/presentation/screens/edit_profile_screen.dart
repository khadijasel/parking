import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:parking_front/core/constants/app_constants.dart';
import 'package:parking_front/core/widgets/app_feedback.dart';

import '../../data/profile_repository.dart';

const _kBlue = Color(0xFF4A90E2);
const _kDark = Color(0xFF1A1A2E);
const _kMid = Color(0xFF8A9BB5);
const _kBg = Color(0xFFF7F9FC);

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const int _maxAvatarDataUrlLength = 950000;

  final ProfileRepository _profileRepository = ProfileRepository();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _matriculeController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _avatarDataUrl;
  String? _nameInlineError;
  String? _emailInlineError;
  String? _phoneInlineError;
  String? _matriculeInlineError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _matriculeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> user = await _profileRepository.fetchProfile();
      if (!mounted) {
        return;
      }

      _nameController.text = (user['name'] ?? '').toString();
      _emailController.text = (user['email'] ?? '').toString();
      _phoneController.text = (user['phone'] ?? '').toString();
      _matriculeController.text = (user['matricule'] ?? '').toString();
      final String avatar = (user['avatar_data_url'] ?? '').toString().trim();
      _avatarDataUrl = avatar.isEmpty ? null : avatar;

      setState(() {
        _isLoading = false;
      });
    } on ProfileException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = 'Impossible de charger votre profil.';
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _nameInlineError = null;
      _emailInlineError = null;
      _phoneInlineError = null;
      _matriculeInlineError = null;
    });

    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String phone = _phoneController.text.trim();
    final String matricule = _matriculeController.text.trim();

    if (name.isEmpty) {
      setState(() => _nameInlineError = 'Le nom est obligatoire.');
      return;
    }

    if (phone.isEmpty) {
      setState(() => _phoneInlineError = 'Le telephone est obligatoire.');
      return;
    }

    if (matricule.isEmpty) {
      setState(() => _matriculeInlineError = 'Le matricule est obligatoire.');
      return;
    }

    if (email.isEmpty) {
      setState(() => _emailInlineError = 'L\'email est obligatoire.');
      return;
    }

    final RegExp emailRegex = RegExp(AppConstants.emailPattern);
    if (!emailRegex.hasMatch(email)) {
      setState(() => _emailInlineError = 'Veuillez entrer un email valide.');
      return;
    }

    if (_avatarDataUrl != null &&
        _avatarDataUrl!.length > _maxAvatarDataUrlLength) {
      _showError('Photo trop lourde. Choisissez une image plus legere.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _profileRepository.updateProfile(
        name: name,
        email: email,
        phone: phone,
        matricule: matricule,
        avatarDataUrl: _avatarDataUrl,
      );

      if (!mounted) {
        return;
      }

      _showSuccess('Profil mis a jour avec succes.');
      Navigator.pop(context, true);
    } on ProfileException catch (error) {
      if (!mounted) {
        return;
      }

      final String lower = error.message.toLowerCase();
      bool mapped = false;

      setState(() {
        _isSaving = false;
        if (lower.contains('email')) {
          _emailInlineError = error.message;
          mapped = true;
        } else if (lower.contains('phone') || lower.contains('telephone')) {
          _phoneInlineError = error.message;
          mapped = true;
        } else if (lower.contains('matricule')) {
          _matriculeInlineError = error.message;
          mapped = true;
        } else if (lower.contains('name') || lower.contains('nom')) {
          _nameInlineError = error.message;
          mapped = true;
        }
      });

      if (!mapped) {
        _showError(error.message);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showError('Echec de la mise a jour du profil.');
      setState(() => _isSaving = false);
    }
  }

  Future<void> _pickPhoto() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir depuis la galerie'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return;
    }

    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 55,
        maxWidth: 720,
        maxHeight: 720,
      );

      if (file == null) {
        return;
      }

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _showError('Photo invalide.');
        return;
      }

      final String lowerPath = file.path.toLowerCase();
      final String mimeType = lowerPath.endsWith('.png')
          ? 'image/png'
          : lowerPath.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';

      final String dataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      if (dataUrl.length > _maxAvatarDataUrlLength) {
        _showError('Photo trop lourde. Essayez une autre image.');
        return;
      }

      setState(() {
        _avatarDataUrl = dataUrl;
      });
    } catch (_) {
      _showError('Impossible de selectionner la photo.');
    }
  }

  void _removePhoto() {
    setState(() {
      _avatarDataUrl = null;
    });
  }

  void _showError(String message) {
    AppFeedback.showError(context, message);
  }

  void _showSuccess(String message) {
    AppFeedback.showSuccess(context, message);
  }

  ImageProvider<Object>? _avatarProvider() {
    final String? dataUrl = _avatarDataUrl;
    if (dataUrl == null ||
        dataUrl.isEmpty ||
        dataUrl.length > _maxAvatarDataUrlLength) {
      return null;
    }

    try {
      final int commaIndex = dataUrl.indexOf(',');
      if (commaIndex <= 0 || commaIndex >= dataUrl.length - 1) {
        return null;
      }
      final String base64Part = dataUrl.substring(commaIndex + 1);
      final Uint8List bytes = base64Decode(base64Part);
      if (bytes.isEmpty) {
        return null;
      }
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? avatar = _avatarProvider();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.maybePop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: _kDark),
          ),
        ),
        centerTitle: true,
        title: const Text(
          'Modifier le profil',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _kDark,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEAF1FB),
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          image: avatar != null
                              ? DecorationImage(
                                  image: avatar, fit: BoxFit.cover)
                              : null,
                        ),
                        child: avatar == null
                            ? Icon(
                                Icons.person_rounded,
                                size: 60,
                                color: _kBlue.withOpacity(0.5),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _kBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_outlined,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    children: [
                      TextButton(
                        onPressed: _pickPhoto,
                        child: const Text(
                          'Ajouter/Modifier photo',
                          style: TextStyle(
                            color: _kBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_avatarDataUrl != null)
                        TextButton(
                          onPressed: _removePhoto,
                          child: const Text(
                            'Supprimer photo',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Nom complet',
                    hint: 'Votre nom',
                    icon: Icons.person_outline_rounded,
                    controller: _nameController,
                    errorText: _nameInlineError,
                    onChanged: (_) {
                      if (_nameInlineError != null) {
                        setState(() => _nameInlineError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Email',
                    hint: 'nom@exemple.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    controller: _emailController,
                    errorText: _emailInlineError,
                    onChanged: (_) {
                      if (_emailInlineError != null) {
                        setState(() => _emailInlineError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Telephone',
                    hint: 'Votre numero',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    controller: _phoneController,
                    errorText: _phoneInlineError,
                    onChanged: (_) {
                      if (_phoneInlineError != null) {
                        setState(() => _phoneInlineError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Matricule',
                    hint: '16-12345-00-16',
                    icon: Icons.directions_car_outlined,
                    controller: _matriculeController,
                    errorText: _matriculeInlineError,
                    onChanged: (_) {
                      if (_matriculeInlineError != null) {
                        setState(() => _matriculeInlineError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'La ville sera detectee automatiquement par la localisation GPS.',
                      style: TextStyle(fontSize: 12, color: _kMid),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Enregistrer les modifications',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _kDark,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              hintStyle: TextStyle(
                color: _kMid.withOpacity(0.8),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(icon, color: _kMid, size: 22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kBlue, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Colors.redAccent, width: 1.4),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Colors.redAccent, width: 1.6),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
