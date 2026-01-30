import 'package:flutter/material.dart';
import '../services/reminders.dart';


class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loading = true;
  List<Reminder> _reminders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await RemindersService.instance.init();
      final upcoming = await RemindersService.instance.listUpcoming();
      if (!mounted) return;
      setState(() {
        _reminders = upcoming;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatWhen(BuildContext context, DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);

    final dateStr = loc.formatMediumDate(dt);
    final timeStr = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: use24h,
    );

    return '$dateStr $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to load reminders:\n$_error'),
                  ),
                )
              : (_reminders.isEmpty
                  ? const Center(child: Text('No upcoming reminders'))
                  : ListView.separated(
                      itemCount: _reminders.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final r = _reminders[index];
                        final dt = r.scheduledAtLocal;
                        final when = _formatWhen(context, dt);
                        return ListTile(
                          title: Text(r.text),
                          subtitle: Text('At $when'),
                        );
                      },
                    ))),
    );
  }
}

