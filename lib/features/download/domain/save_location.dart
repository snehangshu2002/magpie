import 'package:media_downloader/core/media/source_platform.dart';

/// Where downloads go until the user picks another folder in Settings.
const defaultSaveFolder = 'Download/Magpie';

/// `<folder>/<Platform>`, e.g. `Download/Magpie/YouTube`.
String saveDirFor(String folder, SourcePlatform platform) =>
    '$folder/${platform.folderName}';

/// Whether [folder] is one downloads can be saved to: the Download folder
/// of the phone's own storage or a folder inside it. Saving goes through
/// the Downloads collection, which accepts nothing else.
bool isSaveFolder(String folder) =>
    folder == 'Download' || folder.startsWith('Download/');

/// The folder Android's folder picker returned, as a save folder; null when
/// it is outside Download or on another volume (an SD card).
///
/// [treeDocumentId] is the picker's document id: `primary:Download/Videos`.
String? saveFolderFromTreeId(String treeDocumentId) {
  const prefix = 'primary:';
  if (!treeDocumentId.startsWith(prefix)) return null;
  final folder = treeDocumentId
      .substring(prefix.length)
      .replaceAll(RegExp(r'/+$'), '');
  return isSaveFolder(folder) ? folder : null;
}
