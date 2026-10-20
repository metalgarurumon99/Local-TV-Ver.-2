import '../models/media_item.dart';

class SampleMediaData {
  static const List<MediaItem> allItems = [
    // === SERIES ===
    // Documentaries
    MediaItem(
      id: 'doc-1',
      title: 'Tiger King',
      description: 'An exploration of big cat breeding and its bizarre underworld, populated by eccentric characters.',
      genre: 'documentaries',
      maturity: '18',
      slug: 'tiger-king',
      category: 'series',
    ),
    MediaItem(
      id: 'doc-2',
      title: 'Amanda Knox',
      description: 'Amanda Marie Knox is an American woman who spent almost four years in an Italian prison.',
      genre: 'documentaries',
      maturity: '12',
      slug: 'amanda-knox',
      category: 'series',
    ),
    MediaItem(
      id: 'doc-3',
      title: 'Citizenfour',
      description: 'A 2014 documentary concerning Edward Snowden and the NSA spying scandal.',
      genre: 'documentaries',
      maturity: '12',
      slug: 'citizenfour',
      category: 'series',
    ),
    MediaItem(
      id: 'doc-4',
      title: 'Super Size Me',
      description: "Director Morgan Spurlock's experiment in fast-food gastronomy sees him subsisting uniquely on McDonald's.",
      genre: 'documentaries',
      maturity: '12',
      slug: 'super-size-me',
      category: 'series',
    ),
    MediaItem(
      id: 'doc-5',
      title: 'Man on Wire',
      description: "Filmmaker James Marsh masterfully recreates Philippe Petit's 1974 stunt walking on a wire across the Twin Towers.",
      genre: 'documentaries',
      maturity: '12',
      slug: 'man-on-wire',
      category: 'series',
    ),

    // Comedies
    MediaItem(
      id: 'com-1',
      title: 'The Office',
      description: 'A motley group of office workers go through hilarious misadventures at the Scranton, Pennsylvania branch of Dunder Mifflin.',
      genre: 'comedies',
      maturity: '15',
      slug: 'the-office',
      category: 'series',
    ),
    MediaItem(
      id: 'com-2',
      title: 'Arrested Development',
      description: 'Level-headed son Michael Bluth takes over family affairs after his father is imprisoned.',
      genre: 'comedies',
      maturity: '15',
      slug: 'arrested-development',
      category: 'series',
    ),
    MediaItem(
      id: 'com-3',
      title: 'Curb Your Enthusiasm',
      description: 'Larry David plays a fictionalized version of himself navigating life in Los Angeles.',
      genre: 'comedies',
      maturity: '15',
      slug: 'curb-your-enthusiasm',
      category: 'series',
    ),
    MediaItem(
      id: 'com-4',
      title: 'Family Guy',
      description: 'Peter Griffin and his dysfunctional family strive to cope with everyday life as they are thrown from one crazy scenario to another.',
      genre: 'comedies',
      maturity: '15',
      slug: 'family-guy',
      category: 'series',
    ),
    MediaItem(
      id: 'com-5',
      title: 'South Park',
      description: 'Four young boys living in Colorado navigate bizarre, satirical happenings in their town.',
      genre: 'comedies',
      maturity: '15',
      slug: 'south-park',
      category: 'series',
    ),

    // Children
    MediaItem(
      id: 'chi-1',
      title: 'Dora The Explorer',
      description: 'Dora the Explorer goes on interactive quests alongside her monkey companion Boots.',
      genre: 'children',
      maturity: '0',
      slug: 'dora-the-explorer',
      category: 'series',
    ),
    MediaItem(
      id: 'chi-2',
      title: 'PAW Patrol',
      description: 'Six brave puppies led by tech-savvy 10-year-old Ryder work together to protect the community of Adventure Bay.',
      genre: 'children',
      maturity: '0',
      slug: 'paw-patrol',
      category: 'series',
    ),
    MediaItem(
      id: 'chi-3',
      title: 'Arthur',
      description: 'Bespectacled aardvark Arthur Read demonstrates to kids how to deal with childhood challenges.',
      genre: 'children',
      maturity: '0',
      slug: 'arthur',
      category: 'series',
    ),
    MediaItem(
      id: 'chi-4',
      title: 'SpongeBob',
      description: 'A yellow sea sponge named SpongeBob SquarePants lives deep down in the Pacific Ocean in Bikini Bottom.',
      genre: 'children',
      maturity: '0',
      slug: 'spongebob',
      category: 'series',
    ),

    // Crime
    MediaItem(
      id: 'crm-1',
      title: 'Making a Murderer',
      description: 'Filmed over 10 years, this real-life thriller follows the story of Steven Avery.',
      genre: 'crime',
      maturity: '18',
      slug: 'making-a-murderer',
      category: 'series',
    ),
    MediaItem(
      id: 'crm-2',
      title: 'Long Shot',
      description: 'An innocent man is accused of murder, and leading edge baseball footage helps establish his alibi.',
      genre: 'crime',
      maturity: '18',
      slug: 'long-shot',
      category: 'series',
    ),
    MediaItem(
      id: 'crm-3',
      title: 'The Confession Killer',
      description: 'Henry Lee Lucas rose to infamy after confessing to hundreds of unsolved murders.',
      genre: 'crime',
      maturity: '18',
      slug: 'the-confession-killer',
      category: 'series',
    ),

    // Feel-Good
    MediaItem(
      id: 'fg-1',
      title: 'Forrest Gump',
      description: 'The presidencies of Kennedy and Johnson, the Vietnam War, and other historical events unfold through the perspective of an Alabama man.',
      genre: 'feel-good',
      maturity: '12',
      slug: 'forrest-gump',
      category: 'series',
    ),
    MediaItem(
      id: 'fg-2',
      title: 'Good Will Hunting',
      description: 'Will Hunting, a janitor at M.I.T., has a gift for mathematics, but needs help from a psychologist to find direction in his life.',
      genre: 'feel-good',
      maturity: '12',
      slug: 'good-will-hunting',
      category: 'series',
    ),

    // === FILMS ===
    // Drama
    MediaItem(
      id: 'drm-1',
      title: 'The Prestige',
      description: 'Two stage magicians engage in competitive one-upmanship in an attempt to create the ultimate teleportation illusion.',
      genre: 'drama',
      maturity: '15',
      slug: 'the-prestige',
      category: 'films',
    ),
    MediaItem(
      id: 'drm-2',
      title: 'Fight Club',
      description: 'An insomniac office worker looking for a way to change his life crosses paths with a devil-may-care soap maker.',
      genre: 'drama',
      maturity: '18',
      slug: 'fight-club',
      category: 'films',
    ),
    MediaItem(
      id: 'drm-3',
      title: 'The Social Network',
      description: 'Harvard student Mark Zuckerberg pursues an idea that catapults into a global social network phenomenon.',
      genre: 'drama',
      maturity: '12',
      slug: 'the-social-network',
      category: 'films',
    ),

    // Thriller
    MediaItem(
      id: 'thr-1',
      title: 'Joker',
      description: 'Forever alone in a crowd, failed comedian Arthur Fleck seeks connection as he walks the streets of Gotham City.',
      genre: 'thriller',
      maturity: '18',
      slug: 'joker',
      category: 'films',
    ),
    MediaItem(
      id: 'thr-2',
      title: 'Black Swan',
      description: 'A committed dancer wins the lead role in a production of Tchaikovskys Swan Lake only to struggle maintaining her sanity.',
      genre: 'thriller',
      maturity: '15',
      slug: 'black-swan',
      category: 'films',
    ),
    MediaItem(
      id: 'thr-3',
      title: 'Nightcrawler',
      description: 'When Lou Bloom, a driven man desperate for work, muscles into the world of L.A. crime journalism, he blurs the line between observer and participant.',
      genre: 'thriller',
      maturity: '15',
      slug: 'nightcrawler',
      category: 'films',
    ),

    // Suspense
    MediaItem(
      id: 'sus-1',
      title: 'Seven',
      description: 'Two detectives, a rookie and a veteran, hunt a serial killer who uses the seven deadly sins as his motives.',
      genre: 'suspense',
      maturity: '18',
      slug: 'seven',
      category: 'films',
    ),
    MediaItem(
      id: 'sus-2',
      title: 'Shutter Island',
      description: 'In 1954, a U.S. Marshal investigates the disappearance of a murderer who escaped from a hospital for the criminally insane.',
      genre: 'suspense',
      maturity: '15',
      slug: 'shutter-island',
      category: 'films',
    ),
    MediaItem(
      id: 'sus-3',
      title: 'Gone Girl',
      description: 'With his wife disappearance having become the focus of an intense media circus, a man sees the spotlight turned on him.',
      genre: 'suspense',
      maturity: '18',
      slug: 'gone-girl',
      category: 'films',
    ),

    // Romance
    MediaItem(
      id: 'rom-1',
      title: 'La La Land',
      description: 'While navigating their careers in Los Angeles, a pianist and an actress fall in love while attempting to reconcile their aspirations.',
      genre: 'romance',
      maturity: '12',
      slug: 'la-la-land',
      category: 'films',
    ),
    MediaItem(
      id: 'rom-2',
      title: 'Titanic',
      description: 'A seventeen-year-old aristocrat falls in love with a kind but poor artist aboard the luxurious, ill-fated R.M.S. Titanic.',
      genre: 'romance',
      maturity: '12',
      slug: 'titanic',
      category: 'films',
    ),
  ];

  static Map<String, List<MediaItem>> getGrouped(String category) {
    final filtered = allItems.where((item) => item.category == category).toList();
    final Map<String, List<MediaItem>> groups = {};
    for (final item in filtered) {
      final capGenre = item.genre.substring(0, 1).toUpperCase() + item.genre.substring(1);
      groups.putIfAbsent(capGenre, () => []).add(item);
    }
    return groups;
  }
}
