/// Site a link or download comes from. Drives the brand badge, the
/// download suggestion and the `Download/<AppName>/<Platform>` folder.
enum SourcePlatform {
  youtube('YouTube'),
  youtubeMusic('YouTube Music'),
  instagram('Instagram'),
  x('X'),
  reddit('Reddit'),
  facebook('Facebook'),
  other(null);

  new(this.brandName);

  /// Proper noun shown in the UI; null for [other], which is localized.
  final String? brandName;

  /// Folder under the app's download directory. YouTube Music shares the
  /// YouTube folder, as yt-dlp treats both as one site.
  String get folderName => switch (this) {
    youtubeMusic => 'YouTube',
    other => 'Other',
    _ => brandName!,
  };

  /// Sites people mostly use for music, where audio is the better default.
  bool get prefersAudio => this == youtubeMusic;

  /// Sites with photo posts, which yt-dlp reports as items without formats
  /// (the photo is the item's thumbnail). Elsewhere such an item has nothing
  /// to save (e.g. DRM or a stream that hasn't started).
  bool get hasPhotoPosts => this == instagram;

  /// Matches a link's host, e.g. `youtu.be` or `old.reddit.com`.
  static SourcePlatform fromHost(String host) {
    final h = host.toLowerCase();
    bool on(String domain) => h == domain || h.endsWith('.$domain');

    if (h == 'music.youtube.com') return youtubeMusic;
    if (on('youtube.com') || on('youtu.be') || on('youtube-nocookie.com')) {
      return youtube;
    }
    if (on('instagram.com') || on('instagr.am')) return instagram;
    if (on('x.com') || on('twitter.com')) return x;
    if (on('reddit.com') || on('redd.it')) return reddit;
    if (on('facebook.com') || on('fb.watch') || on('fb.com')) return facebook;
    return other;
  }

  /// Maps yt-dlp's raw extractor name (`youtube`, `youtube:tab`, `twitter`,
  /// `Instagram`, …) to a platform.
  static SourcePlatform fromExtractor(String extractor) {
    final key = extractor.toLowerCase().split(':').first;
    return switch (key) {
      'youtube' => youtube,
      'instagram' => instagram,
      'twitter' => x,
      'reddit' => reddit,
      'facebook' => facebook,
      _ => other,
    };
  }
}
