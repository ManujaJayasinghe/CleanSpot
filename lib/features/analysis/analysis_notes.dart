/// Hand-written insight notes for the Analysis screen.
///
/// These are meant to be written with Anushka's research notes. Each one
/// needs a real [source] link; until then it is shown as "Source pending" so
/// nobody mistakes a draft for a verified fact.
class WrittenInsight {
  const WrittenInsight({required this.title, required this.text, this.source});

  final String title;
  final String text;

  /// Link or citation from Anushka's notes. Null while still pending.
  final String? source;
}

const List<WrittenInsight> writtenInsights = [
  WrittenInsight(
    title: 'Rain and mosquito breeding',
    text: 'Cases tend to rise after the monsoon months, when rain leaves '
        'standing water in containers, tyres and blocked drains.',
  ),
  WrittenInsight(
    title: 'Garbage collection gaps',
    text: 'Weeks when garbage collection is missed can leave more '
        'water-holding rubbish outdoors, which gives mosquitoes more places '
        'to breed.',
  ),
];
