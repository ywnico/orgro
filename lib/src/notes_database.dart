import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/preferences.dart';
import 'package:orgro/src/util.dart';

class NotesDirectory {
  NotesDirectory.fromJson(Map<String, dynamic> json)
      : this(
    json['identifier'] as String,
    json['name'] as String,
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
  const NotesDatabase(
      this.notesDirectory,
      // TODO add id link database
      {
        required this.setNotesDirectory,
        required this.removeNotesDirectory,
        required super.child,
        super.key,
      });

  final NotesDirectory? notesDirectory;
  final ValueChanged<NotesDirectory> setNotesDirectory;
  final Function removeNotesDirectory; // TODO is this the right type?

  @override
  bool updateShouldNotify(NotesDatabase oldWidget) =>
      notesDirectory != oldWidget.notesDirectory ||
          setNotesDirectory != oldWidget.setNotesDirectory ||
          removeNotesDirectory != oldWidget.removeNotesDirectory;

  static NotesDatabase of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotesDatabase>()!;
}

mixin NotesDatabaseState<T extends StatefulWidget> on State<T> {
  Preferences get _prefs => Preferences.of(context);
  late NotesDirectory? _notesDirectory;
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

  void removeNotesDirectory() {
    debugPrint('Removing notes directory');
    setState(() {
      _notesDirectory = null;
    });
    _prefs.removeNotesDirectory();
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

  void _load() {
    String? ndJson = _prefs.notesDirectoryJson;
    if (ndJson == null) {
      _notesDirectory = null;
    } else {
      NotesDirectory.fromJson(
          json.decode(ndJson)
      );
    }
  }

  void _onResume() {
    // TODO (maybe)
  }

  Widget buildWithNotesDatabase({required WidgetBuilder builder}) {
    return NotesDatabase(
      _notesDirectory,
      setNotesDirectory: setNotesDirectory,
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