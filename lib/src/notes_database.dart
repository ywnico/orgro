import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_charset_detector/flutter_charset_detector.dart';
import 'package:org_flutter/org_flutter.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/preferences.dart';
import 'package:orgro/src/util.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data_source.dart';

class NotesDirectory {
  NotesDirectory.fromJson(Map<String, dynamic> json)
      : this(
    json['identifier'] as String,
    json['name'] as String,
  );
  NotesDirectory.fromNativeDirectoryInfo(NativeDirectoryInfo ndi)
      : this(
    ndi.identifier,
    ndi.name,
  );

  NotesDirectory(this.identifier, this.name);
  final String identifier;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is NotesDirectory &&
          identifier == other.identifier &&
          name == other.name;

  @override
  int get hashCode => Object.hash(identifier, name);

  Map<String, Object> toJson() => {
    'identifier': identifier,
    'name': name,
  };

  @override
  String toString() => 'NotesDirectory[$name:$_debugShortIdentifier]';

  String get _debugShortIdentifier {
    final length = identifier.length;
    if (length > 20) {
      final front = identifier.substring(0, 10);
      final back = identifier.substring(length - 10);
      return '$front...$back';
    } else {
      return identifier;
    }
  }
}

class NotesDatabase extends InheritedWidget {
  NotesDatabase(
      this.notesDirectory,
      // TODO add id link database
      {
        required this.setNotesDirectory,
        required this.setNotesDirectoryFromNativeDirectoryInfo,
        required this.removeNotesDirectory,
        required super.child,
        super.key,
      });

  final NotesDirectory? notesDirectory;
  final ValueChanged<NotesDirectory> setNotesDirectory;
  final ValueChanged<NativeDirectoryInfo> setNotesDirectoryFromNativeDirectoryInfo;
  final Function removeNotesDirectory; // TODO is this the right type?

  List<File> orgFileList = [];
  // Keys are id (from id links), values are files (we're assuming no duplicates sorry)
  Map<String, String> idLinkFileIdMap = {};
  bool scanInProgress = false;
  // TODO scan start time
  int scanProgressNumerator = 0;
  int scanProgressDenominator = 0;

  @override
  bool updateShouldNotify(NotesDatabase oldWidget) =>
      notesDirectory != oldWidget.notesDirectory ||
          setNotesDirectory != oldWidget.setNotesDirectory ||
          setNotesDirectoryFromNativeDirectoryInfo != oldWidget.setNotesDirectoryFromNativeDirectoryInfo ||
          removeNotesDirectory != oldWidget.removeNotesDirectory;

  static NotesDatabase of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotesDatabase>()!;


  ////////// Scan and parse id links in all files //////////
  // TODO

  Future<List<File>> getOrgFilesFromDirectory() async {
    List<File> output = [];

    if (notesDirectory?.identifier != null) {
      // NOTE android by default only allows listing media files. We have to specifically ask for permission for file access.
      if (await Permission.manageExternalStorage.request().isGranted) {
        try {
          String absNotesDir = _absolutePathFromContentURI(notesDirectory!.identifier);

          Directory dir = Directory(absNotesDir);
          List<FileSystemEntity> entities = await dir.list(recursive: true)
              .where((e) => (
              (e is File) & (e.path.toLowerCase().endsWith(".org"))
              )
             ).toList();

          //output.add(entities.length.toString());
          output.addAll(entities.map((e) => (e as File)));
        } on Exception catch (e, s) {
          logError(e, s);
        }
      }
    }

    return output;
  }

  // find id _links_ in a file
  // TODO use this to produce backlink list
  Future<List<String>> idOutLinksFromOrgDocument(OrgDocument od) async {
    List<String> idLinks = [];

    od.visit<OrgLink>((link) {
      String linkLoc = link.location.trim();
      if (linkLoc.toLowerCase().startsWith('id:')) {
        String linkId = linkLoc.substring('id:'.length).trim();
        if (!idLinks.contains(linkId)) {
          idLinks.add(linkId);
        }
      }
      return true;
    });

    return idLinks;
  }

  // find ids in a file (referring either to sections or to the whole file)
  Future<List<String>> idsFromOrgDocument(OrgDocument od) async {
    List<String> topLevelIds = [];
    List<String> sectionIds = [];

    // First, check if there is an id at the top level
    List<OrgNode> topLevelChildren = od.content?.children ?? [];
    for (OrgDrawer tlChild in topLevelChildren.whereType<OrgDrawer>()) {
        List<OrgNode> drawerChildren = tlChild.body.children;
        for (OrgProperty prop in drawerChildren.whereType<OrgProperty>()) {
          if (prop.key.trim().toUpperCase() == ':ID:') {
            topLevelIds.add(prop.value.trim());
          }
        }
    }
    od.visitSections((section) {
      //debugPrint('${section.headline.title}');
      //debugPrint('${section.ids}');
      sectionIds.addAll(section.ids);
      return true;
    });
    return topLevelIds + sectionIds;
  }

  Future<void> scanDatabase() async {
    // TODO should probably deal with failed scans or something....
    if (scanInProgress) return;

    scanInProgress = true;

    try {
      orgFileList = await getOrgFilesFromDirectory();

      scanProgressNumerator = 0;
      scanProgressDenominator = orgFileList.length;

      for (File thisFile in orgFileList) {
        debugPrint('Scanning file $thisFile');
        String content = await _readFile(thisFile);
        OrgDocument od = await parse(content);

        // TODO use outward links to determine backlinks
        //List<String> thisIdOutLinks = await idOutLinksFromOrgDocument(od);
        ////debugPrint('id links: $thisIdOutLinks');

        List<String> thisIds = await idsFromOrgDocument(od);
        debugPrint('ids: $thisIds');
        for (String id in thisIds) {
          // TODO deal with duplicates?
          idLinkFileIdMap[id] = thisFile.uri.toString();
        }

        scanProgressNumerator += 1;
      }
    } on Exception catch (e, s) {
      logError(e, s);
    }

    scanInProgress = false;
  }

}

mixin NotesDatabaseState<T extends StatefulWidget> on State<T> {
  Preferences get _prefs => Preferences.of(context);
  late NotesDirectory? _notesDirectory; // TODO initialize to null, just to be safe??
  // NotesDirectory? _notesDirectory = null;
  _LifecycleEventHandler? _lifecycleEventHandler;

  bool get hasNotesDirectory => (_notesDirectory != null);

  void setNotesDirectory(NotesDirectory newNotesDirectory) {
    if (newNotesDirectory == _notesDirectory) {
      debugPrint('Same notes directory selected: $newNotesDirectory');
    } else {
      debugPrint('Setting notes directory: $newNotesDirectory');
      _save(newNotesDirectory);
    }
  }
  void setNotesDirectoryFromNativeDirectoryInfo(NativeDirectoryInfo ndi) {
    setNotesDirectory(NotesDirectory.fromNativeDirectoryInfo(ndi));
  }

  Future<void> removeNotesDirectory() async {
    debugPrint('Removing notes directory');
    setState(() {
      _notesDirectory = null;
    });
    _prefs.removeNotesDirectory();

    if (_notesDirectory != null) {
      try {
        await disposeNativeSourceIdentifier(_notesDirectory!.identifier);
      } on Exception catch (e, s) {
        logError(e, s);
      }
    }
  }

  void _save(NotesDirectory dir) {
    setState(() {
      _notesDirectory = dir;
    });
    _prefs.setNotesDirectoryJson(
        json.encode(dir.toJson())
    );
  }

  @override
  void initState() {
    super.initState();
    _lifecycleEventHandler ??= _LifecycleEventHandler(onResume: _onResume);
    WidgetsBinding.instance.addObserver(_lifecycleEventHandler!);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleEventHandler!);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Doing this here instead of [initState] because we need to pull in an
    // InheritedWidget
    _load();
  }

  Future<void> _load() async {
    String? ndJson = _prefs.notesDirectoryJson;
    if (ndJson == null) {
      _notesDirectory = null;
    } else {

      try {
        _notesDirectory = NotesDirectory.fromJson(
            json.decode(ndJson)
        );
      } on Exception catch (e, s) {
        logError(e, s);
        // there was some error, so we'll reset notes directory to null
        _notesDirectory = null;
      }

    }
    debugPrint('Loaded notes dir: ${_notesDirectory?.name}');
  }

  void _onResume() {
    // TODO (maybe)
  }

  Widget buildWithNotesDatabase({required WidgetBuilder builder}) {
    return NotesDatabase(
      _notesDirectory,
      setNotesDirectory: setNotesDirectory,
      setNotesDirectoryFromNativeDirectoryInfo: setNotesDirectoryFromNativeDirectoryInfo,
      removeNotesDirectory: removeNotesDirectory,
      // Builder required to get NotesDatabase into context
      child: Builder(builder: builder),
    );
  }

}

class _LifecycleEventHandler extends WidgetsBindingObserver {
  _LifecycleEventHandler({this.onResume});

  final VoidCallback? onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('App resumed');
        onResume?.call();
        break;
      default:
      // Nothing
    }
  }
}

// Some sketchy code to try to get the absolute path of the notes directory
// This has been designed only for Android 13 and internal storage so....not reliable
// TODO replace with something better
String _absolutePathFromContentURI(String uriStr) {
  String? absPath = null;

  Uri uri = Uri.parse(uriStr);
  if (uriStr.startsWith('file:///')) {
    absPath = uriStr.substring('file://'.length);
  } else if (uriStr.startsWith('content://')) {
    String uriPath = uri.pathSegments.last;

    // we only know how to deal with 'primary:blah/blah/blah'
    List<String> uriPathPieces = uriPath.split(":");
    if ((uriPathPieces.length == 2) && (uriPathPieces[0] == 'primary')) {
      return '/storage/emulated/0/${uriPathPieces[1]}';
    }
  }

  if (absPath == null) {
    debugPrint('Could not convert notes directory URI to absolute path: $uriStr');
    throw const FormatException('Could not parse notes directory URI.');
  } else {
    return absPath;
  }
}

Future<String> _readFile(File file) async {
  try {
    return await file.readAsString();
  } on Exception {
    final bytes = await file.readAsBytes();
    final decoded = await CharsetDetector.autoDecode(bytes);
    debugPrint('Decoded file as ${decoded.charset}');
    return decoded.string;
  }
}
