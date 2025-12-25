import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedPronoun;
  String? _selectedLanguage;

  final List<String> _pronounOptions = ['He/Him', 'She/Her', 'They/Them'];
  final Map<String, String> _pronounMapping = {
    'He/Him': 'he/him',
    'She/Her': 'she/her',
    'They/Them': 'they/them',
  };

  final List<String> _languageOptions = [
    'English',
    'Russian',
    'Spanish',
    'French',
    'Chinese (Mandarin)',
  ];

  final Map<String, String> _languageMapping = {
    'English': 'English',
    'Russian': 'Russian',
    'Spanish': 'Spanish',
    'French': 'French',
    'Chinese (Mandarin)': 'Chinese',
  };

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
  }

  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('userName') ?? '';
      
      // Load pronoun - need to reverse map from stored value to display value
      final storedPronoun = prefs.getString('pronoun') ?? 'you';
      // Map stored values to display values
      String displayPronoun = 'They/Them'; // default
      if (storedPronoun == 'he/him' || storedPronoun == 'he' || storedPronoun == 'him') {
        displayPronoun = 'He/Him';
      } else if (storedPronoun == 'she/her' || storedPronoun == 'she' || storedPronoun == 'her') {
        displayPronoun = 'She/Her';
      } else if (storedPronoun == 'they/them' || storedPronoun == 'they' || storedPronoun == 'them') {
        displayPronoun = 'They/Them';
      } else if (storedPronoun == 'you') {
        // 'you' is not in the list, use They/Them as default
        displayPronoun = 'They/Them';
      }
      _selectedPronoun = displayPronoun;
      
      // Load language - need to reverse map from stored value to display value
      final storedLanguage = prefs.getString('language') ?? 'English';
      // Find matching language option
      String displayLanguage = 'English'; // default
      for (var entry in _languageMapping.entries) {
        if (entry.value.toLowerCase() == storedLanguage.toLowerCase()) {
          displayLanguage = entry.key;
          break;
        }
      }
      _selectedLanguage = displayLanguage;
    });
  }

  Future<void> _saveUserPreferences() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _nameController.text);
    await prefs.setString('pronoun', _pronounMapping[_selectedPronoun] ?? 'they/them');
    await prefs.setString('language', _languageMapping[_selectedLanguage] ?? 'English');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true); // Return true to indicate changes were made
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white70),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Name field
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white70),
              decoration: InputDecoration(
                labelText: 'What is your name?',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white70),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            
            // Pronoun field
            DropdownButtonFormField<String>(
              value: _selectedPronoun,
              style: const TextStyle(color: Colors.white70),
              decoration: InputDecoration(
                labelText: 'How should your AI refer to you?',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white70),
                ),
              ),
              dropdownColor: Colors.grey[900],
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              items: _pronounOptions.map((String pronoun) {
                return DropdownMenuItem<String>(
                  value: pronoun,
                  child: Text(
                    pronoun,
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedPronoun = newValue;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select a pronoun';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            
            // Language field
            DropdownButtonFormField<String>(
              value: _selectedLanguage,
              style: const TextStyle(color: Colors.white70),
              decoration: InputDecoration(
                labelText: 'What language do you speak?',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white70),
                ),
              ),
              dropdownColor: Colors.grey[900],
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              items: _languageOptions.map((String language) {
                return DropdownMenuItem<String>(
                  value: language,
                  child: Text(
                    language,
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedLanguage = newValue;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select a language';
                }
                return null;
              },
            ),
            const SizedBox(height: 48),
            
            // Save button
            ElevatedButton(
              onPressed: _saveUserPreferences,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

