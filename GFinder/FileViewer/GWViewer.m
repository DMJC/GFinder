/* GWViewer.m
 *  
 * Copyright (C) 2004-2015 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola
 * Date: July 2004
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

#include <math.h>

#import <AppKit/AppKit.h>
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "GWViewerBrowser.h"
#import "GWViewerIconsView.h"
#import "GWViewerListView.h"
#import "GWViewerWindow.h"
#import "GWViewerScrollView.h"
#import "GWViewerSplit.h"
#import "GWViewerShelf.h"
#import "GFinder.h"
#import "GWFunctions.h"
#import "FSNBrowser.h"
#import "FSNIconsView.h"
#import "FSNodeRep.h"
#import "FSNIcon.h"
#import "FSNFunctions.h"
#import "Thumbnailer/GWThumbnailer.h"

#define DEFAULT_INCR 150
#define MIN_WIN_H 300

#define MIN_SHELF_HEIGHT 2.0
#define MID_SHELF_HEIGHT 77.0
#define MAX_SHELF_HEIGHT 150.0
#define COLLAPSE_LIMIT 35
#define MID_LIMIT 110


@implementation GWViewer

- (void)dealloc
{
  [nc removeObserver: self];

  RELEASE (baseNode);
  RELEASE (baseNodeArray);
  RELEASE (lastSelection);
  RELEASE (defaultsKeyStr);
  RELEASE (watchedNodes);
  RELEASE (vwrwin);
  RELEASE (viewerPrefs);
  RELEASE (history);
  RELEASE (folderNameField);
  
  [super dealloc];
}

- (id)initForNode:(FSNode *)node
         inWindow:(GWViewerWindow *)win
         showType:(GWViewType)stype
    showSelection:(BOOL)showsel
	  withKey:(NSString *)key
{
  self = [super init];
  
  if (self) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
    NSString *prefsname;
    id defEntry;
    NSRect r;
    NSString *viewTypeStr;
        
    ASSIGN (baseNode, [FSNode nodeWithPath: [node path]]);
    ASSIGN (baseNodeArray, [NSArray arrayWithObject: baseNode]);
    fsnodeRep = [FSNodeRep sharedInstance];
    lastSelection = nil;
    history = [NSMutableArray new];
    historyPosition = 0;
    watchedNodes = [NSMutableArray new];
    manager = [GWViewersManager viewersManager];
    gfinder = [GFinder gfinder];
    nc = [NSNotificationCenter defaultCenter];
    
    defEntry = [defaults objectForKey: @"browserColsWidth"];
    if (defEntry) {
      resizeIncrement = [defEntry intValue];
    } else {
      resizeIncrement = DEFAULT_INCR;
    }
    
    rootViewer = [[baseNode path] isEqual: path_separator()];
    firstRootViewer = (rootViewer && ([[manager viewersForBaseNode: baseNode] count] == 0));
    
    if (rootViewer == YES)
      {
	if (firstRootViewer)
	  {
	    prefsname = @"root_viewer";
	  }
	else
	  {
	    if (key == nil)
	      {
		NSNumber *rootViewerKey;

		rootViewerKey = [NSNumber numberWithUnsignedLong: (unsigned long)self];

		prefsname = [NSString stringWithFormat: @"%lu_viewer_at_%@", [rootViewerKey unsignedLongValue], [node path]];
	      }
	    else
	      {
		prefsname = [key retain];
	      }
	  }
      }
    else
      {
	prefsname = [NSString stringWithFormat: @"viewer_at_%@", [node path]];
      }

    defaultsKeyStr = [prefsname retain];
    if ([baseNode isWritable] && (rootViewer == NO)
            && ([[fsnodeRep volumes] containsObject: [baseNode path]] == NO)) {
		  NSString *dictPath = [[baseNode path] stringByAppendingPathComponent: @".gwdir"];

      if ([[NSFileManager defaultManager] fileExistsAtPath: dictPath]) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile: dictPath];

        if (dict) {
          viewerPrefs = [dict copy];
        }   
      }
    }
    
    if (viewerPrefs == nil) {
      defEntry = [defaults dictionaryForKey: defaultsKeyStr];
      if (defEntry) {
        viewerPrefs = [defEntry copy];
      } else {
        viewerPrefs = [NSDictionary new];
      }
    }
    
    viewType = GWViewTypeIcon;
    viewTypeStr = [viewerPrefs objectForKey: @"viewtype"];
    if (viewTypeStr == nil)
      {
        if (stype != 0)
          {
            viewType = stype;
          }
      }
    else if ([viewTypeStr isEqual: @"Browser"])
      {
        viewType = GWViewTypeBrowser;
      }
    else if ([viewTypeStr isEqual: @"List"])
      {
        viewType = GWViewTypeList;
      }
    else if ([viewTypeStr isEqual: @"Icon"])
      {
        viewType = GWViewTypeIcon;
      }
    
    defEntry = [viewerPrefs objectForKey: @"shelfheight"];
    if (defEntry) {
      shelfHeight = [defEntry floatValue];
    } else {
      shelfHeight = MID_SHELF_HEIGHT;
    }
       
    ASSIGN (vwrwin, win);
    [vwrwin setDelegate: self];

    defEntry = [viewerPrefs objectForKey: @"geometry"];
    if (defEntry) {
      [vwrwin setFrameFromString: defEntry];
    } else {
      r = NSMakeRect(200, 200, resizeIncrement * 3, 350);
      [vwrwin setFrame: rectForWindow([manager viewerWindows], r, YES) 
               display: NO];
    }
    
    r = [vwrwin frame];
    
    if (r.size.height < MIN_WIN_H) {
      r.origin.y -= (MIN_WIN_H - r.size.height);
      r.size.height = MIN_WIN_H;
    
      if (r.origin.y < 0) {
        r.origin.y = 5;
      }
      
      [vwrwin setFrame: r display: NO];
    }

    [vwrwin setMinSize: NSMakeSize(resizeIncrement * 2, MIN_WIN_H)];    
    [vwrwin setResizeIncrements: NSMakeSize(resizeIncrement, 1)];

    if (firstRootViewer) {
      [vwrwin setTitle: NSLocalizedString(@"File Viewer", @"")];
    } else {
      if (rootViewer) {
        [vwrwin setTitle: [NSString stringWithFormat: @"%@ - %@", [node name], [node parentPath]]];
      } else {
        [vwrwin setTitle: [NSString stringWithFormat: @"%@", [node name]]];
      }
    }

    [self createSubviews];

    defEntry = [viewerPrefs objectForKey: @"shelfdicts"];

    if (defEntry && [defEntry count]) {
      [shelf setContents: defEntry];
    } else if (rootViewer) {
      NSMutableArray *sfdicts = [NSMutableArray array];
      NSMutableArray *paths = [NSMutableArray arrayWithObjects:
                        NSHomeDirectory(),
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Desktop"],
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Documents"],
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Downloads"],
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Pictures"],
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Music"],
                        [NSHomeDirectory() stringByAppendingPathComponent: @"Videos"],
                        @"/",
                        @"/media",
                        nil];
      NSArray *appdirs = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSAllDomainsMask, YES);
      if ([appdirs count]) {
        [paths addObject: [appdirs objectAtIndex: 0]];
      }
      NSInteger i;
      for (i = 0; i < [paths count]; i++) {
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithInteger: i], @"index",
                        [NSArray arrayWithObject: [paths objectAtIndex: i]], @"paths",
                        nil];
        [sfdicts addObject: dict];
      }
      [shelf setContents: sfdicts];
    }

    if (viewType == GWViewTypeIcon) {
	      nodeView = [[GWViewerIconsView alloc] initForViewer: self];

    } else if (viewType == GWViewTypeList) {
      NSRect r = [[nviewScroll contentView] bounds];
      
      nodeView = [[GWViewerListView alloc] initWithFrame: r forViewer: self];

    } else if (viewType == GWViewTypeBrowser ) {
      nodeView = [[GWViewerBrowser alloc] initWithBaseNode: baseNode
                                      inViewer: self
		                            visibleColumns: visibleCols
                                      scroller: [nviewScroll horizontalScroller]
                                    cellsIcons: NO
                                 editableCells: NO
                               selectionColumn: YES];
    }

    [nviewScroll setDocumentView: nodeView];
    RELEASE (nodeView);
    [nodeView showContentsOfNode: baseNode];
    if (showsel) {
      defEntry = [viewerPrefs objectForKey: @"lastselection"];
    
      if (defEntry) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *selection = [defEntry mutableCopy];
        int count = [selection count];
        int i;

        for (i = 0; i < count; i++) {
          NSString *s = [selection objectAtIndex: i];

          if ([fm fileExistsAtPath: s] == NO) {
            [selection removeObject: s];
            count--;
            i--;
          }
        }

        if ([selection count]) {
          if ([nodeView isSingleNode]) {
            NSString *base = [selection objectAtIndex: 0];
            FSNode *basenode = [FSNode nodeWithPath: base];
          
            if (([basenode isDirectory] == NO) || [basenode isPackage]) {
              base = [base stringByDeletingLastPathComponent];
              basenode = [FSNode nodeWithPath: base];
            }
            
            [nodeView showContentsOfNode: basenode];
            [self updeateInfoLabels];
            [nodeView selectRepsOfPaths: selection];
          
          } else {
            [nodeView selectRepsOfPaths: selection];
          }
        }

        RELEASE (selection);
      }
    }
        
    [nc addObserver: self 
           selector: @selector(columnsWidthChanged:) 
               name: @"GWBrowserColumnWidthChangedNotification"
             object: nil];

    invalidated = NO;
    closing = NO;    
  }
  
  return self;
}

- (void)createSubviews
{
  NSRect r = [[vwrwin contentView] bounds];
  CGFloat w = r.size.width;
  CGFloat h = r.size.height;
  CGFloat d = 0.0;
  int xmargin = 8;
  int ymargin = 6;
  NSUInteger resizeMask;

  split = [[GWViewerSplit alloc] initWithFrame: r];
  [split setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  [split setDelegate: self];
  [split setVertical: YES];
  d = [split dividerThickness];

  r = NSMakeRect(0, 0, shelfHeight, h);
  shelf = [[GWViewerShelf alloc] initWithFrame: r forViewer: self];
  [split addSubview: shelf];
  RELEASE (shelf);
  
  r = NSMakeRect(shelfHeight + d, 0, w - shelfHeight - d, h);
  lowBox = [[NSView alloc] initWithFrame: r];
  resizeMask = NSViewWidthSizable | NSViewHeightSizable;
  [lowBox setAutoresizingMask: resizeMask];
  [lowBox setAutoresizesSubviews: YES];
  [split addSubview: lowBox];
  RELEASE (lowBox);

  r = [lowBox bounds];
  w = r.size.width;
  h = r.size.height;
  visibleCols = myrintf(w / [vwrwin resizeIncrements].width);
  {
    CGFloat buttonHeight = 25;
    NSTextField *folderLabel;
    CGFloat labelWidth = w - (xmargin * 2);

    folderLabel = [[NSTextField alloc] initWithFrame:
      NSMakeRect(xmargin, h - buttonHeight - ymargin,
                 labelWidth, buttonHeight)];
    [folderLabel setBezeled: NO];
    [folderLabel setDrawsBackground: NO];
    [folderLabel setEditable: NO];
    [folderLabel setSelectable: NO];
    [folderLabel setAutoresizingMask: (NSViewWidthSizable | NSViewMinYMargin)];
    [folderLabel setStringValue: [[nodeView shownNode] name]];
    [lowBox addSubview: folderLabel];
    ASSIGN (folderNameField, folderLabel);
    RELEASE (folderLabel);

    r = NSMakeRect(xmargin, ymargin + buttonHeight,
                   w - (xmargin * 2),
                   h - (ymargin * 3) - (buttonHeight*2));
    nviewScroll = [[GWViewerScrollView alloc] initWithFrame: r inViewer: self];
    [nviewScroll setBorderType: NSBezelBorder];
    [nviewScroll setHasHorizontalScroller: YES];
    [nviewScroll setHasVerticalScroller: (viewType != GWViewTypeBrowser)];
    resizeMask = NSViewNotSizable | NSViewWidthSizable | NSViewHeightSizable;
    [nviewScroll setAutoresizingMask: resizeMask];
    [lowBox addSubview: nviewScroll];
    RELEASE (nviewScroll);
  }
  [vwrwin setContentView: split];
  RELEASE (split);
  [self setupToolbar];
  [self updateViewButtonsState];
}

- (void)setupToolbar
{
  NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier: @"GWViewerToolbar"];
  [tb setAllowsUserCustomization: NO];
  [tb setAutosavesConfiguration: NO];
  [tb setDisplayMode: NSToolbarDisplayModeIconOnly];
  [tb setDelegate: self];

  NSButton *button;
  NSToolbarItem *item;

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 30, 25)];
  [button setTitle: @"<"];
  [button setTarget: vwrwin];
  [button setAction: @selector(goBackwardInHistory:)];
  [button setButtonType: NSMomentaryPushInButton];
  item = [[NSToolbarItem alloc] initWithItemIdentifier: @"BackItem"];
  [item setLabel: @"Back"];
  [item setView: button];
  [item setMinSize: NSMakeSize(30, 25)];
  [item setMaxSize: NSMakeSize(30, 25)];
  ASSIGN (backItem, item);
  RELEASE (item);
  RELEASE (button);

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 30, 25)];
  [button setTitle: @">"];
  [button setTarget: vwrwin];
  [button setAction: @selector(goForwardInHistory:)];
  [button setButtonType: NSMomentaryPushInButton];
  item = [[NSToolbarItem alloc] initWithItemIdentifier: @"ForwardItem"];
  [item setLabel: @"Forward"];
  [item setView: button];
  [item setMinSize: NSMakeSize(30, 25)];
  [item setMaxSize: NSMakeSize(30, 25)];
  ASSIGN (forwardItem, item);
  RELEASE (item);
  RELEASE (button);

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 40, 25)];
  [button setButtonType: NSOnOffButton];
  [button setImage: [NSImage imageNamed: @"IconView.tiff"]];
  [button setTarget: self];
  [button setAction: @selector(setViewerType:)];
  [button setTag: GWViewTypeIcon];
  item = [[NSToolbarItem alloc] initWithItemIdentifier: @"IconItem"];
  [item setLabel: @"Icon"];
  [item setView: button];
  [item setMinSize: NSMakeSize(40, 25)];
  [item setMaxSize: NSMakeSize(40, 25)];
  ASSIGN (iconItem, item);
  ASSIGN (iconButton, button);
  RELEASE (item);
  RELEASE (button);

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 40, 25)];
  [button setButtonType: NSOnOffButton];
  [button setImage: [NSImage imageNamed: @"ListView.tiff"]];
  [button setTarget: self];
  [button setAction: @selector(setViewerType:)];
  [button setTag: GWViewTypeList];
  item = [[NSToolbarItem alloc] initWithItemIdentifier: @"ListItem"];
  [item setLabel: @"List"];
  [item setView: button];
  [item setMinSize: NSMakeSize(40, 25)];
  [item setMaxSize: NSMakeSize(40, 25)];
  ASSIGN (listItem, item);
  ASSIGN (listButton, button);
  RELEASE (item);
  RELEASE (button);

  button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 40, 25)];
  [button setButtonType: NSOnOffButton];
  [button setImage: [NSImage imageNamed: @"BrowserView.tiff"]];
  [button setTarget: self];
  [button setAction: @selector(setViewerType:)];
  [button setTag: GWViewTypeBrowser];
  item = [[NSToolbarItem alloc] initWithItemIdentifier: @"BrowserItem"];
  [item setLabel: @"Browser"];
  [item setView: button];
  [item setMinSize: NSMakeSize(40, 25)];
  [item setMaxSize: NSMakeSize(40, 25)];
  ASSIGN (browserItem, item);
  ASSIGN (browserButton, button);
  RELEASE (item);
  RELEASE (button);

  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:
    NSMakeRect(0, 0, 30, 25)
                                pullsDown: YES];
  [popup addItemWithTitle: @""];
  [[popup itemAtIndex: 0] setImage:
    [NSImage imageNamed: @"Sort_Options.tiff"]];
  NSArray *sortOptions = [NSArray arrayWithObjects:
    @"Name", @"Date Modified", @"Size", @"Type", nil];
  NSUInteger i;
  for (i = 0; i < [sortOptions count]; i++)
    {
      [[popup menu] addItemWithTitle: [sortOptions objectAtIndex: i]
                               action: NULL
                        keyEquivalent: @""];
    }
  item = [[NSToolbarItem alloc] initWithItemIdentifier: @"SortItem"];
  [item setLabel: @"Sort"];
  [item setView: popup];
  [item setMinSize: NSMakeSize(30, 25)];
  [item setMaxSize: NSMakeSize(30, 25)];
  ASSIGN (sortItem, item);
  ASSIGN (sortButton, popup);
  RELEASE (item);
  RELEASE (popup);

  ASSIGN (toolbar, tb);
  [tb insertItemWithItemIdentifier: @"BackItem" atIndex: 0];
  [tb insertItemWithItemIdentifier: @"ForwardItem" atIndex: 1];
  [tb insertItemWithItemIdentifier: @"IconItem" atIndex: 2];
  [tb insertItemWithItemIdentifier: @"ListItem" atIndex: 3];
  [tb insertItemWithItemIdentifier: @"BrowserItem" atIndex: 4];
  [tb insertItemWithItemIdentifier: @"SortItem" atIndex: 5];
  [vwrwin setToolbar: tb];
  RELEASE (tb);
}

- (void)updateViewButtonsState
{
  if (iconButton && listButton && browserButton)
    {
      [iconButton setState: (viewType == GWViewTypeIcon)];
      [listButton setState: (viewType == GWViewTypeList)];
      [browserButton setState: (viewType == GWViewTypeBrowser)];
    }
}

- (NSToolbarItem *)toolbar:(NSToolbar *)tb
    itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
  if ([itemIdentifier isEqual: @"BackItem"])
    return backItem;
  if ([itemIdentifier isEqual: @"ForwardItem"])
    return forwardItem;
  if ([itemIdentifier isEqual: @"IconItem"])
    return iconItem;
  if ([itemIdentifier isEqual: @"ListItem"])
    return listItem;
  if ([itemIdentifier isEqual: @"BrowserItem"])
    return browserItem;
  if ([itemIdentifier isEqual: @"SortItem"])
    return sortItem;
  return nil;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb
{
  return [NSArray arrayWithObjects:
                     @"BackItem",
                     @"ForwardItem",
                     @"IconItem",
                     @"ListItem",
                     @"BrowserItem",
                     @"SortItem", nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb
{
  return [self toolbarDefaultItemIdentifiers: tb];
}

- (void)updateFolderNameLabel
{
  if (folderNameField)
    {
      FSNode *shown = [nodeView shownNode];
      [folderNameField setStringValue: shown ? [shown name] : @""];
    }
}

- (FSNode *)baseNode
{
  return baseNode;
}

- (BOOL)isShowingNode:(FSNode *)anode
{
  NSArray *comps = [FSNode nodeComponentsFromNode: baseNode 
                                           toNode: [nodeView shownNode]];
  return [comps containsObject: anode];
}

- (BOOL)isShowingPath:(NSString *)apath
{
  FSNode *node = [FSNode nodeWithPath: apath];
  return [self isShowingNode: node];
}

- (void)reloadNodeContents
{
  [nodeView reloadContents];
}

- (void)reloadFromNode:(FSNode *)anode
{
  [nodeView reloadFromNode: anode];
  [self updeateInfoLabels];
}

- (void)unloadFromNode:(FSNode *)anode
{
  if ([baseNode isEqual: anode] || [baseNode isSubnodeOfNode: anode]) {
    [self deactivate];
  } else {
    [nodeView unloadFromNode: anode];
  }
}

- (void)updateShownSelection
{

}

- (GWViewerWindow *)win
{
  return vwrwin;
}

- (id)nodeView
{
  return nodeView;
}

- (id)shelf
{
  return shelf;
}

- (GWViewType)viewType
{
  return viewType;
}

- (BOOL)isFirstRootViewer
{
  return firstRootViewer;
}

- (NSString *)defaultsKey
{
  return defaultsKeyStr;
}

- (void)activate
{
  [vwrwin makeKeyAndOrderFront: nil];
  [self tileViews];
  [self scrollToBeginning];    
}

- (void)deactivate
{
  [vwrwin close];
}

- (void)tileViews
{
  NSRect r = [split bounds];
  CGFloat w = r.size.width;
  CGFloat h = r.size.height;
  CGFloat d = [split dividerThickness];

  [shelf setFrame: NSMakeRect(0, 0, shelfHeight, h)];
  [lowBox setFrame: NSMakeRect(shelfHeight + d, 0, w - shelfHeight - d, h)];
}

- (void)scrollToBeginning
{
  if ([nodeView isSingleNode]) {
    [nodeView scrollSelectionToVisible];
  }
}

- (void)invalidate
{
  invalidated = YES;
}

- (BOOL)invalidated
{
  return invalidated;
}

- (BOOL)isClosing
{
  return closing;
}

- (void)setOpened:(BOOL)opened
        repOfNode:(FSNode *)anode
{
  id rep = [nodeView repOfSubnode: anode];

  if (rep) {
    [rep setOpened: opened];

    if ([nodeView isSingleNode]) {
      [rep select];
    }
  }
}

- (void)unselectAllReps
{
  [nodeView unselectOtherReps: nil];
  [nodeView selectionDidChange];
}

- (void)selectionChanged:(NSArray *)newsel
{
  FSNode *node;
  NSArray *components;

  if (closing)
    return;

  [manager selectionChanged: newsel];

  if (lastSelection && [newsel isEqual: lastSelection]) {
    if ([[newsel objectAtIndex: 0] isEqual: [nodeView shownNode]] == NO) {
      return;
    }
  }

  ASSIGN (lastSelection, newsel);
  [self updeateInfoLabels]; 
    
  node = [newsel objectAtIndex: 0];   
     
  if (([node isDirectory] == NO) || [node isPackage] || ([newsel count] > 1)) {
    if ([node isEqual: baseNode] == NO) { // if baseNode is a package 
      node = [FSNode nodeWithPath: [node parentPath]];
    }
  }
    
  components = [FSNode nodeComponentsFromNode: baseNode toNode: node];

  if ([node isDirectory] && ([newsel count] == 1)) {
    if ([nodeView isSingleNode] && ([node isEqual: [nodeView shownNode]] == NO)) {
      node = [FSNode nodeWithPath: [node parentPath]];
      components = [FSNode nodeComponentsFromNode: baseNode toNode: node];
    }
  }

  if ([components isEqual: watchedNodes] == NO) {
    NSUInteger count = [components count];
    unsigned pos = 0;
    NSUInteger i;
  
    for (i = 0; i < [watchedNodes count]; i++) { 
      FSNode *nd = [watchedNodes objectAtIndex: i];
      
      if (i < count) {
        FSNode *ndcomp = [components objectAtIndex: i];

        if ([nd isEqual: ndcomp] == NO) {
          [gfinder removeWatcherForPath: [nd path]];
        } else {
          pos = i + 1;
        }

      } else {
        [gfinder removeWatcherForPath: [nd path]];
      }
    }

    for (i = pos; i < count; i++) {   
      [gfinder addWatcherForPath: [[components objectAtIndex: i] path]];
    }

    [watchedNodes removeAllObjects];
    [watchedNodes addObjectsFromArray: components];
  }  
  
  [manager addNode: node toHistoryOfViewer: self];
}

- (void)multipleNodeViewDidSelectSubNode:(FSNode *)node
{
}

- (void)shelfDidSelectIcon:(id)icon
{
  FSNode *node = [icon node];
  NSArray *selection = [icon selection];
  FSNode *nodetoshow;
  
  if (selection && ([selection count] > 1)) {
    nodetoshow = [FSNode nodeWithPath: [node parentPath]];
  } else {
    if ([node isDirectory] && ([node isPackage] == NO)) {
      nodetoshow = node;
      
      if (viewType != GWViewTypeBrowser) {
        selection = nil;
      } else {
        selection = [NSArray arrayWithObject: node];
      }
    
    } else {
      nodetoshow = [FSNode nodeWithPath: [node parentPath]];
      selection = [NSArray arrayWithObject: node];
    }
  }

  [nodeView showContentsOfNode: nodetoshow];
  
  if (selection) {
    [nodeView selectRepsOfSubnodes: selection];
  }

  if ([nodeView respondsToSelector: @selector(scrollSelectionToVisible)]) {
    [nodeView scrollSelectionToVisible];
  }
}

- (void)setSelectableNodesRange:(NSRange)range
{
  visibleCols = range.length;
}

- (void)updeateInfoLabels
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *attributes = [fm fileSystemAttributesAtPath: [[nodeView shownNode] path]];
  NSNumber *freefs = [attributes objectForKey: NSFileSystemFreeSize];
  NSString *labelstr;
  NSString *countstr;

  if (freefs == nil)
    {
      labelstr = NSLocalizedString(@"unknown volume size", @"");
    }
  else
    {
      unsigned long long freeSize = [freefs unsignedLongLongValue];
      NSUInteger systemType = [[NSProcessInfo processInfo] operatingSystem];

      switch (systemType)
	{
	case NSMACHOperatingSystem:
	  freeSize = (freeSize >> 8);
	  break;
	default:
	  break;
	}
      labelstr = [NSString stringWithFormat: @"%@ %@",
			   sizeDescription(freeSize),
			   NSLocalizedString(@"free", @"")];
    }
  NSArray *subNodes = [[nodeView shownNode] subNodes];
  NSUInteger count = 0;
  for (NSUInteger i = 0; i < [subNodes count]; i++) {
    FSNode *nd = [subNodes objectAtIndex: i];
    if ([nd isReserved] == NO) {
      count++;
    }
  }
  countstr = [NSString stringWithFormat: @"%lu %@", (unsigned long)count, NSLocalizedString(@"files", @"")];

  [split updateDiskSpaceInfo: labelstr];
  [split updateFileCountInfo: countstr];
}

- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo
{
  FSNode *lastNode = [nodeView shownNode];
  NSArray *comps = [FSNode nodeComponentsFromNode: baseNode toNode: lastNode];
  int i;    

  for (i = 0; i < [comps count]; i++) {
    if ([[comps objectAtIndex: i] involvedByFileOperation: opinfo]) {
      return YES;
    }
  }

  return NO;
}

- (void)nodeContentsWillChange:(NSDictionary *)info
{
  [nodeView nodeContentsWillChange: info];
}

- (void)nodeContentsDidChange:(NSDictionary *)info
{
  if ([nodeView isSingleNode]) {  
    NSString *operation = [info objectForKey: @"operation"];
    NSString *source = [info objectForKey: @"source"];
    NSString *destination = [info objectForKey: @"destination"];
  
    if ([operation isEqual: @"GFinderRenameOperation"]) {
      destination = [destination stringByDeletingLastPathComponent]; 
    }

    if ([operation isEqual: NSWorkspaceMoveOperation]
          || [operation isEqual: NSWorkspaceCopyOperation]
          || [operation isEqual: NSWorkspaceLinkOperation]
          || [operation isEqual: NSWorkspaceDuplicateOperation]
          || [operation isEqual: @"GFinderCreateDirOperation"]
          || [operation isEqual: @"GFinderCreateFileOperation"]
          || [operation isEqual: NSWorkspaceRecycleOperation]
          || [operation isEqual: @"GFinderRenameOperation"]
			    || [operation isEqual: @"GFinderRecycleOutOperation"]) { 
      [nodeView reloadFromNode: [FSNode nodeWithPath: destination]];
    }

    if ([operation isEqual: NSWorkspaceMoveOperation]
          || [operation isEqual: NSWorkspaceDestroyOperation]
				  || [operation isEqual: NSWorkspaceRecycleOperation]
				  || [operation isEqual: @"GFinderRecycleOutOperation"]
				  || [operation isEqual: @"GFinderEmptyRecyclerOperation"]) {
      [nodeView reloadFromNode: [FSNode nodeWithPath: source]];
    }
    
  } else {
    [nodeView nodeContentsDidChange: info];
  }
}

- (void)watchedPathChanged:(NSDictionary *)info
{
  if (invalidated == NO) {
    if ([nodeView isSingleNode]) {
      NSString *path = [info objectForKey: @"path"];
      NSString *event = [info objectForKey: @"event"];
  
      if ([event isEqual: @"GWWatchedPathDeleted"]) {
        NSString *s = [path stringByDeletingLastPathComponent];

        if ([self isShowingPath: s]) {
          FSNode *node = [FSNode nodeWithPath: s];
          [nodeView reloadFromNode: node];
        }

      } else if ([nodeView isShowingPath: path]) {
        [nodeView watchedPathChanged: info];
      }
  
    } else {
      [nodeView watchedPathChanged: info];
    }
  }
}

- (NSMutableArray *)history
{
  return history;
}

- (int)historyPosition
{
  return historyPosition;
}

- (void)setHistoryPosition:(int)pos
{
  historyPosition = pos;
}

- (NSArray *)watchedNodes
{
  return watchedNodes;
}

- (void)hideDotsFileChanged:(BOOL)hide
{
  [self reloadFromNode: baseNode];
  [shelf checkIconsAfterDotsFilesChange];
}

- (void)hiddenFilesChanged:(NSArray *)paths
{
  [self reloadFromNode: baseNode];
  [shelf checkIconsAfterHidingOfPaths: paths];
}

- (void)columnsWidthChanged:(NSNotification *)notification
{
  NSRect r = [vwrwin frame];
  NSRange range;

  RETAIN (nodeView);
  [nodeView removeFromSuperviewWithoutNeedingDisplay];
  [nviewScroll setDocumentView: nil];	

  resizeIncrement = [(NSNumber *)[notification object] intValue];
  r.size.width = (visibleCols * resizeIncrement);
  [vwrwin setFrame: r display: YES];
  [vwrwin setMinSize: NSMakeSize(resizeIncrement * 2, MIN_WIN_H)];
  [vwrwin setResizeIncrements: NSMakeSize(resizeIncrement, 1)];

  [nviewScroll setDocumentView: nodeView];
  RELEASE (nodeView);
  [nodeView resizeWithOldSuperviewSize: [nodeView bounds].size];

  [self windowDidResize: nil];
}

- (void)updateDefaults
{
  if ([baseNode isValid])
    {
      NSMutableDictionary *updatedprefs = [nodeView updateNodeInfo: NO];
      id defEntry;
      NSString *viewTypeStr;

      if (viewType == GWViewTypeIcon)
        viewTypeStr = @"Icon";
      else if (viewType == GWViewTypeList)
        viewTypeStr = @"List";
      else
        viewTypeStr = @"Browser";

    if (updatedprefs == nil) {
      updatedprefs = [NSMutableDictionary dictionary];
    }

    [updatedprefs setObject: [NSNumber numberWithBool: [nodeView isSingleNode]]
                     forKey: @"singlenode"];

    [updatedprefs setObject: viewTypeStr forKey: @"viewtype"];

    [updatedprefs setObject: [NSNumber numberWithFloat: shelfHeight]
                     forKey: @"shelfheight"];

    [updatedprefs setObject: [shelf contentsInfo]
                     forKey: @"shelfdicts"];

    defEntry = [nodeView selectedPaths];
    if (defEntry) {
      if ([defEntry count] == 0) {
        defEntry = [NSArray arrayWithObject: [[nodeView shownNode] path]];
      }
      [updatedprefs setObject: defEntry forKey: @"lastselection"];
    }
    
    [updatedprefs setObject: [vwrwin stringWithSavedFrame] 
                     forKey: @"geometry"];

    [baseNode checkWritable];

    if ([baseNode isWritable] && (rootViewer == NO)
              && ([[fsnodeRep volumes] containsObject: [baseNode path]] == NO)) {
      NSString *dictPath = [[baseNode path] stringByAppendingPathComponent: @".gwdir"];

      [updatedprefs writeToFile: dictPath atomically: YES];
    } else {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	    
      [defaults setObject: updatedprefs forKey: defaultsKeyStr];
    }
    
    ASSIGN (viewerPrefs, [updatedprefs makeImmutableCopyOnFail: NO]);
  }
}


//
// splitView delegate methods
//
- (void)splitView:(NSSplitView *)sender 
                      resizeSubviewsWithOldSize:(NSSize)oldSize
{
  [self tileViews];
}

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
	[self tileViews];
}

- (CGFloat)splitView:(NSSplitView *)sender
constrainSplitPosition:(CGFloat)proposedPosition 
         ofSubviewAt:(NSInteger)offset
{
  if (proposedPosition < COLLAPSE_LIMIT) {
    shelfHeight = MIN_SHELF_HEIGHT;
  } else if (proposedPosition <= MID_LIMIT) {  
    shelfHeight = MID_SHELF_HEIGHT;
  } else {
    shelfHeight = MAX_SHELF_HEIGHT;
  }
  
  return shelfHeight;
}

- (CGFloat)splitView:(NSSplitView *)sender 
constrainMaxCoordinate:(CGFloat)proposedMax 
         ofSubviewAt:(NSInteger)offset
{
  if (proposedMax >= MAX_SHELF_HEIGHT) {
    return MAX_SHELF_HEIGHT;
  }
  
  return proposedMax;
}

- (CGFloat)splitView:(NSSplitView *)sender 
constrainMinCoordinate:(CGFloat)proposedMin 
         ofSubviewAt:(NSInteger)offset
{
  if (proposedMin <= MIN_SHELF_HEIGHT) {
    return MIN_SHELF_HEIGHT;
  }
  
  return proposedMin;
}

@end


//
// GWViewerWindow Delegate Methods
//
@implementation GWViewer (GWViewerWindowDelegateMethods)

- (void)windowDidExpose:(NSNotification *)aNotification
{
  [self updeateInfoLabels];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
  NSArray *selection = [nodeView selectedNodes];

  [manager updateDesktop];
  if ([selection count] == 0)
    {
      selection = [NSArray arrayWithObject: [nodeView shownNode]];
    }
  [self selectionChanged: selection];
  
  [manager changeHistoryOwner: self];
}

- (void)windowDidResize:(NSNotification *)aNotification
{
  if (nodeView) {
    [nodeView stopRepNameEditing];

    if ([nodeView isSingleNode]) {
      NSRect r = [[vwrwin contentView] bounds];
      int cols = myrintf(r.size.width / [vwrwin resizeIncrements].width);

      if (cols != visibleCols) {
        [self setSelectableNodesRange: NSMakeRange(0, cols)];
      }
    }
  }
}

- (BOOL)windowShouldClose:(id)sender
{
  [manager updateDesktop];
	return YES;
}

- (void)windowWillClose:(NSNotification *)aNotification
{
  if (invalidated == NO) {
    closing = YES;
    [self updateDefaults];
    [vwrwin setDelegate: nil];
    [manager viewerWillClose: self]; 
  }
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
  NSImage *image = [fsnodeRep iconOfSize: 48 forNode: baseNode];

  [vwrwin setMiniwindowImage: image];
  [vwrwin setMiniwindowTitle: [baseNode name]];
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes]; 
    NSUInteger count = (selection ? [selection count] : 0);
    
    if (count) {
      NSMutableArray *dirs = [NSMutableArray array];
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
        FSNode *node = [selection objectAtIndex: i];

        NS_DURING
          {
        if ([node isDirectory]) {
          if ([node isPackage]) {    
            if ([node isApplication] == NO) {
              [gfinder openFile: [node path]];
            } else {
              [[NSWorkspace sharedWorkspace] launchApplication: [node path]];
            }
          } else {
            [dirs addObject: node];
          }
        } else if ([node isPlain]) {
          [gfinder openFile: [node path]];
        }      
          }
        NS_HANDLER
          {
            NSRunAlertPanel(NSLocalizedString(@"error", @""), 
                [NSString stringWithFormat: @"%@ %@!", 
                          NSLocalizedString(@"Can't open ", @""), [node name]],
                                              NSLocalizedString(@"OK", @""), 
                                              nil, 
                                              nil);                                     
          }
        NS_ENDHANDLER
      }

      if (([dirs count] == 1) && ([selection count] == 1)) {
        if (newv == NO) {
          if ([nodeView isSingleNode]) {
            [nodeView showContentsOfNode: [dirs objectAtIndex: 0]];
            [self scrollToBeginning];
          }
        } else {
          [manager openAsFolderSelectionInViewer: self];
        }
      }

    } else if (newv) {
      [manager openAsFolderSelectionInViewer: self];
    }
  
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't open a document that is in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)openSelectionAsFolder
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    [manager openAsFolderSelectionInViewer: self];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't do this in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)openSelectionWith
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    [manager openWithSelectionInViewer: self];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't do this in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)newFolder
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    [gfinder newObjectAtPath: [[nodeView shownNode] path] 
                    isDirectory: YES];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't create a new folder in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)newFile
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    [gfinder newObjectAtPath: [[nodeView shownNode] path] 
                    isDirectory: NO];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't create a new file in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)duplicateFiles
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes];

    if (selection && [selection count]) {
      if ([nodeView isSingleNode]) {
        [gfinder duplicateFiles];
      } else if ([selection isEqual: baseNodeArray] == NO) {
        [gfinder duplicateFiles];
      }
    }
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't duplicate files in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)recycleFiles
{
  if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes];

    if (selection && [selection count]) {
      if ([nodeView isSingleNode]) {
        [gfinder moveToTrash];
      } else if ([selection isEqual: baseNodeArray] == NO) {
        [gfinder moveToTrash];
      }
    }
  }
}

- (void)emptyTrash
{
  [gfinder emptyRecycler: nil];
}

- (void)deleteFiles
{
  NSArray *selection = [nodeView selectedNodes];

  if (selection && [selection count]) {
    if ([nodeView isSingleNode]) {
      [gfinder deleteFiles];
    } else if ([selection isEqual: baseNodeArray] == NO) {
      [gfinder deleteFiles];
    }
  }
}

- (void)goBackwardInHistory
{
  [manager goBackwardInHistoryOfViewer: self];
}

- (void)goForwardInHistory
{
  [manager goForwardInHistoryOfViewer: self];
}

- (void)setViewerType:(id)sender
{
  NSInteger tag;

  if ([sender isKindOfClass: [NSSegmentedControl class]])
    {
      NSInteger seg = [sender selectedSegment];
      switch (seg)
        {
          case 0:
            tag = GWViewTypeIcon;
            break;
          case 1:
            tag = GWViewTypeList;
            break;
          case 2:
            tag = GWViewTypeBrowser;
            break;
          default:
            tag = 0;
            break;
        }
    }
  else
    {
      tag = [sender tag];
    }

  if (tag > 0)
    {
      NSArray *selection = [nodeView selectedNodes];
      NSUInteger i;

      [nodeView updateNodeInfo: YES];
      if ([nodeView isSingleNode] && ([selection count] == 0))
        selection = [NSArray arrayWithObject: [nodeView shownNode]];

      RETAIN (selection);

      [nviewScroll setDocumentView: nil];

      if (tag == GWViewTypeBrowser)
        {
          [nviewScroll setHasVerticalScroller: NO];
          [nviewScroll setHasHorizontalScroller: YES];

          nodeView = [[GWViewerBrowser alloc] initWithBaseNode: baseNode
                                                      inViewer: self
                                                visibleColumns: visibleCols
                                                      scroller: [nviewScroll horizontalScroller]
                                                    cellsIcons: NO
                                                 editableCells: NO
                                               selectionColumn: YES];

          viewType = GWViewTypeBrowser;
        }
      else if (tag == GWViewTypeIcon)
        {
          NSScroller *scroller = RETAIN ([pathsScroll horizontalScroller]);

          [pathsScroll setHasHorizontalScroller: NO];
          [pathsScroll setHorizontalScroller: scroller]; 
          [pathsScroll setHasHorizontalScroller: YES];
          RELEASE (scroller);
      
          [pathsView setOwnsScroller: YES];
          [pathsScroll setDelegate: pathsView];

          [nviewScroll setHasVerticalScroller: YES];
          [nviewScroll setHasHorizontalScroller: YES];
   
          nodeView = [[GWViewerIconsView alloc] initForViewer: self];
      
          viewType = GWViewTypeIcon;     
        }
      else if (tag == GWViewTypeList)
        {
          NSRect r = [[nviewScroll contentView] bounds];

          [nviewScroll setHasVerticalScroller: YES];
          [nviewScroll setHasHorizontalScroller: YES];

          nodeView = [[GWViewerListView alloc] initWithFrame: r forViewer: self];

          viewType = GWViewTypeList;
        }

      [nviewScroll setDocumentView: nodeView];
      RELEASE (nodeView);
      [nodeView showContentsOfNode: baseNode];

      if ([selection count])
        {
          if ([nodeView isSingleNode])
            {
              FSNode *basend = [selection objectAtIndex: 0];
        
              if ([basend isEqual: baseNode] == NO)
                {
                  if (([selection count] > 1) || (([basend isDirectory] == NO) || ([basend isPackage])))
                    {
                      basend = [FSNode nodeWithPath: [basend parentPath]];
                    }
                }
              
              [nodeView showContentsOfNode: basend];
              [nodeView selectRepsOfSubnodes: selection];
              
            }
          else
            {
              [nodeView selectRepsOfSubnodes: selection];
            }
        }
      
      DESTROY (selection);
    
      [self scrollToBeginning];

      [vwrwin makeFirstResponder: nodeView]; 

      for (i = 0; i < [watchedNodes count]; i++)
        {  
          [gfinder removeWatcherForPath: [[watchedNodes objectAtIndex: i] path]];
        }
      [watchedNodes removeAllObjects];
      
      DESTROY (lastSelection);
      selection = [nodeView selectedNodes];
      
      if ([selection count] == 0)
        {
          selection = [NSArray arrayWithObject: [nodeView shownNode]];
        }
      
      [self selectionChanged: selection];
      
      [self updateDefaults];
      [self updateViewButtonsState];
    }
}

- (void)setShownType:(id)sender
{
  NSString *title = [sender title];
  FSNInfoType type = FSNInfoNameType;

  if ([title isEqual: NSLocalizedString(@"Name", @"")]) {
    type = FSNInfoNameType;
  } else if ([title isEqual: NSLocalizedString(@"Type", @"")]) {
    type = FSNInfoKindType;
  } else if ([title isEqual: NSLocalizedString(@"Size", @"")]) {
    type = FSNInfoSizeType;
  } else if ([title isEqual: NSLocalizedString(@"Modification date", @"")]) {
    type = FSNInfoDateType;
  } else if ([title isEqual: NSLocalizedString(@"Owner", @"")]) {
    type = FSNInfoOwnerType;
  } else {
    type = FSNInfoNameType;
  } 

  [(id <FSNodeRepContainer>)nodeView setShowType: type]; 
  [self scrollToBeginning]; 
  [nodeView updateNodeInfo: YES];
}

- (void)setExtendedShownType:(id)sender
{
  [(id <FSNodeRepContainer>)nodeView setExtendedShowType: [sender title]];  
  [self scrollToBeginning];
  [nodeView updateNodeInfo: YES];
}

- (void)setIconsSize:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setIconSize:)]) {
    [(id <FSNodeRepContainer>)nodeView setIconSize: [[sender title] intValue]];
    [self scrollToBeginning];
    [nodeView updateNodeInfo: YES];
  }
}

- (void)setIconsPosition:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setIconPosition:)]) {
    NSString *title = [sender title];
    
    if ([title isEqual: NSLocalizedString(@"Left", @"")]) {
      [(id <FSNodeRepContainer>)nodeView setIconPosition: NSImageLeft];
    } else {
      [(id <FSNodeRepContainer>)nodeView setIconPosition: NSImageAbove];
    }
    
    [self scrollToBeginning];
    [nodeView updateNodeInfo: YES];
  }
}

- (void)setLabelSize:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setLabelTextSize:)]) {
    [nodeView setLabelTextSize: [[sender title] intValue]];
    [self scrollToBeginning];
    [nodeView updateNodeInfo: YES];
  }
}

- (void)chooseLabelColor:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setTextColor:)]) {

  }
}

- (void)chooseBackColor:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setBackgroundColor:)]) {

  }
}

- (void)selectAllInViewer
{
  [nodeView selectAll];
}

- (void)showTerminal
{
  NSString *path;

  if ([nodeView isSingleNode])
    {
      path = [[nodeView shownNode] path];
    }
  else
    {
      NSArray *selection = [nodeView selectedNodes];

      if (selection)
	{
	  FSNode *node = [selection objectAtIndex: 0];

	  if ([selection count] > 1)
	    {
	      path = [node parentPath];
	    }
	  else
	    {
	      if ([node isDirectory] && ([node isPackage] == NO))
		{
		  path = [node path];
		}
	      else
		{
		  path = [node parentPath];
		}
	    }
	}
      else
	{
	  path = [[nodeView shownNode] path];
	}
    }

  [gfinder startXTermOnDirectory: path];
}

- (BOOL)validateItem:(id)menuItem
{
  if ([NSApp keyWindow] == vwrwin) {
    SEL action = [menuItem action];
    NSString *itemTitle = [menuItem title];
    NSString *menuTitle = [[menuItem menu] title];

    if ([menuTitle isEqual: NSLocalizedString(@"Icon Size", @"")]) {
      return [nodeView respondsToSelector: @selector(setIconSize:)];
    } else if ([menuTitle isEqual: NSLocalizedString(@"Icon Position", @"")]) {
      return [nodeView respondsToSelector: @selector(setIconPosition:)];
    } else if ([menuTitle isEqual: NSLocalizedString(@"Label Size", @"")]) {
      return [nodeView respondsToSelector: @selector(setLabelTextSize:)];
    } else if ([itemTitle isEqual: NSLocalizedString(@"Label Color...", @"")]) {
      return [nodeView respondsToSelector: @selector(setTextColor:)];
    } else if ([itemTitle isEqual: NSLocalizedString(@"Background Color...", @"")]) {
      return [nodeView respondsToSelector: @selector(setBackgroundColor:)];

    } else if (sel_isEqual(action, @selector(duplicateFiles:))
                    || sel_isEqual(action, @selector(recycleFiles:))
                        || sel_isEqual(action, @selector(deleteFiles:))) {
      if (lastSelection && [lastSelection count]
              && ([lastSelection isEqual: baseNodeArray] == NO)) {
        return ([[baseNode path] isEqual: [gfinder trashPath]] == NO);
      }

      return NO;
    } else if (sel_isEqual(action, @selector(makeThumbnails:)) || sel_isEqual(action, @selector(removeThumbnails:)))
      {
        /* Make or Remove Thumbnails */
        return YES;
    } else if (sel_isEqual(action, @selector(openSelection:))) {
      if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
        BOOL canopen = YES;
        NSUInteger i;

        if (lastSelection && [lastSelection count] 
                && ([lastSelection isEqual: baseNodeArray] == NO)) {
          for (i = 0; i < [lastSelection count]; i++) {
            FSNode *node = [lastSelection objectAtIndex: i];

            if ([node isDirectory] && ([node isPackage] == NO)) {
              canopen = NO;
              break;      
            }
          }
        } else {
          canopen = NO;
        }

        return canopen;
      }

      return NO;

    } else if (sel_isEqual(action, @selector(openSelectionAsFolder:))) {
      if (lastSelection && ([lastSelection count] == 1)) {  
        return [[lastSelection objectAtIndex: 0] isDirectory];
      }

      return NO;

    } else if (sel_isEqual(action, @selector(openWith:))) {
      BOOL canopen = YES;
      int i;

      if (lastSelection && [lastSelection count]
            && ([lastSelection isEqual: baseNodeArray] == NO)) {
        for (i = 0; i < [lastSelection count]; i++) {
          FSNode *node = [lastSelection objectAtIndex: i];

          if (([node isPlain] == NO) 
                && (([node isPackage] == NO) || [node isApplication])) {
            canopen = NO;
            break;
          }
        }
      } else {
        canopen = NO;
      }

      return canopen;

    } else if (sel_isEqual(action, @selector(newFolder:))
                                  || sel_isEqual(action, @selector(newFile:))) {
      if ([[baseNode path] isEqual: [gfinder trashPath]] == NO) {
        return [[nodeView shownNode] isWritable];
      }

      return NO;
    }
    
    return YES;   
  } else {
    SEL action = [menuItem action];
    if (sel_isEqual(action, @selector(makeKeyAndOrderFront:))) {
      return YES;
    }
  }
  
  return NO;
}

- (void)makeThumbnails:(id)sender
{
  NSString *path;

  path = [[nodeView shownNode] path];
  path = [path stringByResolvingSymlinksInPath];
  if (path)
    {
      Thumbnailer *t;
      
      t = [Thumbnailer sharedThumbnailer];
      [t makeThumbnails:path];
      [t release];
    }
}

- (void)removeThumbnails:(id)sender
{
  NSString *path;

  path = [[nodeView shownNode] path];
  path = [path stringByResolvingSymlinksInPath];
  if (path)
    {
      Thumbnailer *t;
      
      t = [Thumbnailer sharedThumbnailer];
      [t removeThumbnails:path];
      [t release];
    }
}

@end
