/* GFinder.m
 *  
 * Copyright (C) 2003-2016 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola
 * Date: August 2001
 *
 * This file is part of the GNUstep GFinder application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#include "config.h"

/* the following for getrlimit */
#include <sys/types.h>
#include <sys/time.h>
#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
/* getrlimit */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWFunctions.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "GFinder.h"
#import "Dialogs.h"
#import "OpenWithController.h"
#import "RunExternalController.h"
#import "StartAppWin.h"
#import "Preferences/PrefController.h"
#import "Fiend/Fiend.h"
#import "GWViewersManager.h"
#import "GWViewer.h"
#import "Finder.h"
#import "Inspector.h"
#import "Operation.h"
#import "History/History.h"


static NSString *defaulteditor = @"nedit.app";
static NSString *defaultxterm = @"xterm";

static GFinder *gfinder = nil;

@interface	GFinder (PrivateMethods)
- (void)_updateTrashContents;
@end

@implementation GFinder

#ifndef byname
  #define byname 0
  #define bykind 1
  #define bydate 2
  #define bysize 3
  #define byowner 4
#endif

#define HISTORT_CACHE_MAX 20

#ifndef TSHF_MAXF
  #define TSHF_MAXF 999
#endif


+ (void)initialize
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject: @"GFinder" 
               forKey: @"DesktopApplicationName"];
  [defaults setObject: @"gfinder" 
               forKey: @"DesktopApplicationSelName"];
  [defaults synchronize];
}

+ (GFinder *)gfinder
{
  if (gfinder == nil) {
    gfinder = [[GFinder alloc] init];
  }	
  return gfinder;
}

+ (void)registerForServices
{
  NSArray *sendTypes = [NSArray arrayWithObjects: NSFilenamesPboardType, nil];	
  NSArray *returnTypes = [NSArray arrayWithObjects: NSFilenamesPboardType, nil];	
  [NSApp registerServicesMenuSendTypes: sendTypes returnTypes: returnTypes];
}

- (void)dealloc
{
  if (fswatcher && [[(NSDistantObject *)fswatcher connectionForProxy] isValid]) {
    [fswatcher unregisterClient: (id <FSWClientProtocol>)self];
    DESTROY (fswatcher);
  }
  [[NSDistributedNotificationCenter defaultCenter] removeObserver: self];
  [wsnc removeObserver: self];
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  DESTROY (recyclerApp);
  DESTROY (ddbd);
  DESTROY (mdextractor);
  RELEASE (gwProcessName);
  RELEASE (gwBundlePath);
  RELEASE (defEditor);
  RELEASE (defXterm);
  RELEASE (defXtermArgs);
  RELEASE (selectedPaths);
  RELEASE (trashContents);
  RELEASE (trashPath);
  RELEASE (watchedPaths);
  RELEASE (fiend);
  RELEASE (history);
  RELEASE (openWithController);
  RELEASE (runExtController);
  RELEASE (startAppWin);
  RELEASE (vwrsManager);
  DESTROY (inspector);
  DESTROY (fileOpsManager);
  RELEASE (finder);
  RELEASE (launchedApps);
  RELEASE (storedAppinfoPath);
  RELEASE (storedAppinfoLock);
    
}

- (void)createMenu
{
  NSMenu *mainMenu = [NSMenu new];
  NSMenu *menu;
  NSMenu *subMenu;
  NSMenu *windows, *services;  
  id<NSMenuItem> menuItem;
    	
  // Info
  menuItem = [mainMenu addItemWithTitle:_(@"Info") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];	
  [menu addItemWithTitle: _(@"Info Panel...") action:@selector(showInfo:) keyEquivalent:@""];
  [menu addItemWithTitle: _(@"Preferences...") action:@selector(showPreferences:) keyEquivalent:@""];
  [menu addItemWithTitle: _(@"Help...") action:@selector(showHelp:) keyEquivalent:@"?"];
  [menu addItemWithTitle: _(@"Activate context help") action:@selector(activateContextHelp:) keyEquivalent:@";"];
	 
  // File
  menuItem = [mainMenu addItemWithTitle:_(@"File") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];		
  [menu addItemWithTitle:_(@"Open") action:@selector(openSelection:) keyEquivalent:@"o"];
  [menu addItemWithTitle:_(@"Open With...")  action:@selector(openWith:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Open as Folder") action:@selector(openSelectionAsFolder:) keyEquivalent:@"O"];
  [menu addItemWithTitle:_(@"New Folder") action:@selector(newFolder:) keyEquivalent:@"n"];
  [menu addItemWithTitle:_(@"New File")  action:@selector(newFile:) keyEquivalent:@"N"];
  [menu addItemWithTitle:_(@"Duplicate")  action:@selector(duplicateFiles:) keyEquivalent:@"u"];
  [menu addItemWithTitle:_(@"Destroy")  action:@selector(deleteFiles:) keyEquivalent:@"r"];  
  [menu addItemWithTitle:_(@"Move to Recycler")  action:@selector(recycleFiles:) keyEquivalent:@"del"];
  [menu addItemWithTitle:_(@"Empty Recycler") action:@selector(emptyRecycler:) keyEquivalent:@""];
  
  // Edit
  menuItem = [mainMenu addItemWithTitle:_(@"Edit") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];	
  [menu addItemWithTitle:_(@"Cut") action:@selector(cut:) keyEquivalent:@"x"];
  [menu addItemWithTitle:_(@"Copy") action:@selector(copy:) keyEquivalent:@"c"];
  [menu addItemWithTitle:_(@"Paste") action:@selector(paste:) keyEquivalent:@"v"];
  [menu addItemWithTitle:_(@"Select All") action:@selector(selectAllInViewer:) keyEquivalent:@"a"];

  // View
  menuItem = [mainMenu addItemWithTitle:_(@"View") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Browser") action:@selector(setViewerType:) keyEquivalent:@"b"];
  [menuItem setTag:GWViewTypeBrowser];
  [menu addItem:menuItem];
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Icon") action:@selector(setViewerType:) keyEquivalent:@"i"];
  [menuItem setTag:GWViewTypeIcon];
  [menu addItem:menuItem];
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"List") action:@selector(setViewerType:) keyEquivalent:@"l"];
  [menuItem setTag:GWViewTypeList];
  [menu addItem:menuItem];
	
  menuItem = [menu addItemWithTitle:_(@"Show") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  [subMenu addItemWithTitle:_(@"Name only") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Type") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Size") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Modification date") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Owner") action:@selector(setShownType:) keyEquivalent:@""];
      
  menuItem = [menu addItemWithTitle:_(@"Icon Size") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"24") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"28") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"32") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"36") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"40") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"48") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"64") action:@selector(setIconsSize:) keyEquivalent:@""];
      
  menuItem = [menu  addItemWithTitle:_(@"Icon Position") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"Up") action:@selector(setIconsPosition:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Left") action:@selector(setIconsPosition:) keyEquivalent:@""];

  menuItem = [menu addItemWithTitle:_(@"Thumbnails") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"Make thumbnail(s)") action:@selector(makeThumbnails:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Remove thumbnail(s)") action:@selector(removeThumbnails:) keyEquivalent:@""];

  menuItem = [menu addItemWithTitle:_(@"Label Size") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  [subMenu addItemWithTitle:_(@"10") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"11") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"12") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"13") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"14") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"15") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"16") action:@selector(setLabelSize:) keyEquivalent:@""];

  [menu addItemWithTitle:_(@"Viewer") action:@selector(showViewer:) keyEquivalent:@"V"];	
            
  //Go
  menuItem = [mainMenu addItemWithTitle:_(@"Go") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  [menu addItemWithTitle:_(@"Back") action:@selector(goBackwardInHistory:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Forward") action:@selector(goForwardInHistory:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Enclosing Folder") action:@selector(goEnclosingFolder:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"All My Files") action:@selector(goAllMyFiles:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Desktop") action:@selector(goDesktop:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Documents") action:@selector(goDocuments:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Downloads") action:@selector(goDownloads:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Home") action:@selector(goHome:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Computer") action:@selector(goComputer:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Network") action:@selector(goNetwork:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Applications") action:@selector(goApplications:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Utilities") action:@selector(goUtilities:) keyEquivalent:@""];

  // Tools
  menuItem = [mainMenu addItemWithTitle:_(@"Tools") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];	
		
  menuItem = [menu addItemWithTitle:_(@"Inspectors") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"Show Inspectors") action:NULL keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Attributes") action:@selector(showAttributesInspector:) keyEquivalent:@"1"];
  [subMenu addItemWithTitle:_(@"Contents") action:@selector(showContentsInspector:) keyEquivalent:@"2"];
  [subMenu addItemWithTitle:_(@"Tools") action:@selector(showToolsInspector:) keyEquivalent:@"3"];
  [subMenu addItemWithTitle:_(@"Annotations") action:@selector(showAnnotationsInspector:) keyEquivalent:@"4"];

  [menu addItemWithTitle:_(@"Finder") action:@selector(showFinder:) keyEquivalent:@"f"];

  menuItem = [menu addItemWithTitle:_(@"Fiend") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];

  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];    
  [menu addItemWithTitle:_(@"Terminal") action:@selector(showTerminal:) keyEquivalent:@"t"];
  [menu addItemWithTitle:_(@"Run...") action:@selector(runCommand:) keyEquivalent:@"R"];  

  menuItem = [menu addItemWithTitle:_(@"History") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  [subMenu addItemWithTitle:_(@"Show History") action:@selector(showHistory:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Go backward") action:@selector(goBackwardInHistory:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Go forward") action:@selector(goForwardInHistory:) keyEquivalent:@""];
  
  [menu addItemWithTitle:_(@"Show Recycler") action:@selector(showRecycler:) keyEquivalent:@""];

  [menu addItemWithTitle:_(@"Check for disks") action:@selector(checkRemovableMedia:) keyEquivalent:@"E"];
	
  // Windows
  menuItem = [mainMenu addItemWithTitle:_(@"Windows") action:NULL keyEquivalent:@""];
  windows = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: windows forItem: menuItem];		
  [windows addItemWithTitle:_(@"Arrange in Front") action:@selector(arrangeInFront:) keyEquivalent:@""];
  [windows addItemWithTitle:_(@"Miniaturize Window") action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  [windows addItemWithTitle:_(@"Close Window") action:@selector(performClose:) keyEquivalent:@"w"];

  // Services 
  menuItem = [mainMenu addItemWithTitle:_(@"Services") action:NULL keyEquivalent:@""];
  services = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: services forItem: menuItem];		

  // Hide
  [mainMenu addItemWithTitle:_(@"Hide") action:@selector(hide:) keyEquivalent:@"h"];
  [mainMenu addItemWithTitle:_(@"Hide Others") action:@selector(hideOtherApplications:)  keyEquivalent:@"H"];
  [mainMenu addItemWithTitle:_(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];

  // Print
  [mainMenu addItemWithTitle:_(@"Print...") action:@selector(print:) keyEquivalent:@"p"];
	
  // Quit
#if !AMBROSIA_BUILD
  [mainMenu addItemWithTitle:_(@"Quit") action:@selector(terminate:) keyEquivalent:@"Q"];
#endif

  [mainMenu update];

  [NSApp setServicesMenu: services];
  [NSApp setWindowsMenu: windows];
  [NSApp setMainMenu: mainMenu];		
  
  RELEASE (mainMenu);
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
  NSUserDefaults *defaults;
  id entry;
  BOOL boolentry;
  NSArray *extendedInfo;
  NSMenu *menu;
  NSString *lockpath;
  NSUInteger i;
  
  [self createMenu];
    
  [[self class] registerForServices];
  
  ASSIGN (gwProcessName, [[NSProcessInfo processInfo] processName]);
  ASSIGN (gwBundlePath, [[NSBundle mainBundle] bundlePath]);
  
  fm = [NSFileManager defaultManager];
  ws = [NSWorkspace sharedWorkspace];
  fsnodeRep = [FSNodeRep sharedInstance];  
    
  extendedInfo = [fsnodeRep availableExtendedInfoNames];
  menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"View", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Show", @"")] submenu];

  for (i = 0; i < [extendedInfo count]; i++)
    {
      [menu addItemWithTitle: [extendedInfo objectAtIndex: i] 
                      action: @selector(setExtendedShownType:) 
               keyEquivalent: @""];
    }
	    
  defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject: gwProcessName forKey: @"GSWorkspaceApplication"];
        
  entry = [defaults objectForKey: @"reserved_names"];
  if (entry) 
    {
      [fsnodeRep setReservedNames: entry];
    } 
  else 
    {
      [fsnodeRep setReservedNames: [NSArray arrayWithObjects: @".gwdir", @".gwsort", nil]];
    }
        
  entry = [defaults stringForKey: @"defaulteditor"];
  if (entry == nil)
    {
      defEditor = [[NSString alloc] initWithString: defaulteditor];
    } 
  else 
    {
      ASSIGN (defEditor, entry);
    }

	entry = [defaults stringForKey: @"defxterm"];
	if (entry == nil) {
		defXterm = [[NSString alloc] initWithString: defaultxterm];
	} else {
		ASSIGN (defXterm, entry);
  }

	entry = [defaults stringForKey: @"defaultxtermargs"];
	if (entry == nil) {
		defXtermArgs = nil;
	} else {
		ASSIGN (defXtermArgs, entry);
  }
  
  teminalService = [defaults boolForKey: @"terminal_services"];
  [self setUseTerminalService: teminalService];
  		
	entry = [defaults objectForKey: @"default_sortorder"];	
	if (entry == nil) { 
		[defaults setObject: @"0" forKey: @"default_sortorder"];
    [fsnodeRep setDefaultSortOrder: byname];
	} else {
    [fsnodeRep setDefaultSortOrder: [entry intValue]];
	}

  boolentry = [defaults boolForKey: @"GSFileBrowserHideDotFiles"];
  [fsnodeRep setHideSysFiles: boolentry];

	entry = [defaults objectForKey: @"hiddendirs"];
	if (entry) {
    [fsnodeRep setHiddenPaths: entry];
	} 

	entry = [defaults objectForKey: @"history_cache"];
	if (entry) {
    maxHistoryCache = [entry intValue];
	} else {
    maxHistoryCache = HISTORT_CACHE_MAX;
  }
  
  dontWarnOnQuit = [defaults boolForKey: @"NoWarnOnQuit"];

  boolentry = [defaults boolForKey: @"use_thumbnails"];
  [fsnodeRep setUseThumbnails: boolentry];
  
  selectedPaths = [[NSArray alloc] initWithObjects: NSHomeDirectory(), nil];
  trashContents = [NSMutableArray new];
  ASSIGN (trashPath, [self trashPath]);
  [self _updateTrashContents];
  
  startAppWin = [[StartAppWin alloc] init];
  
  watchedPaths = [[NSCountedSet alloc] initWithCapacity: 1];
  fswatcher = nil;
  fswnotifications = YES;
  [self connectFSWatcher];
    
  recyclerApp = nil;

  if ([defaults boolForKey: @"uses_recycler"])
    {
      [self connectRecycler];
    }

  prefController = [PrefController new];  
  
  history = [[History alloc] init];
  
  openWithController = [[OpenWithController alloc] init];
  runExtController = [[RunExternalController alloc] init];
  	    
  finder = [Finder finder];
  
  fiend = [[Fiend alloc] init];
  
  if ([defaults boolForKey: @"usefiend"])
    [self showFiend: nil];
  else
    [self hideFiend: nil];
    
  vwrsManager = [GWViewersManager viewersManager];
  [vwrsManager showViewers];
  
  inspector = [Inspector new];
  if ([defaults boolForKey: @"uses_inspector"]) {  
    [self showInspector: nil]; 
  }
  
  fileOpsManager = [Operation new];
  
  ddbd = nil;
  [self connectDDBd];
  
  mdextractor = nil;
  if ([defaults boolForKey: @"GSMetadataIndexingEnabled"]) {
    [self connectMDExtractor];
  }
    
  [defaults synchronize];
  terminating = NO;
  
  [self setContextHelp];
  
  storedAppinfoPath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"GSLaunchedApplications"];
  lockpath = [storedAppinfoPath stringByAppendingPathExtension: @"lock"];   
  storedAppinfoLock = [[NSDistributedLock alloc] initWithPath: lockpath];

  launchedApps = [NSMutableArray new];   
  activeApplication = nil;   
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
  
  NS_DURING
    {
      [NSApp setServicesProvider:self];
    }
  NS_HANDLER
    {
      NSLog(@"setServicesProvider: %@", localException);
    }
  NS_ENDHANDLER

  [nc addObserver: self 
         selector: @selector(fileSystemWillChange:) 
             name: @"GWFileSystemWillChangeNotification"
           object: nil];

  [nc addObserver: self 
         selector: @selector(fileSystemDidChange:) 
             name: @"GWFileSystemDidChangeNotification"
           object: nil];

  [dnc addObserver: self 
          selector: @selector(changeDefaultEditor:) 
              name: @"GWDefaultEditorChangedNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(thumbnailsDidChange:) 
              name: @"GWThumbnailsDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(removableMediaPathsDidChange:) 
              name: @"GSRemovableMediaPathsDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(reservedMountNamesDidChange:) 
              name: @"GSReservedMountNamesDidChangeNotification"
            object: nil];
 
  [dnc addObserver: self 
          selector: @selector(hideDotsFileDidChange:) 
              name: @"GSHideDotFilesDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(customDirectoryIconDidChange:) 
              name: @"GWCustomDirectoryIconDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(applicationForExtensionsDidChange:) 
              name: @"GWAppForExtensionDidChangeNotification"
            object: nil];
  
  [self initializeWorkspace]; 
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
  [self resetSelectedPaths];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app 
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  
#define TEST_CLOSE(o, w) if ((o) && ([w isVisible])) [w close]
  
  if ([fileOpsManager operationsPending]) {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"Wait the operations to terminate!", @""),
					        NSLocalizedString(@"Ok", @""), 
                  nil, 
                  nil);  
    return NSTerminateCancel;  
  }
    
  if ((dontWarnOnQuit == NO) && (loggingout == NO))
    {
      if (NSRunAlertPanel(NSLocalizedString(@"Quit!", @""),
			  NSLocalizedString(@"Do you really want to quit?", @""),
			  NSLocalizedString(@"Yes", @""),
			  NSLocalizedString(@"No", @""),
			  nil,
			  nil) != NSAlertDefaultReturn)
      {
	return NSTerminateCancel;
      }
  }

  [wsnc removeObserver: self];
  
  fswnotifications = NO;
  terminating = YES;

  [self updateDefaults];
  
  TEST_CLOSE (prefController, [prefController myWin]);
  TEST_CLOSE (fiend, [fiend myWin]);
  TEST_CLOSE (history, [history myWin]); 
  TEST_CLOSE (startAppWin, [startAppWin win]);

  if (fswatcher)
    {
      NSConnection *conn = [(NSDistantObject *)fswatcher connectionForProxy];
  
      if ([conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          NS_DURING
            [fswatcher unregisterClient: (id <FSWClientProtocol>)self];  
          NS_HANDLER
            NSLog(@"[GFinder shouldTerminateApplication] unregister fswatcher: %@", [localException description]);
          NS_ENDHANDLER
          DESTROY (fswatcher);
        }
    }

  [inspector updateDefaults];

  [finder stopAllSearchs];
  
  if (recyclerApp)
    {
      NSConnection *conn;

      conn = [(NSDistantObject *)recyclerApp connectionForProxy];
  
      if (conn && [conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          [recyclerApp terminateApplication];
          DESTROY (recyclerApp);
        }
    }
  
  if (ddbd)
    {
      NSConnection *conn = [(NSDistantObject *)ddbd connectionForProxy];
  
      if (conn && [conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          DESTROY (ddbd);
        }
    }

  if (mdextractor)
    {
      NSConnection *conn = [(NSDistantObject *)mdextractor connectionForProxy];
  
      if (conn && [conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          DESTROY (mdextractor);
        }
  }
  		
  return NSTerminateNow;
}

- (NSString *)defEditor
{
  return defEditor;
}

- (NSString *)defXterm
{
  return defXterm;
}

- (NSString *)defXtermArgs
{
  return defXtermArgs;
}

- (GWViewersManager *)viewersManager
{
  return vwrsManager;
}

- (History *)historyWindow
{
  return history;
}

- (id)rootViewer
{
  return nil;
}

- (void)showRootViewer
{
  id viewer = [vwrsManager rootViewer];
  
  if (viewer == nil) {
    [vwrsManager showRootViewer];
  } else {
    [viewer activate];
  }
}

- (void)rootViewerSelectFiles:(NSArray *)paths
{
  NSString *path = [[paths objectAtIndex: 0] stringByDeletingLastPathComponent];
  FSNode *parentnode = [FSNode nodeWithPath: path];
  NSArray *selection = [NSArray arrayWithArray: paths];
  id viewer = [vwrsManager rootViewer];
  id nodeView = nil;

  if ([paths count] == 1)
    {
      FSNode *node = [FSNode nodeWithPath: [paths objectAtIndex: 0]];
      
      if ([node isDirectory] && ([node isPackage] == NO))
        {
          parentnode = [FSNode nodeWithPath: [node path]];
          selection = [NSArray arrayWithObject: [node path]];
        }
    }
  
  if (viewer == nil)
    viewer = [vwrsManager showRootViewer];
  
  nodeView = [viewer nodeView];
  [nodeView showContentsOfNode: parentnode];
  [nodeView selectRepsOfPaths: selection];
  
  if ([nodeView respondsToSelector: @selector(scrollSelectionToVisible)])
    [nodeView scrollSelectionToVisible];
}

- (void)newViewerAtPath:(NSString *)path
{
  FSNode *node = [FSNode nodeWithPath: path];

  [vwrsManager viewerForNode: node 
                    showType: 0
               showSelection: NO
                    forceNew: NO
	             withKey: nil];
}

- (void)changeDefaultEditor:(NSNotification *)notif
{
  NSString *editor = [notif object];

  if (editor) {
    ASSIGN (defEditor, editor);
  }
}

- (void)changeDefaultXTerm:(NSString *)xterm 
                 arguments:(NSString *)args
{
  ASSIGN (defXterm, xterm);
  
  if ([args length]) {
    ASSIGN (defXtermArgs, args);
  } else {
    DESTROY (defXtermArgs);
  }
}

- (void)setUseTerminalService:(BOOL)value
{
  teminalService = value;
}

- (NSString *)gfinderProcessName
{
  return gwProcessName;
}

- (void)updateDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id entry;

  if ([[prefController myWin] isVisible])
    {
      [prefController updateDefaults]; 
    }
	
  if ((fiend != nil) && ([[fiend myWin] isVisible]))
    {
      [fiend updateDefaults]; 
      [defaults setBool: YES forKey: @"usefiend"];
    }
  else
    {
      [defaults setBool: NO forKey: @"usefiend"];
    }

  [history updateDefaults];

  [defaults setObject: [fsnodeRep hiddenPaths] 
               forKey: @"hiddendirs"];

  entry = [NSNumber numberWithInt: [fsnodeRep defaultSortOrder]];
  [defaults setObject: entry forKey: @"default_sortorder"];

  [vwrsManager updateDefaults];

  [finder updateDefaults];

  [defaults setObject: defEditor forKey: @"defaulteditor"];
  [defaults setObject: defXterm forKey: @"defxterm"];
  if (defXtermArgs != nil)
    {
      [defaults setObject: defXtermArgs forKey: @"defaultxtermargs"];
    }

  [defaults setBool: teminalService forKey: @"terminal_services"];
	
  [defaults setBool: [fsnodeRep usesThumbnails]  
             forKey: @"use_thumbnails"];

  entry = [NSNumber numberWithInt: maxHistoryCache];
  [defaults setObject: entry forKey: @"history_cache"];

  [defaults setBool: [[inspector win] isVisible] forKey: @"uses_inspector"];

  [defaults setBool: (recyclerApp != nil) forKey: @"uses_recycler"];

	[defaults synchronize];
}

- (void)setContextHelp
{
  NSHelpManager *manager = [NSHelpManager sharedHelpManager];
  NSString *help;

  help = @"History.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[history myWin] contentView]];

  help = @"Fiend.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[fiend myWin] contentView]];

  help = @"RunExternal.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[runExtController win] contentView]];

  help = @"Preferences.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[prefController myWin] contentView]];

  help = @"Inspector.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[inspector win] contentView]];
}

- (NSAttributedString *)contextHelpFromName:(NSString *)fileName
{
  NSString *bpath = [[NSBundle mainBundle] bundlePath];
  NSString *resPath = [bpath stringByAppendingPathComponent: @"Resources"];
  NSArray *languages = [NSUserDefaults userLanguages];
  NSUInteger i;
     
  for (i = 0; i < [languages count]; i++)
    {
      NSString *language = [languages objectAtIndex: i];
      NSString *langDir = [NSString stringWithFormat: @"%@.lproj", language];  
      NSString *helpPath = [langDir stringByAppendingPathComponent: @"Help"];
      
      helpPath = [resPath stringByAppendingPathComponent: helpPath];
      helpPath = [helpPath stringByAppendingPathComponent: fileName];
      
      if ([fm fileExistsAtPath: helpPath])
	{
	  NS_DURING
	    {
	      NSAttributedString *help = [[NSAttributedString alloc] initWithPath: helpPath
							       documentAttributes: NULL];
	      return AUTORELEASE (help);
	    }
	  NS_HANDLER
	    {
	      return nil;
	    }
	  NS_ENDHANDLER;
	}
    }
  
  return nil;
}

- (void)startXTermOnDirectory:(NSString *)dirPath
{
  if (teminalService) {
    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    NSArray *types = [NSArray arrayWithObject: NSFilenamesPboardType];

    [pboard declareTypes: types owner: self];
    [pboard setPropertyList: [NSArray arrayWithObject: dirPath]
									  forType: NSFilenamesPboardType];
                    
    NSPerformService(@"Terminal/Open shell here", pboard);  
                      
  } else {  
	  NSTask *task = [NSTask new];

	  [task setCurrentDirectoryPath: dirPath];
	  [task setLaunchPath: defXterm];

    if (defXtermArgs) {
	    NSArray *args = [defXtermArgs componentsSeparatedByString: @" "];
	    [task setArguments: args];
    }

	  [task launch];

    /* Reap the child when the terminal exits to prevent zombie processes. */
    __block id obs = [[NSNotificationCenter defaultCenter]
        addObserverForName: NSTaskDidTerminateNotification
                    object: task
                     queue: [NSOperationQueue mainQueue]
                usingBlock: ^(NSNotification *n) {
      [[NSNotificationCenter defaultCenter] removeObserver: obs];
      obs = nil;
      (void)[task terminationStatus];
    }];
  }
}

- (int)defaultSortType
{
  return [fsnodeRep defaultSortOrder];
}

- (void)setDefaultSortType:(int)type
{
  [fsnodeRep setDefaultSortOrder: type];
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)anItem
{	
  SEL action = [anItem action];

  if (sel_isEqual(action, @selector(showRecycler:))) {
    return YES;

  } else if (sel_isEqual(action, @selector(emptyRecycler:))) {
    return ([trashContents count] != 0);

  } else if (sel_isEqual(action, @selector(activateContextHelp:))) {
    return ([NSHelpManager isContextHelpModeActive] == NO);

  } else if (sel_isEqual(action, @selector(cut:))
                || sel_isEqual(action, @selector(copy:))
                  || sel_isEqual(action, @selector(paste:))) {
    NSWindow *kwin = [NSApp keyWindow];
  }
  return YES;
}
           
- (void)fileSystemWillChange:(NSNotification *)notif
{
}

- (void)fileSystemDidChange:(NSNotification *)notif
{
  NSDictionary *info = (NSDictionary *)[notif object];
  
  if (info) { 
@autoreleasepool {   
    NSString *source = [info objectForKey: @"source"];
    NSString *destination = [info objectForKey: @"destination"];
  
    if ([source isEqual: trashPath] || [destination isEqual: trashPath]) {    
      [self _updateTrashContents];
    }
    
    if (ddbd != nil) {
      [ddbd fileSystemDidChange: [NSArchiver archivedDataWithRootObject: info]];
    }
    
  } // @autoreleasepool
  } 
}

- (void)setSelectedPaths:(NSArray *)paths
{
 
  if (paths && ([selectedPaths isEqualToArray: paths] == NO))
    {
      NSUInteger i;
      NSMutableArray *onlyDirPaths;
      NSFileManager *fileMgr;

      ASSIGN (selectedPaths, paths);
    
      if ([[inspector win] isVisible])
        {
          [inspector setCurrentSelection: paths];
        }
      
      /* we extract from the selection only valid directories */
      onlyDirPaths = [NSMutableArray arrayWithCapacity:1];
      fileMgr = [NSFileManager defaultManager];
      for (i = 0; i < [paths count]; i++)
        {
          NSString *p;
          BOOL isDir;
          p = [paths objectAtIndex:i];
          if([fileMgr fileExistsAtPath:p isDirectory:&isDir])
            if (isDir)
              [onlyDirPaths addObject:p];
        }
      if ([onlyDirPaths count] > 0)
        [finder setCurrentSelection: onlyDirPaths];
    
      [[NSNotificationCenter defaultCenter]
 				 postNotificationName: @"GWCurrentSelectionChangedNotification"
                                               object: nil];      
    }
}

- (void)resetSelectedPaths
{
  if (selectedPaths == nil) {
    return;
  }
  
  if ([[inspector win] isVisible]) {
    [inspector setCurrentSelection: selectedPaths];
  }
				
  [[NSNotificationCenter defaultCenter]
 				 postNotificationName: @"GWCurrentSelectionChangedNotification"
	 								        object: nil];    
}

- (NSArray *)selectedPaths
{
  return selectedPaths;
}

- (void)openSelectedPaths:(NSArray *)paths newViewer:(BOOL)newv
{
  NSUInteger count = [paths count];
  NSUInteger i;
  
  [self setSelectedPaths: paths];      

  if (count > MAX_FILES_TO_OPEN_DIALOG) {
    NSString *msg1 = NSLocalizedString(@"Are you sure you want to open", @"");
    NSString *msg2 = NSLocalizedString(@"items?", @"");
  
    if (NSRunAlertPanel(nil,
                        [NSString stringWithFormat: @"%@ %lu %@", msg1, (unsigned long)count, msg2],
                NSLocalizedString(@"Cancel", @""),
                NSLocalizedString(@"Yes", @""),
                nil)) {
      return;
    }
  }
  
  for (i = 0; i < count; i++) {
    NSString *apath = [paths objectAtIndex: i];
    
    if ([fm fileExistsAtPath: apath]) {
      NSString *defApp = nil, *type = nil;

      NS_DURING
        {
	  [ws getInfoForFile: apath application: &defApp type: &type];     

	  if (type != nil)
	    {
	      if ((type == NSDirectoryFileType) || (type == NSFilesystemFileType))
		{
		  if (newv)
		    [self newViewerAtPath: apath];    
		}
	      else if ((type == NSPlainFileType) || ([type isEqual: NSShellCommandFileType]))
		{
		  [self openFile: apath];
		}
	      else if (type == NSApplicationFileType)
		{
		  [ws launchApplication: apath];
		}
	    }
        }
      NS_HANDLER
        {
          NSRunAlertPanel(NSLocalizedString(@"error", @""), 
              [NSString stringWithFormat: @"%@ %@!", 
               NSLocalizedString(@"Can't open ", @""), [apath lastPathComponent]],
                                            NSLocalizedString(@"OK", @""), 
                                            nil, 
                                            nil);                                     
        }
      NS_ENDHANDLER
    }
  }
}

- (void)openSelectedPathsWith
{
  BOOL canopen = YES;
  NSUInteger i;

  for (i = 0; i < [selectedPaths count]; i++) {
    FSNode *node = [FSNode nodeWithPath: [selectedPaths objectAtIndex: i]];

    if (([node isPlain] == NO) 
          && (([node isPackage] == NO) || [node isApplication])) {
      canopen = NO;
      break;
    }
  }
  
  if (canopen) {
    [openWithController activate];
  }
}

- (BOOL)openFile:(NSString *)fullPath
{
  NSString *appName = nil;
  NSString *type = nil;
  BOOL success;
  NSURL *aURL;

  aURL = nil;
  [ws getInfoForFile: fullPath application: &appName type: &type];

  if (type == NSDirectoryFileType)
    {
      [self newViewerAtPath: fullPath];
      return YES;
    }
  else if (type == NSPlainFileType)
    {
      if ([[fullPath pathExtension] isEqualToString: @"webloc"])
	{
	  NSDictionary *weblocDict;
	  NSString *urlString;

	  weblocDict = [NSDictionary dictionaryWithContentsOfFile: fullPath];
	  urlString = [weblocDict objectForKey:@"URL"];
	  aURL = [NSURL URLWithString: urlString];
        }
    }
  
  NS_DURING
    {
      if (aURL == nil)
	success = [ws openFile: fullPath withApplication: appName];
      else
	success = [ws openURL: aURL];
    }
  NS_HANDLER
    {
      NSRunAlertPanel(NSLocalizedString(@"error", @""), 
		      [NSString stringWithFormat: @"%@ %@!", 
				NSLocalizedString(@"Can't open ", @""), [fullPath lastPathComponent]],
		      NSLocalizedString(@"OK", @""), 
		      nil, 
		      nil);                                     
      success = NO;
    }
  NS_ENDHANDLER  
  
    return success;  
}

- (BOOL)application:(NSApplication *)theApplication 
           openFile:(NSString *)filename
{
  BOOL isDir;

  if ([filename isAbsolutePath] 
                    && [fm fileExistsAtPath: filename isDirectory: &isDir]) {
    NSString *type = nil;
    NSString *appName;

    [ws getInfoForFile: filename application: &appName type: &type];
    if (isDir) {
      if ([[filename pathExtension] isEqual: @"lsf"]) {
        return [finder openLiveSearchFolderAtPath: filename];
      } else if (type == NSDirectoryFileType) {
        [self newViewerAtPath: filename];
        return YES;
      }
    }

    // it is a direcotry or a bundle, which is a NSFilePlainType
    [self openFile: filename];
    return YES;
  } 

  return NO;
}

- (NSArray *)getSelectedPaths
{
  return selectedPaths;
}

- (void)showPasteboardData:(NSData *)data 
                    ofType:(NSString *)type
                  typeIcon:(NSImage *)icon
{
  if ([[inspector win] isVisible]) {
    if ([inspector canDisplayDataOfType: type]) {
      [inspector showData: data ofType: type];
    }
  }
}

- (void)newObjectAtPath:(NSString *)basePath 
            isDirectory:(BOOL)directory
{
  NSString *fullPath;
  NSString *fileName;
  NSString *operation;
  NSMutableDictionary *notifObj;  
  unsigned suff;
    
	if ([self verifyFileAtPath: basePath] == NO) {
		return;
	}
	
	if ([fm isWritableFileAtPath: basePath] == NO) {
		NSString *err = NSLocalizedString(@"Error", @"");
		NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
		NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
		return;
	}

  if (directory) {
    fileName = @"NewFolder";
    operation = @"GFinderCreateDirOperation";
  } else {
    fileName = @"NewFile";
    operation = @"GFinderCreateFileOperation";
  }

  fullPath = [basePath stringByAppendingPathComponent: fileName];
  	
  if ([fm fileExistsAtPath: fullPath]) {    
    suff = 1;
    while (1) {    
      NSString *s = [fileName stringByAppendingFormat: @"%i", suff];
      fullPath = [basePath stringByAppendingPathComponent: s];
      if ([fm fileExistsAtPath: fullPath] == NO) {
        fileName = [NSString stringWithString: s];
        break;      
      }      
      suff++;
    }     
  }

  notifObj = [NSMutableDictionary dictionaryWithCapacity: 1];		
  [notifObj setObject: operation forKey: @"operation"];	
  [notifObj setObject: basePath forKey: @"source"];	
  [notifObj setObject: basePath forKey: @"destination"];	
  [notifObj setObject: [NSArray arrayWithObject: fileName] forKey: @"files"];	

  [self performFileOperation: notifObj];
}

- (void)duplicateFiles
{
  NSString *basePath;
  NSMutableArray *files;
  NSInteger tag;
  NSUInteger i;

  basePath = [NSString stringWithString: [selectedPaths objectAtIndex: 0]];
  basePath = [basePath stringByDeletingLastPathComponent];

	if ([fm isWritableFileAtPath: basePath] == NO) {
		NSString *err = NSLocalizedString(@"Error", @"");
		NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
		NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
		return;
	}

  files = [NSMutableArray array];
  for (i = 0; i < [selectedPaths count]; i++) {
    [files addObject: [[selectedPaths objectAtIndex: i] lastPathComponent]];
  }

  [self performFileOperation: NSWorkspaceDuplicateOperation 
              source: basePath destination: basePath files: files tag: &tag];
}

- (void)deleteFiles
{
  NSString *basePath;
  NSMutableArray *files;
  NSInteger tag;
  NSUInteger i;

  basePath = [NSString stringWithString: [selectedPaths objectAtIndex: 0]];
  basePath = [basePath stringByDeletingLastPathComponent];

	if ([fm isWritableFileAtPath: basePath] == NO) {
		NSString *err = NSLocalizedString(@"Error", @"");
		NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
		NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
		return;
	}

  files = [NSMutableArray array];
  for (i = 0; i < [selectedPaths count]; i++) {
    [files addObject: [[selectedPaths objectAtIndex: i] lastPathComponent]];
  }

  [self performFileOperation: NSWorkspaceDestroyOperation 
              source: basePath destination: basePath files: files tag: &tag];
}

- (void)moveToTrash
{
  NSArray *vpaths = [ws mountedLocalVolumePaths];
  NSMutableArray *umountPaths = [NSMutableArray array];
  NSMutableArray *files = [NSMutableArray array];
  NSUInteger i;
  NSInteger tag;

  for (i = 0; i < [selectedPaths count]; i++) {
    NSString *path = [selectedPaths objectAtIndex: i];

    if ([vpaths containsObject: path]) {
      [umountPaths addObject: path];
    } else {
      [files addObject: [path lastPathComponent]];
    }
  }

  for (i = 0; i < [umountPaths count]; i++) {
    [ws unmountAndEjectDeviceAtPath: [umountPaths objectAtIndex: i]];
  }

  if ([files count])
    {
      NSString *basePath = [NSString stringWithString: [selectedPaths objectAtIndex: 0]];

      basePath = [basePath stringByDeletingLastPathComponent];

      if ([fm isWritableFileAtPath: basePath] == NO)
        {
          NSString *err = NSLocalizedString(@"Error", @"");
          NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
          NSString *buttstr = NSLocalizedString(@"Continue", @"");
          NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
          return;
        }

      [self performFileOperation: NSWorkspaceRecycleOperation
                          source: basePath destination: trashPath 
                           files: files tag: &tag];
    }
}

- (BOOL)verifyFileAtPath:(NSString *)path
{
  if ([fm fileExistsAtPath: path] == NO)
    {
      NSString *err = NSLocalizedString(@"Error", @"");
      NSString *msg = NSLocalizedString(@": no such file or directory!", @"");
      NSString *buttstr = NSLocalizedString(@"Continue", @"");
      NSMutableDictionary *notifObj = [NSMutableDictionary dictionaryWithCapacity: 1];		
      NSString *basePath = [path stringByDeletingLastPathComponent];
		
      NSRunAlertPanel(err, [NSString stringWithFormat: @"%@%@", path, msg], buttstr, nil, nil);   

      [notifObj setObject: NSWorkspaceDestroyOperation forKey: @"operation"];	
      [notifObj setObject: basePath forKey: @"source"];	
      [notifObj setObject: basePath forKey: @"destination"];	
      [notifObj setObject: [NSArray arrayWithObjects: path, nil] forKey: @"files"];	

      [[NSNotificationCenter defaultCenter]
 					 postNotificationName: @"GWFileSystemWillChangeNotification"
						       object: notifObj];
      [[NSNotificationCenter defaultCenter]
 				  postNotificationName: @"GWFileSystemDidChangeNotification"
						object: notifObj];
      return NO;
    }
	
  return YES;
}

- (void)setUsesThumbnails:(BOOL)value
{  
  if ([fsnodeRep usesThumbnails] == value) {
    return;
  }
  
  [fsnodeRep setUseThumbnails: value];
  
  [vwrsManager thumbnailsDidChangeInPaths: nil];
}

- (void)thumbnailsDidChange:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSArray *deleted = [info objectForKey: @"deleted"];	
  NSArray *created = [info objectForKey: @"created"];	
  NSMutableArray *tmbdirs = [NSMutableArray array];
  NSUInteger i;

  [fsnodeRep thumbnailsDidChange: info];

  if ([fsnodeRep usesThumbnails] == NO)
    return;

  NSString *thumbnailDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];

  thumbnailDir = [thumbnailDir stringByAppendingPathComponent: @"Thumbnails"];
  
  if (deleted && [deleted count])
    {
      for (i = 0; i < [deleted count]; i++) {
        NSString *path = [deleted objectAtIndex: i];
        NSString *dir = [path stringByDeletingLastPathComponent];

        if ([tmbdirs containsObject: dir] == NO) {
          [tmbdirs addObject: dir];
        }
      }

      [vwrsManager thumbnailsDidChangeInPaths: tmbdirs];
      [tmbdirs removeAllObjects];
    }

    if (created && [created count]) {
      NSString *dictName = @"thumbnails.plist";
      NSString *dictPath = [thumbnailDir stringByAppendingPathComponent: dictName];
      
      if ([fm fileExistsAtPath: dictPath]) {
        NSDictionary *tdict = [NSDictionary dictionaryWithContentsOfFile: dictPath];

        for (i = 0; i < [created count]; i++) {
          NSString *key = [created objectAtIndex: i];
          NSString *dir = [key stringByDeletingLastPathComponent];
          NSString *tumbname = [tdict objectForKey: key];
          NSString *tumbpath = [thumbnailDir stringByAppendingPathComponent: tumbname]; 

          if ([fm fileExistsAtPath: tumbpath]) {        
            if ([tmbdirs containsObject: dir] == NO) {
              [tmbdirs addObject: dir];
            }
          }
        }
      }
      
      [vwrsManager thumbnailsDidChangeInPaths: tmbdirs];
    }
}

- (void)removableMediaPathsDidChange:(NSNotification *)notif
{
  NSArray *removables;

  removables = [[[NSUserDefaults standardUserDefaults] persistentDomainForName: NSGlobalDomain] objectForKey: @"GSRemovableMediaPaths"];

  [fsnodeRep setVolumes: removables];
}

- (void)reservedMountNamesDidChange:(NSNotification *)notif
{

}

- (void)hideDotsFileDidChange:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  BOOL hide = [[info objectForKey: @"hide"] boolValue];
  
  [fsnodeRep setHideSysFiles: hide];
  [vwrsManager hideDotsFileDidChange: hide];

  if (fiend != nil) {
    [fiend checkIconsAfterDotsFilesChange];
  }
}

- (void)hiddenFilesDidChange:(NSArray *)paths
{
  [vwrsManager hiddenFilesDidChange: paths];
  if (fiend != nil) {
    [fiend checkIconsAfterHidingOfPaths: paths];
  }
}

- (void)customDirectoryIconDidChange:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *dirpath = [info objectForKey: @"path"];
  NSString *imgpath = [info objectForKey: @"icon_path"];  
  NSArray *paths;	

  [fsnodeRep removeCachedIconsForKey: imgpath];
  
  if ([dirpath isEqual: path_separator()] == NO) {
    dirpath = [dirpath stringByDeletingLastPathComponent];
  }
  
  paths = [NSArray arrayWithObject: dirpath];
  
  [vwrsManager thumbnailsDidChangeInPaths: paths];
}

- (void)applicationForExtensionsDidChange:(NSNotification *)notif
{
  NSDictionary *changedInfo = [notif userInfo];
  NSString *app = [changedInfo objectForKey: @"app"];
  NSArray *extensions = [changedInfo objectForKey: @"exts"];
  NSUInteger i;

  for (i = 0; i < [extensions count]; i++) {
    [[NSWorkspace sharedWorkspace] setBestApp: app
                                       inRole: nil 
                                 forExtension: [extensions objectAtIndex: i]];  
  }
}

- (int)maxHistoryCache
{
  return maxHistoryCache;
}

- (void)setMaxHistoryCache:(int)value
{
  maxHistoryCache = value;
}

- (void)connectFSWatcher
{
  if (fswatcher == nil)
  {
    fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher" 
                                                                  host: @""];

    if (fswatcher == nil)
    {
      NSString *cmd;
      NSMutableArray *arguments;
      unsigned i;
    
      cmd = [NSTask launchPathForTool: @"fswatcher"];    
                
      [startAppWin showWindowWithTitle: @"GFinder"
                               appName: @"fswatcher"
                             operation: NSLocalizedString(@"starting:", @"")
                          maxProgValue: 40.0];
    
      arguments = [NSMutableArray arrayWithCapacity:2];
      [arguments addObject:@"--daemon"];
      [arguments addObject:@"--auto"];  
      {
        NSTask *fswTask = [NSTask launchedTaskWithLaunchPath: cmd arguments: arguments];
        __block id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName: NSTaskDidTerminateNotification
                        object: fswTask
                         queue: [NSOperationQueue mainQueue]
                    usingBlock: ^(NSNotification *n) {
          [[NSNotificationCenter defaultCenter] removeObserver: obs];
          obs = nil;
          (void)[fswTask terminationStatus];
        }];
      }

      for (i = 1; i <= 40; i++) {
        [startAppWin updateProgressBy: 1.0];
        [NSThread sleepForTimeInterval: 0.1];

        fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher"
                                                                      host: @""];
        if (fswatcher)
	{
          [startAppWin updateProgressBy: 40.0 - (double)i];
          break;
        }
      }

      [[startAppWin win] close];
    }
    
    if (fswatcher)
    {
      [fswatcher setProtocolForProxy: @protocol(FSWatcherProtocol)];
    
	    [[NSNotificationCenter defaultCenter] addObserver: self
	                   selector: @selector(fswatcherConnectionDidDie:)
		                     name: NSConnectionDidDieNotification
		                   object: [fswatcher connectionForProxy]];
                       
	    [fswatcher registerClient: (id <FSWClientProtocol>)self 
                isGlobalWatcher: NO];
    } else {
      fswnotifications = NO;
      NSRunAlertPanel(nil,
              NSLocalizedString(@"unable to contact fswatcher\nfswatcher notifications disabled!", @""),
              NSLocalizedString(@"Ok", @""),
              nil, 
              nil);  
    }
  }
}

- (void)fswatcherConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
	                    name: NSConnectionDidDieNotification
	                  object: connection];

  NSAssert(connection == [fswatcher connectionForProxy],
		                                  NSInternalInconsistencyException);
  RELEASE (fswatcher);
  fswatcher = nil;

  if (NSRunAlertPanel(nil,
                    NSLocalizedString(@"The fswatcher connection died.\nDo you want to restart it?", @""),
                    NSLocalizedString(@"Yes", @""),
                    NSLocalizedString(@"No", @""),
                    nil)) {
    [self connectFSWatcher]; 
    
    if (fswatcher != nil) {
      NSEnumerator *enumerator = [watchedPaths objectEnumerator];
      NSString *path;
      
      while ((path = [enumerator nextObject])) {
        unsigned count = [watchedPaths countForObject: path];
        unsigned i;
      
        for (i = 0; i < count; i++) {
          [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
        }
      }
    }
                   
  } else {
    fswnotifications = NO;
    NSRunAlertPanel(nil,
                    NSLocalizedString(@"fswatcher notifications disabled!", @""),
                    NSLocalizedString(@"Ok", @""),
                    nil, 
                    nil);  
  }
}

- (oneway void)watchedPathDidChange:(NSData *)dirinfo
{
@autoreleasepool {
  NSDictionary *info = [NSUnarchiver unarchiveObjectWithData: dirinfo];
  NSString *event = [info objectForKey: @"event"];

  if ([event isEqual: @"GWFileDeletedInWatchedDirectory"]
            || [event isEqual: @"GWFileCreatedInWatchedDirectory"]) {
    NSString *path = [info objectForKey: @"path"];

    if ([path isEqual: trashPath]) {
      [self _updateTrashContents];
    }
  }
  
	[[NSNotificationCenter defaultCenter]
 				 postNotificationName: @"GWFileWatcherFileDidChangeNotification"
	 								     object: info];  
  } // @autoreleasepool                       
}

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo
{
}

- (void)connectRecycler
{
  if (recyclerApp == nil)
    {
      recyclerApp = [NSConnection rootProxyForConnectionWithRegisteredName: @"Recycler" 
                                                                      host: @""];
      
      if (recyclerApp == nil)
        {
          unsigned i;
          
          [startAppWin showWindowWithTitle: @"GFinder"
                                   appName: @"Recycler"
                                 operation: NSLocalizedString(@"starting:", @"")
                              maxProgValue: 80.0];
          
          [ws launchApplication: @"Recycler"];
          
          for (i = 1; i <= 80; i++)
            {
              [startAppWin updateProgressBy: 1.0];
              [NSThread sleepForTimeInterval: 0.1];
              recyclerApp = [NSConnection rootProxyForConnectionWithRegisteredName: @"Recycler"
                                                                              host: @""];
              if (recyclerApp)
                {
                  [startAppWin updateProgressBy: 80.0 - (double)i];
                  break;
                }
            }

          [[startAppWin win] close];
        }
    
      if (recyclerApp)
        {
          NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
          id item = [menu itemWithTitle: NSLocalizedString(@"Show Recycler", @"")];

          if (item != nil) {
            [item setTitle: NSLocalizedString(@"Hide Recycler", @"")];
          }
    
          [recyclerApp setProtocolForProxy: @protocol(RecyclerAppProtocol)];
    
          [[NSNotificationCenter defaultCenter] addObserver: self
                                                   selector: @selector(recyclerConnectionDidDie:)
                                                       name: NSConnectionDidDieNotification
                                                     object: [recyclerApp connectionForProxy]];
        } 
      else
        {
          NSRunAlertPanel(nil,
                          NSLocalizedString(@"unable to contact Recycler!", @""),
                          NSLocalizedString(@"Ok", @""),
                          nil, 
                          nil);  
        }
    }
}

- (void)recyclerConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  id item = [menu itemWithTitle: NSLocalizedString(@"Hide Recycler", @"")];

  [[NSNotificationCenter defaultCenter] removeObserver: self
	                    name: NSConnectionDidDieNotification
	                  object: connection];

  NSAssert(connection == [recyclerApp connectionForProxy],
		                                  NSInternalInconsistencyException);
  RELEASE (recyclerApp);
  recyclerApp = nil;

  if (item != nil) {
    [item setTitle: NSLocalizedString(@"Show Recycler", @"")];
  }
    
  if (recyclerCanQuit == NO) {  
    if (NSRunAlertPanel(nil,
                      NSLocalizedString(@"The Recycler connection died.\nDo you want to restart it?", @""),
                      NSLocalizedString(@"Yes", @""),
                      NSLocalizedString(@"No", @""),
                      nil)) {
      [self connectRecycler]; 
    }    
  }
}

- (void)connectDDBd
{
  if (ddbd == nil)
    {
      ddbd = [NSConnection rootProxyForConnectionWithRegisteredName: @"ddbd" 
							       host: @""];

      if (ddbd == nil)
	{
	  NSString *cmd;
	  NSMutableArray *arguments;
	  unsigned i;
    
	  cmd = [NSTask launchPathForTool: @"ddbd"];    
                
	  [startAppWin showWindowWithTitle: @"GFinder"
				   appName: @"ddbd"
				 operation: NSLocalizedString(@"starting:", @"")
			      maxProgValue: 40.0];
 
	  arguments = [NSMutableArray arrayWithCapacity:2];
	  [arguments addObject:@"--daemon"];
	  [arguments addObject:@"--auto"];
	  {
	    NSTask *ddbdTask = [NSTask launchedTaskWithLaunchPath: cmd arguments: arguments];
	    __block id obs = [[NSNotificationCenter defaultCenter]
	        addObserverForName: NSTaskDidTerminateNotification
	                    object: ddbdTask
	                     queue: [NSOperationQueue mainQueue]
	                usingBlock: ^(NSNotification *n) {
	      [[NSNotificationCenter defaultCenter] removeObserver: obs];
	      obs = nil;
	      (void)[ddbdTask terminationStatus];
	    }];
	  }

	  for (i = 1; i <= 40; i++)
	    {
	      [startAppWin updateProgressBy: 1.0];
	      [NSThread sleepForTimeInterval: 0.1];

	      ddbd = [NSConnection rootProxyForConnectionWithRegisteredName: @"ddbd"
								       host: @""];                  
	      if (ddbd)
		{
		  [startAppWin updateProgressBy: 40.0 - (double)i];
		  break;
		}
	    }

	  [[startAppWin win] close];
	}
    
      if (ddbd)
	{
	  [ddbd setProtocolForProxy: @protocol(DDBdProtocol)];
    
	  [[NSNotificationCenter defaultCenter] addObserver: self
						   selector: @selector(ddbdConnectionDidDie:)
						       name: NSConnectionDidDieNotification
						     object: [ddbd connectionForProxy]];
	}
      else
	{
	  NSRunAlertPanel(nil,
			  NSLocalizedString(@"unable to contact ddbd.", @""),
			  NSLocalizedString(@"Ok", @""),
			  nil, 
			  nil);  
	}
    }
}  
  
- (void)ddbdConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
	                    name: NSConnectionDidDieNotification
	                  object: connection];

  NSAssert(connection == [ddbd connectionForProxy],
		                                  NSInternalInconsistencyException);
  RELEASE (ddbd);
  ddbd = nil;
  
  NSRunAlertPanel(nil,
                  NSLocalizedString(@"ddbd connection died.", @""),
                  NSLocalizedString(@"Ok", @""),
                  nil,
                  nil);                
}

- (BOOL)ddbdactive
{
  return ((terminating == NO) && (ddbd != nil));
}

- (void)ddbdInsertPath:(NSString *)path
{
  if (ddbd != nil) {
    [ddbd insertPath: path];
  }
}

- (void)ddbdRemovePath:(NSString *)path
{
  if (ddbd != nil) {
    [ddbd removePath: path];
  }
}

- (NSString *)ddbdGetAnnotationsForPath:(NSString *)path
{
  if (ddbd != nil) {
    return [ddbd annotationsForPath: path];
  }
  
  return nil;
}

- (void)ddbdSetAnnotations:(NSString *)annotations
                   forPath:(NSString *)path
{
  if (ddbd != nil) {
    [ddbd setAnnotations: annotations forPath: path];
  }
}

- (void)connectMDExtractor
{
  if (mdextractor == nil) {
    mdextractor = [NSConnection rootProxyForConnectionWithRegisteredName: @"mdextractor" 
                                                                    host: @""];

    if (mdextractor == nil) {
	    NSString *cmd;
      unsigned i;
    
      cmd = [NSTask launchPathForTool: @"mdextractor"];    
                
      [startAppWin showWindowWithTitle: @"MDIndexing"
                               appName: @"mdextractor"
                             operation: NSLocalizedString(@"starting:", @"")
                          maxProgValue: 80.0];
    
      {
        NSTask *mdTask = [NSTask launchedTaskWithLaunchPath: cmd arguments: nil];
        __block id obs = [[NSNotificationCenter defaultCenter]
            addObserverForName: NSTaskDidTerminateNotification
                        object: mdTask
                         queue: [NSOperationQueue mainQueue]
                    usingBlock: ^(NSNotification *n) {
          [[NSNotificationCenter defaultCenter] removeObserver: obs];
          obs = nil;
          (void)[mdTask terminationStatus];
        }];
      }

      for (i = 1; i <= 80; i++) {
        [startAppWin updateProgressBy: 1.0];
        [NSThread sleepForTimeInterval: 0.1];

        mdextractor = [NSConnection rootProxyForConnectionWithRegisteredName: @"mdextractor"
                                                                        host: @""];                  
        if (mdextractor) {
          [startAppWin updateProgressBy: 80.0 - (double)i];
          break;
        }
      }

      [[startAppWin win] close];
    }
    
    if (mdextractor) {
      [mdextractor setProtocolForProxy: @protocol(MDExtractorProtocol)];
    
	    [[NSNotificationCenter defaultCenter] addObserver: self
	                   selector: @selector(mdextractorConnectionDidDie:)
		                     name: NSConnectionDidDieNotification
		                   object: [mdextractor connectionForProxy]];
    } else {
      NSRunAlertPanel(nil,
              NSLocalizedString(@"unable to contact mdextractor!", @""),
              NSLocalizedString(@"Ok", @""),
              nil,
              nil);
    }
  }
}

- (void)mdextractorConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
						  name: NSConnectionDidDieNotification
						object: connection];

  NSAssert(connection == [mdextractor connectionForProxy],
	   NSInternalInconsistencyException);
  RELEASE (mdextractor);
  mdextractor = nil;

  if (NSRunAlertPanel(nil,
		      NSLocalizedString(@"The mdextractor connection died.\nDo you want to restart it?", @""),
		      NSLocalizedString(@"Yes", @""),
		      NSLocalizedString(@"No", @""),
		      nil))
    {
      [self connectMDExtractor];
    }
}

- (void)slideImage:(NSImage *)image 
	      from:(NSPoint)fromPoint
		to:(NSPoint)toPoint
{
  [[NSWorkspace sharedWorkspace] slideImage: image from: fromPoint to: toPoint];
}


//
// NSServicesRequests protocol
//
- (id)validRequestorForSendType:(NSString *)sendType
                     returnType:(NSString *)returnType
{	
  BOOL sendOK = ((sendType == nil) || ([sendType isEqual: NSFilenamesPboardType]));
  BOOL returnOK = ((returnType == nil)
		   || ([returnType isEqual: NSFilenamesPboardType]
		       && (selectedPaths != nil)));

  if (sendOK && returnOK)
    {
      return self;
    }
  return nil;
}
	
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
  return ([[pboard types] indexOfObject: NSFilenamesPboardType] != NSNotFound);
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray *)types
{
	if ([types containsObject: NSFilenamesPboardType]) {
		NSArray *typesDeclared = [NSArray arrayWithObject: NSFilenamesPboardType];

		[pboard declareTypes: typesDeclared owner: self];
		
		return [pboard setPropertyList: selectedPaths 
									  		   forType: NSFilenamesPboardType];
	}
	
	return NO;
}

//
// Workspace service
//

- (void)openInWorkspace:(NSPasteboard *)pboard
	       userData:(NSString *)userData
		  error:(NSString **)error
{
  NSArray *types = [pboard types];
  if ([types containsObject: NSStringPboardType])
    {
      NSString *path = [pboard stringForType: NSStringPboardType];
      path = [path stringByTrimmingCharactersInSet:
		     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      [self openSelectedPaths: [NSArray arrayWithObject: path] newViewer: YES];
    }
}

//
// Menu Operations
//
- (void)showInfo:(id)sender
{
  
  [NSApp orderFrontStandardInfoPanel: self];
}

- (void)showPreferences:(id)sender
{
  [prefController activate]; 
}

- (void)activateContextHelp:(id)sender
{
  if ([NSHelpManager isContextHelpModeActive] == NO) {
    [NSHelpManager setContextHelpModeActive: YES];
  }
}

- (void)showViewer:(id)sender
{
  [vwrsManager showRootViewer];
}

- (id)currentViewer
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin && [vwrsManager hasViewerWithWindow: kwin])
    return [vwrsManager viewerWithWindow: kwin];

  return [vwrsManager rootViewer];
}

- (void)goEnclosingFolder:(id)sender
{
  [[self currentViewer] goEnclosingFolder];
}

- (void)goAllMyFiles:(id)sender
{
  [[self currentViewer] goAllMyFiles];
}

- (void)goDesktop:(id)sender
{
  [[self currentViewer] goDesktop];
}

- (void)goDocuments:(id)sender
{
  [[self currentViewer] goDocuments];
}

- (void)goDownloads:(id)sender
{
  [[self currentViewer] goDownloads];
}

- (void)goHome:(id)sender
{
  [[self currentViewer] goHome];
}

- (void)goComputer:(id)sender
{
  [[self currentViewer] goComputer];
}

- (void)goNetwork:(id)sender
{
  [[self currentViewer] goNetwork];
}

- (void)goApplications:(id)sender
{
  [[self currentViewer] goApplications];
}

- (void)goUtilities:(id)sender
{
  [[self currentViewer] goUtilities];
}

- (void)showHistory:(id)sender
{
  [history activate];
}

- (void)showInspector:(id)sender
{
  [inspector activate];
  [inspector setCurrentSelection: selectedPaths];
}

- (void)showAttributesInspector:(id)sender
{
  [self showInspector: nil]; 
  [inspector showAttributes];
}

- (void)showContentsInspector:(id)sender
{
  [self showInspector: nil];  
  [inspector showContents];
}

- (void)showToolsInspector:(id)sender
{
  [self showInspector: nil]; 
  [inspector showTools];
}

- (void)showAnnotationsInspector:(id)sender
{
  [self showInspector: nil]; 
  [inspector showAnnotations];
}

- (void)showRecycler:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  id item;

  if (recyclerApp == nil)
    {
      recyclerCanQuit = NO; 
      [self connectRecycler];
      item = [menu itemWithTitle: NSLocalizedString(@"Show Recycler", @"")];
      [item setTitle: NSLocalizedString(@"Hide Recycler", @"")];
    }
  else
    {
      recyclerCanQuit = YES;
      [recyclerApp terminateApplication];
      item = [menu itemWithTitle: NSLocalizedString(@"Hide Recycler", @"")];
      [item setTitle: NSLocalizedString(@"Show Recycler", @"")];
    }
}

- (void)showFinder:(id)sender
{
  [finder activate];   
}

- (void)showFiend:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Fiend", @"")] submenu];

  while (1)
    {
      if ([menu numberOfItems] == 0)
        break;

      [menu removeItemAtIndex: 0];
    }

  [menu addItemWithTitle: NSLocalizedString(@"Hide Fiend", @"")
                  action: @selector(hideFiend:) keyEquivalent: @""];
  [menu addItemWithTitle: NSLocalizedString(@"Remove Current Layer", @"")
                  action: @selector(removeFiendLayer:) keyEquivalent: @""];
  [menu addItemWithTitle: NSLocalizedString(@"Rename Current Layer", @"")
                  action: @selector(renameFiendLayer:) keyEquivalent: @""];	
  [menu addItemWithTitle: NSLocalizedString(@"Add Layer...", @"")
                  action: @selector(addFiendLayer:) keyEquivalent: @""];

  [fiend activate];
}

- (void)hideFiend:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Fiend", @"")] submenu];

  while (1)
    {
      if ([menu numberOfItems] == 0)
	{
	  break;
	}
      [menu removeItemAtIndex: 0];
    }

  [menu addItemWithTitle: NSLocalizedString(@"Show Fiend", @"")
		  action: @selector(showFiend:) keyEquivalent: @""];

  if (fiend != nil)
    {
      [fiend hide];
    }
}

- (void)addFiendLayer:(id)sender
{
  [fiend addLayer];
}

- (void)removeFiendLayer:(id)sender
{
  [fiend removeCurrentLayer];
}

- (void)renameFiendLayer:(id)sender
{
  [fiend renameCurrentLayer];
}

- (void)cut:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin && [vwrsManager hasViewerWithWindow: kwin])
    {
      id nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
      NSArray *selection = [nodeView selectedPaths];
      NSArray *basesel = [NSArray arrayWithObject: [[nodeView baseNode] path]];

      if ([selection count] && ([selection isEqual: basesel] == NO))
        {
          NSPasteboard *pb = [NSPasteboard generalPasteboard];
          [pb declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType] owner: nil];
          if ([pb setPropertyList: selection forType: NSFilenamesPboardType])
            {
              [fileOpsManager setFilenamesCut: YES];
            }
        }
    }
}

- (void)copy:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin && [vwrsManager hasViewerWithWindow: kwin])
    {
      id nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
      NSArray *selection = [nodeView selectedPaths];
      NSArray *basesel = [NSArray arrayWithObject: [[nodeView baseNode] path]];

      if ([selection count] && ([selection isEqual: basesel] == NO))
        {
          NSPasteboard *pb = [NSPasteboard generalPasteboard];
          [pb declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType] owner: nil];
          if ([pb setPropertyList: selection forType: NSFilenamesPboardType])
            {
              [fileOpsManager setFilenamesCut: NO];
            }
        }
    }
}

- (void)paste:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin && [vwrsManager hasViewerWithWindow: kwin])
    {
      NSPasteboard *pb = [NSPasteboard generalPasteboard];

      if ([[pb types] containsObject: NSFilenamesPboardType])
        {
          NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType];

          if (sourcePaths)
            {
              BOOL cut = [fileOpsManager filenamesWasCut];
              id nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];

              if ([nodeView validatePasteOfFilenames: sourcePaths wasCut: cut])
                {
                  NSMutableDictionary *opDict = [NSMutableDictionary dictionary];
                  NSString *source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
                  NSString *destination = [[nodeView shownNode] path];
                  NSMutableArray *files = [NSMutableArray array];
                  NSString *operation;
                  int i;

                  for (i = 0; i < [sourcePaths count]; i++)
                    {
                      [files addObject: [[sourcePaths objectAtIndex: i] lastPathComponent]];
                    }

                  if (cut)
                    {
                      operation = [source isEqual: trashPath]
                        ? @"GFinderRecycleOutOperation"
                        : NSWorkspaceMoveOperation;
                    }
                  else
                    {
                      operation = NSWorkspaceCopyOperation;
                    }

                  [opDict setObject: operation forKey: @"operation"];
                  [opDict setObject: source forKey: @"source"];
                  [opDict setObject: destination forKey: @"destination"];
                  [opDict setObject: files forKey: @"files"];

                  [self performFileOperation: opDict];
                }
            }
        }
    }
}

- (void)runCommand:(id)sender
{
  [runExtController activate];
}

- (void)checkRemovableMedia:(id)sender
{
}

- (void)emptyRecycler:(id)sender
{
@autoreleasepool {
  FSNode *node = [FSNode nodeWithPath: trashPath];
  NSMutableArray *subNodes = [[node subNodes] mutableCopy];
  int count = [subNodes count];
  NSUInteger i;  
  
  for (i = 0; i < count; i++)
    {
      FSNode *nd = [subNodes objectAtIndex: i];

      if ([nd isReserved])
	{
	  [subNodes removeObjectAtIndex: i];
	  i--;
	  count --;
	}
    }
  
  if ([subNodes count])
    {
      NSMutableArray *files = [NSMutableArray array];
      NSMutableDictionary *opinfo = [NSMutableDictionary dictionary];

      for (i = 0; i < [subNodes count]; i++)
	{
	  [files addObject: [[(FSNode *)[subNodes objectAtIndex: i] path] lastPathComponent]];
	}

      [opinfo setObject: @"GFinderEmptyRecyclerOperation" forKey: @"operation"];
      [opinfo setObject: trashPath forKey: @"source"];
      [opinfo setObject: trashPath forKey: @"destination"];
      [opinfo setObject: files forKey: @"files"];

      [self performFileOperation: opinfo];
    }

  RELEASE (subNodes);
  } // @autoreleasepool
}


//
// DesktopApplication protocol
//
- (void)selectionChanged:(NSArray *)newsel
{
  if (newsel && [newsel count] && ([vwrsManager orderingViewers] == NO)) {
    [self setSelectedPaths: [FSNode pathsOfNodes: newsel]];
  }
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  if (selectedPaths && [selectedPaths count]) {
    [self openSelectedPaths: selectedPaths newViewer: newv];
  }  
}

- (void)openSelectionWithApp:(id)sender
{
  NSString *appName = (NSString *)[(NSMenuItem *)sender representedObject];
  NSUInteger count = (selectedPaths ? [selectedPaths count] : 0);
  
  if (count) {
    NSUInteger i;

    if (count > MAX_FILES_TO_OPEN_DIALOG) {
      NSString *msg1 = NSLocalizedString(@"Are you sure you want to open", @"");
      NSString *msg2 = NSLocalizedString(@"items?", @"");

      if (NSRunAlertPanel(nil,
                          [NSString stringWithFormat: @"%@ %lu %@", msg1, (unsigned long)count, msg2],
                  NSLocalizedString(@"Cancel", @""),
                  NSLocalizedString(@"Yes", @""),
                  nil)) {
        return;
      }
    }

    for (i = 0; i < count; i++) {
      NSString *path = [selectedPaths objectAtIndex: i];
    
      NS_DURING
        {
      [ws openFile: path withApplication: appName];
        }
      NS_HANDLER
        {
      NSRunAlertPanel(NSLocalizedString(@"error", @""), 
          [NSString stringWithFormat: @"%@ %@!", 
              NSLocalizedString(@"Can't open ", @""), [path lastPathComponent]],
                                        NSLocalizedString(@"OK", @""), 
                                        nil, 
                                        nil);                                     
        }
      NS_ENDHANDLER  
    }
  }
}

- (void)performFileOperation:(NSDictionary *)opinfo
{
  NSString *operation = [opinfo objectForKey: @"operation"];
  NSString *source = [opinfo objectForKey: @"source"];
  NSString *destination = [opinfo objectForKey: @"destination"];
  NSArray *files = [opinfo objectForKey: @"files"];
  NSInteger tag;

  if (destination == nil && [operation isEqualToString:NSWorkspaceRecycleOperation])
    destination = [self trashPath];

  [self performFileOperation: operation source: source 
		 destination: destination files: files tag: &tag];
}

- (BOOL)filenamesWasCut
{
  return [fileOpsManager filenamesWasCut];
}

- (void)setFilenamesCut:(BOOL)value
{
  [fileOpsManager setFilenamesCut: value];
}

- (void)lsfolderDragOperation:(NSData *)opinfo
              concludedAtPath:(NSString *)path
{
  [finder lsfolderDragOperation: opinfo concludedAtPath: path];
}     
                          
- (void)concludeRemoteFilesDragOperation:(NSData *)opinfo
                             atLocalPath:(NSString *)localPath
{
  NSDictionary *infoDict = [NSUnarchiver unarchiveObjectWithData: opinfo];
  NSArray *srcPaths = [infoDict objectForKey: @"paths"];
  BOOL bookmark = [[infoDict objectForKey: @"bookmark"] boolValue];
  NSString *connName = [infoDict objectForKey: @"dndconn"];
  NSArray *locContents = [fm directoryContentsAtPath: localPath];
  BOOL samename = NO;
  int i;

  if (locContents) {
    NSConnection *conn;
    id remote;
  
    for (i = 0; i < [srcPaths count]; i++) {
      NSString *name = [[srcPaths objectAtIndex: i] lastPathComponent];

      if ([locContents containsObject: name]) {
        samename = YES;
        break;
      }
    }
    
    conn = [NSConnection connectionWithRegisteredName: connName host: @""];
  
    if (conn) {
      remote = [conn rootProxy];
      
      if (remote) {
        NSMutableDictionary *reply = [NSMutableDictionary dictionary];
        NSData *rpdata;
      
        [reply setObject: localPath forKey: @"destination"];
        [reply setObject: srcPaths forKey: @"paths"];
        [reply setObject: [NSNumber numberWithBool: bookmark] forKey: @"bookmark"];  
        [reply setObject: [NSNumber numberWithBool: !samename] forKey: @"dndok"];
        rpdata = [NSArchiver archivedDataWithRootObject: reply];
      
        [remote setProtocolForProxy: @protocol(GWRemoteFilesDraggingInfo)];
        remote = (id <GWRemoteFilesDraggingInfo>)remote;
      
        [remote remoteDraggingDestinationReply: rpdata];
      }
    }
  }
}

- (void)addWatcherForPath:(NSString *)path
{
  [watchedPaths addObject: path];

  if (fswnotifications) {
    [self connectFSWatcher];
    [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
  }
}

- (void)removeWatcherForPath:(NSString *)path
{
  [watchedPaths removeObject: path];

  if (fswnotifications) {
    [self connectFSWatcher];
    [fswatcher client: (id <FSWClientProtocol>)self removeWatcherForPath: path];
  }
}

- (NSString *)trashPath
{
  static NSString *tpath = nil;
  
  if (tpath == nil) {
    tpath = [NSHomeDirectory() stringByAppendingPathComponent: @".Trash"]; 
  }
  
  return tpath;
}

- (id)workspaceApplication
{
  return [GFinder gfinder];
}

- (oneway void)terminateApplication
{
  [NSApp terminate: self];
}

- (BOOL)terminating
{
  return terminating;
}

@end


@implementation GFinder (SharedInspector)

- (oneway void)showExternalSelection:(NSArray *)selection
{
  if ([[inspector win] isVisible] == NO) {
    [self showContentsInspector: nil];    
  }  
  
  if (selection) {
    [inspector setCurrentSelection: selection];
  } else {
    [self resetSelectedPaths];
  }
}

@end


@implementation	GFinder (PrivateMethods)

- (void)_updateTrashContents
{
  FSNode *node = [FSNode nodeWithPath: trashPath];

  [trashContents removeAllObjects];

  if (node && [node isValid]) {
    NSArray *subNodes = [node subNodes];
    NSUInteger i;

    for (i = 0; i < [subNodes count]; i++) {
      FSNode *subnode = [subNodes objectAtIndex: i];

      if ([subnode isReserved] == NO) {
	[trashContents addObject: subnode];
      }
    }
  }
}

@end

