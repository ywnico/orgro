import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:orgro/src/file_picker.dart';
import 'package:orgro/src/data_source.dart';
import 'package:orgro/src/debug.dart';
import 'package:orgro/src/preferences.dart';
import 'package:orgro/src/notes_database.dart';

// TODO not currently using state for NotesDatabaseMenu, so make stateless

class NotesDatabaseMenu extends StatefulWidget {
  const NotesDatabaseMenu({super.key});

  @override
  State createState() => _NotesDatabaseMenuState();
}

class _NotesDatabaseMenuState extends State<NotesDatabaseMenu>
{
  @override
  Widget build(BuildContext context) {
        return notesDatabaseMenuItem(context);
  }
}

PopupMenuButton notesDatabaseMenuItem(BuildContext context) {
  final prefs = Preferences.of(context);
  final scaffoldMessenger = ScaffoldMessenger.of(context);

  final notesDatabase = NotesDatabase.of(context);
  final String curNotesDirName = notesDatabase.notesDirectory?.name ?? 'No current notes dir.';

  // TODO change message as necessary
  final snackBarRescanNotesBegun = SnackBar(
    content: Text('Notes rescan initiated…'), // TODO localize
    duration: const Duration(seconds: 1), // TODO standardize duration
  );

  // Get current rescan progress
  // TODO: make live...?
  // TODO: localize
  String rescanString = 'Rescan notes';
  if (notesDatabase.scanInProgress) {
    rescanString = 'Scan progress: ${notesDatabase.scanProgressNumerator}/${notesDatabase.scanProgressDenominator}';
  }

  // Currently this contains directory setting and force rescan submenu items.
  // TODO: reorganize into a popup window in which:
  //       1) current directory (if applicable) is displayed, along with a change option
  //       2) rescan interval can be set
  //       3) manual rescan can be run
  //       4) progress of current rescan is shown?
  return PopupMenuButton(
      child: Text('Notes database…'), // TODO localize
      onSelected: (callback) => callback(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[

        // set notes directory
        PopupMenuItem<VoidCallback>(
          value: () async {
            NativeDirectoryInfo? chosenDir = await pickDirectory();
            if (chosenDir == null) {
              // cancelled
              debugPrint('chosenDir null');
              // TODO notify user that no change was made
            } else {
              debugPrint('chosenDir: ${chosenDir?.name}');
              // TODO notify user that change was made

              // update notes directory preference
              // TODO make async? no await since void....
              notesDatabase.setNotesDirectoryFromNativeDirectoryInfo(chosenDir);
              //await prefs.setRemoteImagesPolicy(kDefaultRemoteImagesPolicy);
            }
          },
          child: Text(AppLocalizations.of(context)!.menuItemSetNotesDirectory),
        ),

        // rescan notes directory
        PopupMenuItem<VoidCallback>(
          value: () async {
            scaffoldMessenger.showSnackBar(snackBarRescanNotesBegun);

            // TODO This is basically all debug testing stuff
            await notesDatabase.scanDatabase();

            //List<File> testList = await notesDatabase.getOrgFilesFromDirectory();
            //String testString = testList.map((f) => f.toString()).join("\n");

            final snackBarTest = SnackBar( // debug
              content: Text('Scan complete.'), // TODO localize
              duration: const Duration(seconds: 1), // TODO standardize duration
            );
            scaffoldMessenger.showSnackBar(snackBarTest);
          },
          child: Text(rescanString),
        ),
      ],
  );
}