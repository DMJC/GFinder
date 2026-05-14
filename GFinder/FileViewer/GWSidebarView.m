/* GWSidebarView.m
 *
 * Copyright (C) 2025 Free Software Foundation, Inc.
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

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import <objc/runtime.h>
#import <mntent.h>
#import <sys/vfs.h>
#import "GWSidebarView.h"
#import "GWViewer.h"

/* Linux network-filesystem magic numbers */
#define NFS_SUPER_MAGIC   0x6969
#define SMB_SUPER_MAGIC   0x517B
#define CIFS_SUPER_MAGIC  0xFF534D42
#define SMB2_SUPER_MAGIC  0xFE534D42
#define FUSE_SUPER_MAGIC  0x65735546   /* covers sshfs, rclone, gvfs-fuse … */
#define AFP_SUPER_MAGIC   0x6B414653
#define NCPFS_SUPER_MAGIC 0x564C

static BOOL
isNetworkMount(NSString *path)
{
  struct statfs sfs;
  if (statfs([path fileSystemRepresentation], &sfs) != 0)
    return NO;
  switch ((unsigned long)sfs.f_type)
    {
      case NFS_SUPER_MAGIC:
      case SMB_SUPER_MAGIC:
      case CIFS_SUPER_MAGIC:
      case SMB2_SUPER_MAGIC:
      case FUSE_SUPER_MAGIC:
      case AFP_SUPER_MAGIC:
      case NCPFS_SUPER_MAGIC:
        return YES;
      default:
        return NO;
    }
}


/* ---- Private data model ---- */

@interface GWSidebarItem : NSObject
{
  NSString *_label;
  NSImage  *_icon;
  NSString *_path;
}
- (id)initWithLabel:(NSString *)label icon:(NSImage *)icon path:(NSString *)path;
- (NSString *)label;
- (NSImage  *)icon;
- (NSString *)path;
@end

@implementation GWSidebarItem

- (id)initWithLabel:(NSString *)label icon:(NSImage *)icon path:(NSString *)path
{
  self = [super init];
  if (self)
    {
      ASSIGN(_label, label);
      ASSIGN(_icon,  icon);
      ASSIGN(_path,  path);
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_label);
  RELEASE(_icon);
  RELEASE(_path);
}

- (NSString *)label { return _label; }
- (NSImage  *)icon  { return _icon;  }
- (NSString *)path  { return _path;  }

@end


@interface GWSidebarSection : NSObject
{
  NSString       *_title;
  NSMutableArray *_items;
}
- (id)initWithTitle:(NSString *)title;
- (NSString *)title;
- (NSMutableArray *)items;
- (void)addItem:(GWSidebarItem *)item;
@end

@implementation GWSidebarSection

- (id)initWithTitle:(NSString *)title
{
  self = [super init];
  if (self)
    {
      ASSIGN(_title, title);
      _items = [NSMutableArray new];
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_title);
  RELEASE(_items);
}

- (NSString       *)title { return _title; }
- (NSMutableArray *)items { return _items; }
- (void)addItem:(GWSidebarItem *)item { [_items addObject: item]; }

@end


/* ---- Custom outline cell ---- */

@interface GWSidebarCell : NSTextFieldCell
{
  NSImage *_icon;
  BOOL     _isHeader;
}
- (void)setIcon:(NSImage *)icon;
- (void)setIsHeader:(BOOL)flag;
@end

@implementation GWSidebarCell

- (id)copyWithZone:(NSZone *)zone
{
  GWSidebarCell *copy = (GWSidebarCell *)[super copyWithZone: zone];
  /* NSCell's copyWithZone uses NSCopyObject (bitwise copy), leaving ARC-managed
     ivars as unretained shared pointers.  Zero them at raw memory level before
     ARC-managed re-assignment to prevent over-releasing the original's objects. */
  {
    char *base = (char *)(__bridge void *)copy;
    const char *names[] = { "_icon", NULL };
    for (int i = 0; names[i]; i++)
      {
        Ivar iv = class_getInstanceVariable([GWSidebarCell class], names[i]);
        if (iv) memset(base + ivar_getOffset(iv), 0, sizeof(id));
      }
  }
  return copy;
}

- (void)dealloc
{
  RELEASE(_icon);
}

- (void)setIcon:(NSImage *)icon
{
  ASSIGN(_icon, icon);
}

- (void)setIsHeader:(BOOL)flag
{
  _isHeader = flag;
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
  if (_isHeader)
    {
      NSString *title = [[self stringValue] uppercaseString];
      NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize: 9], NSFontAttributeName,
        [NSColor grayColor], NSForegroundColorAttributeName,
        nil];
      NSRect tr = frame;
      tr.origin.x += 8;
      tr.origin.y += (frame.size.height - 11) / 2.0;
      tr.size.width -= 8;
      tr.size.height = 11;
      [title drawInRect: tr withAttributes: attrs];
      return;
    }

  /* Highlight background */
  if ([self isHighlighted])
    {
      [[NSColor selectedControlColor] set];
      NSRectFill(frame);
    }

  /* Icon */
  if (_icon)
    {
      NSRect ir = NSMakeRect(frame.origin.x + 8,
                             frame.origin.y + (frame.size.height - 16) / 2.0,
                             16, 16);
      [_icon drawInRect: ir
               fromRect: NSZeroRect
              operation: NSCompositeSourceOver
               fraction: 1.0];
    }

  /* Label */
  NSColor *textColor = [self isHighlighted]
    ? [NSColor selectedControlTextColor]
    : [NSColor controlTextColor];

  NSDictionary *textAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont systemFontOfSize: 12], NSFontAttributeName,
    textColor, NSForegroundColorAttributeName,
    nil];

  NSRect tr = frame;
  tr.origin.x += _icon ? 30 : 8;
  tr.origin.y += (frame.size.height - 14) / 2.0;
  tr.size.width -= _icon ? 34 : 8;
  tr.size.height = 14;

  [[self stringValue] drawInRect: tr withAttributes: textAttrs];
}

@end


/* ---- Helpers ---- */

static NSImage *
iconForPath(NSString *path)
{
  NSImage *icon = nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath: path])
    icon = [[NSWorkspace sharedWorkspace] iconForFile: path];
  if (icon == nil)
    icon = [NSImage imageNamed: @"NSFolder"];
  if (icon != nil)
    {
      icon = AUTORELEASE([icon copy]);
      [icon setSize: NSMakeSize(16, 16)];
    }
  return icon;
}


/* ---- GWSidebarView ---- */

@implementation GWSidebarView

- (id)initWithFrame:(NSRect)frame forViewer:(id)vwr
{
  self = [super initWithFrame: frame];
  if (self)
    {
      viewer   = vwr;
      nc       = [NSNotificationCenter defaultCenter];
      sections = [NSMutableArray new];

      [self buildSections];
      [self buildOutlineView];
      [self registerForVolumeNotifications];
    }
  return self;
}

- (void)dealloc
{
  [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self];
  [nc removeObserver: self];
  RELEASE(sections);
}


/* ---- Section builders ---- */

- (NSString *)deviceForMountPoint:(NSString *)mountPoint
{
  FILE *f = setmntent("/proc/mounts", "r");
  if (!f) f = setmntent("/etc/mtab", "r");
  if (!f) return nil;

  struct mntent *entry;
  NSString *result = nil;
  while ((entry = getmntent(f)) != NULL)
    {
      if (strcmp(entry->mnt_dir, [mountPoint fileSystemRepresentation]) == 0)
        {
          result = [NSString stringWithUTF8String: entry->mnt_fsname];
          break;
        }
    }
  endmntent(f);
  return result;
}

- (BOOL)isPhysicalBlockDevice:(NSString *)device
{
  if (![device hasPrefix: @"/dev/"])
    return NO;
  NSString *name = [device lastPathComponent];
  NSArray *patterns = [NSArray arrayWithObjects:
    @"^sd[a-z]+[0-9]*$",
    @"^hd[a-z]+[0-9]*$",
    @"^sg[0-9]+$",
    @"^nvme[0-9]+n[0-9]+(p[0-9]+)?$",
    nil];
  for (NSString *pattern in patterns)
    {
      NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern: pattern options: 0 error: nil];
      if ([re numberOfMatchesInString: name
                              options: 0
                                range: NSMakeRange(0, [name length])] > 0)
        return YES;
    }
  return NO;
}

- (void)buildDevicesSection
{
  GWSidebarSection *sec = AUTORELEASE([[GWSidebarSection alloc]
    initWithTitle: NSLocalizedString(@"Devices", @"")]);
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *vols = [[NSWorkspace sharedWorkspace] mountedLocalVolumePaths];

  for (NSString *volPath in vols)
    {
      BOOL isDir = NO;
      if (![fm fileExistsAtPath: volPath isDirectory: &isDir] || !isDir)
        continue;
      NSString *device = [self deviceForMountPoint: volPath];
      if (device == nil || ![self isPhysicalBlockDevice: device])
        continue;
      NSString *name = [volPath isEqualToString: @"/"]
        ? NSLocalizedString(@"Computer", @"")
        : [volPath lastPathComponent];
      GWSidebarItem *item = AUTORELEASE([[GWSidebarItem alloc]
        initWithLabel: name
                 icon: iconForPath(volPath)
                 path: volPath]);
      [sec addItem: item];
    }

  [sections addObject: sec];
}

- (void)buildSharedSection
{
  GWSidebarSection *sec = AUTORELEASE([[GWSidebarSection alloc]
    initWithTitle: NSLocalizedString(@"Shared", @"")]);
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *vols = [[NSWorkspace sharedWorkspace] mountedLocalVolumePaths];

  for (NSString *volPath in vols)
    {
      BOOL isDir = NO;
      if ([fm fileExistsAtPath: volPath isDirectory: &isDir] && isDir
          && isNetworkMount(volPath))
        {
          NSString *name = [volPath lastPathComponent];
          GWSidebarItem *item = AUTORELEASE([[GWSidebarItem alloc]
            initWithLabel: name
                     icon: iconForPath(volPath)
                     path: volPath]);
          [sec addItem: item];
        }
    }

  [sections addObject: sec];
}

- (void)buildPlacesSection
{
  GWSidebarSection *sec = AUTORELEASE([[GWSidebarSection alloc]
    initWithTitle: NSLocalizedString(@"Places", @"")]);
  NSFileManager *fm = [NSFileManager defaultManager];

  NSArray *fixed = [NSArray arrayWithObjects:
    [NSArray arrayWithObjects: NSLocalizedString(@"All My Files", @""),
      NSHomeDirectory(), nil],
    [NSArray arrayWithObjects: NSLocalizedString(@"Desktop", @""),
      [NSHomeDirectory() stringByAppendingPathComponent: @"Desktop"], nil],
    [NSArray arrayWithObjects: NSLocalizedString(@"Home", @""),
      NSHomeDirectory(), nil],
    nil];

  for (NSArray *entry in fixed)
    {
      NSString *label = [entry objectAtIndex: 0];
      NSString *path  = [entry objectAtIndex: 1];
      GWSidebarItem *item = AUTORELEASE([[GWSidebarItem alloc]
        initWithLabel: label icon: iconForPath(path) path: path]);
      [sec addItem: item];
    }

  NSArray *appdirs = NSSearchPathForDirectoriesInDomains(
    NSApplicationDirectory, NSLocalDomainMask, YES);
  if ([appdirs count] > 0)
    {
      NSString *appPath = [appdirs objectAtIndex: 0];
      GWSidebarItem *appItem = AUTORELEASE([[GWSidebarItem alloc]
        initWithLabel: NSLocalizedString(@"Applications", @"")
                 icon: iconForPath(appPath)
                 path: appPath]);
      [sec addItem: appItem];
    }

  NSArray *fixed1 = [NSArray arrayWithObjects:
    [NSArray arrayWithObjects: NSLocalizedString(@"Documents", @""),
      [NSHomeDirectory() stringByAppendingPathComponent: @"Documents"], nil],
    [NSArray arrayWithObjects: NSLocalizedString(@"Downloads", @""),
      [NSHomeDirectory() stringByAppendingPathComponent: @"Downloads"], nil],
    nil];

  for (NSArray *entry in fixed1)
    {
      NSString *label = [entry objectAtIndex: 0];
      NSString *path  = [entry objectAtIndex: 1];
      GWSidebarItem *item = AUTORELEASE([[GWSidebarItem alloc]
        initWithLabel: label icon: iconForPath(path) path: path]);
      [sec addItem: item];
    }

  [sections addObject: sec];
}

- (void)buildSections
{
  [sections removeAllObjects];
  [self buildDevicesSection];
  [self buildSharedSection];
  [self buildPlacesSection];
}


/* ---- Outline view setup ---- */

- (void)buildOutlineView
{
  NSRect r = [self bounds];

  scrollView = [[NSScrollView alloc] initWithFrame: r];
  [scrollView setHasVerticalScroller: YES];
  [scrollView setHasHorizontalScroller: NO];
  [scrollView setAutohidesScrollers: YES];
  [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [scrollView setBorderType: NSNoBorder];

  NSRect ovFrame = [[scrollView contentView] bounds];
  outlineView = [[NSOutlineView alloc] initWithFrame: ovFrame];
  [outlineView setAutoresizesOutlineColumn: YES];
  [outlineView setIndentationPerLevel: 8];
  [outlineView setRowHeight: 22];
  [outlineView setDrawsGrid: NO];
  [outlineView setHeaderView: nil];
  [outlineView setDataSource: self];
  [outlineView setDelegate: self];

  NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier: @"SidebarColumn"];
  [col setMinWidth: 60];
  [col setWidth: r.size.width];
  [col setResizingMask: NSTableColumnAutoresizingMask];

  GWSidebarCell *cell = [[GWSidebarCell alloc] init];
  [cell setEditable: NO];
  [cell setWraps: NO];
  [col setDataCell: cell];
  RELEASE(cell);

  [outlineView addTableColumn: col];
  [outlineView setOutlineTableColumn: col];
  RELEASE(col);

  [scrollView setDocumentView: outlineView];
  RELEASE(outlineView);

  [self addSubview: scrollView];
  RELEASE(scrollView);

  [nc addObserver: self
         selector: @selector(outlineViewSelectionDidChange:)
             name: NSOutlineViewSelectionDidChangeNotification
           object: outlineView];

  [outlineView reloadData];
  for (id section in sections)
    [outlineView expandItem: section];
}

- (void)registerForVolumeNotifications
{
  NSNotificationCenter *wsnc = [[NSWorkspace sharedWorkspace] notificationCenter];
  [wsnc addObserver: self
           selector: @selector(volumeDidMount:)
               name: NSWorkspaceDidMountNotification
             object: nil];
  [wsnc addObserver: self
           selector: @selector(volumeDidUnmount:)
               name: NSWorkspaceDidUnmountNotification
             object: nil];
}

- (void)volumeDidMount:(NSNotification *)notif   { [self reloadDevices]; }
- (void)volumeDidUnmount:(NSNotification *)notif { [self reloadDevices]; }

- (void)reloadDevices
{
  [self buildSections];
  [outlineView reloadData];
  for (id section in sections)
    [outlineView expandItem: section];
}


/* ---- Selection → navigation ---- */

- (void)outlineViewSelectionDidChange:(NSNotification *)notif
{
  NSInteger row = [outlineView selectedRow];
  if (row < 0) return;

  id item = [outlineView itemAtRow: row];
  if ([item isKindOfClass: [GWSidebarItem class]])
    {
      NSString *path = [(GWSidebarItem *)item path];
      if (path && [viewer respondsToSelector: @selector(goToDirectory:)])
        [viewer performSelector: @selector(goToDirectory:) withObject: path];
    }
}


/* ---- NSOutlineViewDataSource ---- */

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
  if (item == nil)
    return (NSInteger)[sections count];
  if ([item isKindOfClass: [GWSidebarSection class]])
    return (NSInteger)[[(GWSidebarSection *)item items] count];
  return 0;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
  return [item isKindOfClass: [GWSidebarSection class]];
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
  if (item == nil)
    return [sections objectAtIndex: (NSUInteger)index];
  if ([item isKindOfClass: [GWSidebarSection class]])
    return [[(GWSidebarSection *)item items] objectAtIndex: (NSUInteger)index];
  return nil;
}

- (id)outlineView:(NSOutlineView *)ov
objectValueForTableColumn:(NSTableColumn *)col
           byItem:(id)item
{
  if ([item isKindOfClass: [GWSidebarSection class]])
    return [(GWSidebarSection *)item title];
  if ([item isKindOfClass: [GWSidebarItem class]])
    return [(GWSidebarItem *)item label];
  return @"";
}


/* ---- NSOutlineViewDelegate ---- */

- (BOOL)outlineView:(NSOutlineView *)ov shouldSelectItem:(id)item
{
  return [item isKindOfClass: [GWSidebarItem class]];
}

- (void)outlineView:(NSOutlineView *)ov
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)col
               item:(id)item
{
  if (![cell isKindOfClass: [GWSidebarCell class]])
    return;

  if ([item isKindOfClass: [GWSidebarSection class]])
    {
      [(GWSidebarCell *)cell setIsHeader: YES];
      [(GWSidebarCell *)cell setIcon: nil];
    }
  else if ([item isKindOfClass: [GWSidebarItem class]])
    {
      [(GWSidebarCell *)cell setIsHeader: NO];
      [(GWSidebarCell *)cell setIcon: [(GWSidebarItem *)item icon]];
    }
}

- (CGFloat)outlineView:(NSOutlineView *)ov heightOfRowByItem:(id)item
{
  return 22.0;
}

@end
