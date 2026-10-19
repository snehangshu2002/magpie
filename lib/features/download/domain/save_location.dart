import 'package:media_downloader/core/media/source_platform.dart';

/// Where downloads land under shared storage, until Settings lets the user
/// pick a location.
const saveRoot = 'Download/Magpie';

/// `Download/<AppName>/<Platform>`, e.g. `Download/Magpie/YouTube`.
String saveDirFor(SourcePlatform platform) =>
    '$saveRoot/${platform.folderName}';
