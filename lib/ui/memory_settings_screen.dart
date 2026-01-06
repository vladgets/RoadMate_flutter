import 'package:flutter/material.dart';
import '../services/memory_store.dart';

class MemorySettingsScreen extends StatefulWidget {
  const MemorySettingsScreen({super.key});

  @override
  State<MemorySettingsScreen> createState() => _MemorySettingsScreenState();
}

class _MemorySettingsScreenState extends State<MemorySettingsScreen> {
  String _memoryText = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final text = await MemoryStore.readAll();
    setState(() {
      _memoryText = text;
      _loading = false;
    });
  }

  Future<void> _addTestLine() async {
    await MemoryStore.appendLine('Test fact at ${DateTime.now().toIso8601String()}');
    await _refresh();
  }

  Future<void> _clear() async {
    await MemoryStore.clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Long-term Memory'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _addTestLine,
                        icon: const Icon(Icons.add),
                        label: const Text('Add test line'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _memoryText.isEmpty ? '(memory is empty)' : _memoryText,
                        style: const TextStyle(fontSize: 14, height: 1.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}