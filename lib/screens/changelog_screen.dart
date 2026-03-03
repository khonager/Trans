import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';

class ChangelogScreen extends StatefulWidget {
  final String? currentVersion;
  const ChangelogScreen({super.key, this.currentVersion});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  List<dynamic> _releases = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReleases();
  }

  Future<void> _fetchReleases() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/khonager/Trans/releases?per_page=100'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        // Sort by published_at descending (newest first)
        data.sort((a, b) {
          final dateA = DateTime.tryParse(a['published_at'] ?? '') ?? DateTime(0);
          final dateB = DateTime.tryParse(b['published_at'] ?? '') ?? DateTime(0);
          return dateB.compareTo(dateA);
        });

        setState(() {
          _releases = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load releases: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading releases: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = TransColors.of(context);
    
    return Scaffold(
      backgroundColor: colors.scaffoldBg,
      appBar: AppBar(
        title: Text("Changelog", style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.scaffoldBg,
        iconTheme: IconThemeData(color: colors.textPrimary),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });
                          _fetchReleases();
                        },
                        child: const Text("Retry"),
                      )
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _releases.length,
                  itemBuilder: (context, index) {
                    final release = _releases[index];
                    final String tagName = release['tag_name'] ?? 'Unknown Version';
                    final String name = release['name'] ?? '';
                    final String body = release['body'] ?? 'No description.';
                    final String dateStr = release['published_at'] ?? '';
                    
                    DateTime? date;
                    if (dateStr.isNotEmpty) {
                      date = DateTime.tryParse(dateStr);
                    }

                    final isCurrent = widget.currentVersion != null && 
                                      (tagName == "v${widget.currentVersion}" || tagName == widget.currentVersion);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: isCurrent 
                            ? Border.all(color: colors.effectiveSeed, width: 2)
                            : Border.all(color: colors.divider.withOpacity(0.5)),
                        boxShadow: isCurrent 
                            ? [
                                BoxShadow(
                                  color: colors.effectiveSeed.withOpacity(0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                )
                              ] 
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colors.effectiveSeed.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isCurrent ? "$tagName (Current)" : tagName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colors.effectiveSeed,
                                  ),
                                ),
                              ),
                              if (date != null)
                                Text(
                                  DateFormat.yMMMd().format(date),
                                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                ),
                            ],
                          ),
                          if (name.isNotEmpty && name != tagName) ...[
                            const SizedBox(height: 12),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          MarkdownBody(
                            data: body,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(color: colors.textPrimary),
                              h1: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 24),
                              h2: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
                              h3: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                              listBullet: TextStyle(color: colors.textPrimary),
                              code: TextStyle(
                                backgroundColor: colors.settingsSectionBg,
                                color: colors.textPrimary,
                                fontFamily: 'monospace',
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: colors.settingsSectionBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onTapLink: (text, href, title) {
                              if (href != null) {
                                launchUrl(Uri.parse(href));
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
