  Widget _buildPreviousSearches(TransColors colors) {
    if (_recentSearches.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 20, left: 16, right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.cardBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.history, color: colors.sectionHeader, size: 18), const SizedBox(width: 8), Text(AppLocalizations.of(context)!.previousSearches, style: TextStyle(color: colors.sectionHeader, fontWeight: FontWeight.bold, fontSize: 13))]),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recentSearches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, idx) {
                final station = _recentSearches[idx];
                return GestureDetector(
                  onTap: () => _selectStation(station),
                  child: Container(
                    width: 100,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: colors.searchInputFill.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(station.type == 'address' ? Icons.place : Icons.directions_bus, size: 20, color: colors.textPrimary.withValues(alpha: 0.7)),
                        const Spacer(),
                        Text(station.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      )
    );
  }

  Widget _buildFrequentJourneys(TransColors colors) {
    if (_frequentJourneys.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16), // Reduced margin top as it follows prev searches
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(AppLocalizations.of(context)!.frequentJourneys, style: TextStyle(color: colors.sectionHeader, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _frequentJourneys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, idx) {
              final item = _frequentJourneys[idx];
              final from = Station.fromJson(item['from']);
              final to = Station.fromJson(item['to']);
              return GestureDetector(
                onTap: () {
                   setState(() {
                     _fromStation = from;
                     _fromController.text = from.name;
                     _toStation = to;
                     _toController.text = to.name;
                   });
                   _findRoutes();
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: colors.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: colors.navBarSelected.withValues(alpha: 0.2), shape: BoxShape.circle), child: Icon(Icons.bookmark, color: colors.navBarSelected, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(to.name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text("From ${from.name}", style: TextStyle(color: colors.searchHintText, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.searchHintText, size: 20)
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
