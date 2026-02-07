import 'dart:async';
import 'package:flutter/material.dart';
import '../models/voice_memory.dart';
import '../services/voice_memory_store.dart';

class VoiceMemoriesScreen extends StatefulWidget {
  const VoiceMemoriesScreen({super.key});

  @override
  State<VoiceMemoriesScreen> createState() => _VoiceMemoriesScreenState();
}

class _VoiceMemoriesScreenState extends State<VoiceMemoriesScreen> {
  bool _loading = true;
  List<VoiceMemory> _memories = [];
  List<VoiceMemory> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await VoiceMemoryStore.instance.init();
    if (!mounted) return;
    setState(() {
      _memories = VoiceMemoryStore.instance.allMemories;
      _applyFilter();
      _loading = false;
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _applyFilter());
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _filtered = _memories;
    } else {
      _filtered = VoiceMemoryStore.instance.search(
        text: query,
        limit: 200,
      );
    }
  }

  Future<void> _deleteMemory(VoiceMemory memory) async {
    await VoiceMemoryStore.instance.deleteMemory(memory.id);
    if (!mounted) return;
    setState(() {
      _memories = VoiceMemoryStore.instance.allMemories;
      _applyFilter();
    });
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Memory'),
        content: const Text('Are you sure you want to delete this memory? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDetail(VoiceMemory memory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Date/time
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    _formatDateTime(memory.createdAt),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (memory.address != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        memory.address!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (memory.latitude != null && memory.longitude != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(
                    '${memory.latitude!.toStringAsFixed(4)}, ${memory.longitude!.toStringAsFixed(4)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // Full transcription
              SelectableText(
                memory.transcription,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Voice Memory'),
        content: TextField(
          controller: textController,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'Write your memory...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final text = textController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              await VoiceMemoryStore.instance.createMemory(transcription: text);
              if (!mounted) return;
              setState(() {
                _memories = VoiceMemoryStore.instance.allMemories;
                _applyFilter();
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${h == 1 ? 'hour' : 'hours'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d ${d == 1 ? 'day' : 'days'} ago';
    }
    if (diff.inDays < 30) {
      final w = diff.inDays ~/ 7;
      return '$w ${w == 1 ? 'week' : 'weeks'} ago';
    }
    if (diff.inDays < 365) {
      final m = diff.inDays ~/ 30;
      return '$m ${m == 1 ? 'month' : 'months'} ago';
    }
    final y = diff.inDays ~/ 365;
    return '$y ${y == 1 ? 'year' : 'years'} ago';
  }

  String _formatDateTime(DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final dateStr = loc.formatMediumDate(dt);
    final timeStr = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: use24h,
    );
    return '$dateStr at $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Memories'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search memories...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_stories,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No memories match your search'
                                  : 'No voice memories yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (_searchController.text.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Tell your assistant to save a memory,\nor tap + to add one manually.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final memory = _filtered[index];
                          return _MemoryListItem(
                            memory: memory,
                            relativeTime: _formatRelativeTime(memory.createdAt),
                            onTap: () => _showDetail(memory),
                            onDelete: () => _deleteMemory(memory),
                            onConfirmDelete: () => _confirmDelete(context),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Add memory',
        child: const Icon(Icons.edit_note),
      ),
    );
  }
}

class _MemoryListItem extends StatelessWidget {
  final VoiceMemory memory;
  final String relativeTime;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<bool?> Function() onConfirmDelete;

  const _MemoryListItem({
    required this.memory,
    required this.relativeTime,
    required this.onTap,
    required this.onDelete,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Truncate transcription for title
    final titleText = memory.transcription.length > 100
        ? '${memory.transcription.substring(0, 100)}...'
        : memory.transcription;

    return Dismissible(
      key: Key(memory.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => onConfirmDelete(),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          child: Icon(Icons.auto_stories, color: Colors.blue.shade700, size: 20),
        ),
        title: Text(
          titleText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (memory.address != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      memory.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(
              relativeTime,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
      ),
    );
  }
}
