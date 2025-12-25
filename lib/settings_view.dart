import 'package:flutter/material.dart';
import 'profile_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    void _navigateToProfile() async {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProfileView(),
        ),
      );
      // If profile was updated, return true to parent
      if (result == true) {
        Navigator.pop(context, true);
      }
    }
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
          'Settings',
          style: TextStyle(color: Colors.white70),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person, color: Colors.white70),
            title: const Text(
              'Profile',
              style: TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: _navigateToProfile,
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.restore, color: Colors.white70),
            title: const Text(
              'Recovery subscription',
              style: TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              // Placeholder - not implemented yet
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recovery subscription - Coming soon'),
                  backgroundColor: Colors.grey,
                ),
              );
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.description, color: Colors.white70),
            title: const Text(
              'Terms of Services',
              style: TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              // Placeholder - not implemented yet
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Terms of Services - Coming soon'),
                  backgroundColor: Colors.grey,
                ),
              );
            },
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.privacy_tip, color: Colors.white70),
            title: const Text(
              'Privacy Policy',
              style: TextStyle(color: Colors.white70),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              // Placeholder - not implemented yet
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Privacy Policy - Coming soon'),
                  backgroundColor: Colors.grey,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

