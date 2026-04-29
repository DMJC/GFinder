
PACKAGE_NEEDS_CONFIGURE = YES

PACKAGE_NAME = gfinder
include $(GNUSTEP_MAKEFILES)/common.make

VERSION = 1.1.0

#
# subprojects
#
SUBPROJECTS = Finder/Modules \
	Thumbnailer

#
# MAIN APP
#
APP_NAME = GFinder
GFinder_PRINCIPAL_CLASS = GFinder
GFinder_APPLICATION_ICON=FileManager.tiff

GFinder_HAS_RESOURCE_BUNDLE = yes

#
# Additional libraries
#
ADDITIONAL_GUI_LIBS += -lFSNode
ADDITIONAL_GUI_LIBS += -lInspector
ADDITIONAL_GUI_LIBS += -lOperation

GFinder_RESOURCE_FILES = \
  Resources/Icons/* \
  Resources/English.lproj \
  Resources/BrasilPortuguese.lproj \
  Resources/Dutch.lproj \
  Resources/Esperanto.lproj \
  Resources/French.lproj \
  Resources/German.lproj \
  Resources/Hungarian.lproj \
  Resources/Italian.lproj \
  Resources/Norvegian.lproj \
  Resources/Portuguese.lproj \
  Resources/Romanian.lproj \
  Resources/Spanish.lproj \
  Resources/Japanese.lproj \
  Resources/Polish.lproj \
  GFinderInfo.plist

GFinder_LANGUAGES = \
  Resources/English \
  Resources/BrasilPortuguese \
  Resources/Dutch \
  Resources/Esperanto \
  Resources/French \
  Resources/German \
  Resources/Hungarian \
  Resources/Italian \
  Resources/Norvegian \
  Resources/Portuguese \
  Resources/Romanian \
  Resources/Spanish \
  Resources/Japanese \
  Resources/Polish

# The Objective-C source files to be compiled
GFinder_OBJC_FILES = main.m \
GWFunctions.m \
GFinder.m \
WorkspaceApplication.m \
FileViewer/GWViewersManager.m \
FileViewer/GWViewer.m \
FileViewer/GWViewerWindow.m \
FileViewer/GWViewerBrowser.m \
FileViewer/GWViewerIconsView.m \
FileViewer/GWViewerListView.m \
FileViewer/GWSidebarView.m \
FileViewer/GWViewerSplit.m \
FileViewer/GWViewerScrollView.m \
FileViewer/GWViewerIconsPath.m \
FileViewer/GWViewerPathsPopUp.m \
Finder/Finder.m \
Finder/FindModuleView.m \
Finder/SearchPlacesBox.m \
Finder/SearchPlacesCell.m \
Finder/SearchResults/SearchResults.m \
Finder/SearchResults/ResultsTableView.m \
Finder/LiveSearch/LSFolder.m \
Finder/LiveSearch/LSFEditor.m \
Preferences/PrefController.m \
Preferences/DefEditorPref.m \
Preferences/XTermPref.m \
Preferences/DefSortOrderPref.m \
Preferences/IconsPref.m \
Preferences/HiddenFilesPref.m \
Preferences/HistoryPref.m \
Preferences/BrowserViewerPref.m \
Preferences/OperationPrefs.m \
History/History.m \
Dialogs/Dialogs.m \
Dialogs/ExecuteController.m \
Dialogs/OpenWithController.m \
Dialogs/RunExternalController.m \
Dialogs/CompletionField.m \
Dialogs/StartAppWin.m \
Fiend/Fiend.m \
Fiend/FiendLeaf.m \
Thumbnailer/GWThumbnailer.m \


-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

include $(GNUSTEP_MAKEFILES)/application.make

-include GNUmakefile.postamble
