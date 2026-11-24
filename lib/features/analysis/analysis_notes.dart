/// A link that backs up a written insight note.
class NoteSource {
  const NoteSource({required this.label, required this.url});

  /// Short name of the source, shown before the link.
  final String label;
  final String url;
}

/// Written insight notes for the Analysis screen.
///
/// Each note says only what its sources say. The sources were read when the
/// notes were written; see docs/ANALYSIS_DATA.md.
class WrittenInsight {
  const WrittenInsight({
    required this.title,
    required this.text,
    required this.sources,
  });

  final String title;
  final String text;
  final List<NoteSource> sources;
}

const NoteSource _tisseraEid2020 = NoteSource(
  label:
      'Tissera et al., Emerging Infectious Diseases, April 2020 '
      '(National Dengue Control Unit authors)',
  url: 'https://wwwnc.cdc.gov/eid/article/26/4/19-0435',
);

const List<WrittenInsight> writtenInsights = [
  WrittenInsight(
    title: 'Rain and mosquito breeding',
    text:
        'In Sri Lanka, seasonal dengue epidemics mostly affect areas with '
        'more than 2,500 mm of rain a year. In the 2017 epidemic, a quarter of '
        'the whole year\'s cases were reported 5 weeks after the southwest '
        'monsoon started.',
    sources: [_tisseraEid2020],
  ),
  WrittenInsight(
    title: 'Rubbish that holds water',
    text:
        'Mosquito surveys in the Western Province found that more than half '
        'of Aedes aegypti breeding was in discarded items such as containers '
        'and tyres. The authors link this to poor container waste management. '
        'WHO advises disposing of solid waste properly and removing artificial '
        'habitats that can hold water.',
    sources: [
      _tisseraEid2020,
      NoteSource(
        label: 'WHO, Dengue fact sheet',
        url: 'https://www.who.int/news-room/fact-sheets/detail/dengue-and-severe-dengue',
      ),
    ],
  ),
];
