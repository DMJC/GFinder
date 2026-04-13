/* DesktopPref.m
 *  
 * Copyright (C) 2005-2021 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola <rm@gnu.org>
 * Date: January 2005
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "DesktopPref.h"
#import "GWDesktopManager.h"
#import "GFinder.h"
#import "GWDesktopView.h"
#import "Dock.h"
#import "TShelf/TShelfWin.h"

static NSString *nibName = @"DesktopPref";

@implementation DesktopPref

- (void)dealloc
{
  RELEASE (prefbox);
  RELEASE (imagePath);
  RELEASE (imagesDir);

}

- (id)init
{
  self = [super init];

  if (self)
    {
      if ([NSBundle loadNibNamed: nibName owner: self] == NO)
	{
	  NSLog(@"failed to load %@!", nibName);
	}
      else
	{
	  NSString *impath;
	  id cell;

	  RELEASE (win);

	  manager = [GWDesktopManager desktopManager];
	  gfinder = [GFinder gfinder];

	  // Color
	  [NSColorPanel setPickerMask: NSColorPanelWheelModeMask
			| NSColorPanelRGBModeMask
			| NSColorPanelColorListModeMask];
	  [NSColorPanel setPickerMode: NSWheelModeColorPanel];
	  [colorWell setColor: [[manager desktopView] currentColor]];

	  // Background image
	  [imageView setEditable: NO];
	  [imageView setImageScaling: NSScaleProportionally];

	  impath = [[manager desktopView] backImagePath];
	  if (impath) {
	    ASSIGN (imagePath, impath);
	  }

	  if (imagePath)
	    {
@autoreleasepool {
	      NSImage *image = [[NSImage alloc] initWithContentsOfFile: imagePath];

	      if (image)
		{
		  [imageView setImage: image];
		  RELEASE (image);
		}
  } // @autoreleasepool
	    }

	  [imagePosMatrix selectCellAtRow: [[manager desktopView] backImageStyle] column: 0];

	  BOOL useImage = [[manager desktopView] useBackImage];
	  [imageView setEnabled: useImage];
	  [chooseImageButt setEnabled: useImage];
	  [imagePosMatrix setEnabled: useImage];
	  [useImageSwitch setState: useImage ? NSOnState : NSOffState];

	  // General
	  [omnipresentCheck setState: ([manager usesXBundle] ? NSOnState : NSOffState)];
	  [launchSingleClick setState: ([manager singleClickLaunch] ? NSOnState : NSOffState)];
	  [hideTShelfCheck setState: NSOffState];

	  /* Internationalization */
	  [[tabView tabViewItemAtIndex: 0] setLabel: NSLocalizedString(@"Background", @"")];
	  [[tabView tabViewItemAtIndex: 1] setLabel: NSLocalizedString(@"General", @"")];

	  [colorLabel setStringValue:_(@"Color:")];
	  cell = [imagePosMatrix cellAtRow: BackImageCenterStyle column: 0];
	  [cell setTitle: NSLocalizedString(@"center", @"")];
	  cell = [imagePosMatrix cellAtRow: BackImageFitStyle column: 0];
	  [cell setTitle: NSLocalizedString(@"fit", @"")];
	  cell = [imagePosMatrix cellAtRow: BackImageTileStyle column: 0];
	  [cell setTitle: NSLocalizedString(@"tile", @"")];
	  cell = [imagePosMatrix cellAtRow: BackImageScaleStyle column: 0];
	  [cell setTitle: NSLocalizedString(@"scale", @"")];
	  [useImageSwitch setTitle: NSLocalizedString(@"Use image", @"")];
	  [chooseImageButt setTitle: NSLocalizedString(@"Choose", @"")];

	  [omnipresentCheck setTitle: _(@"Omnipresent")];
	  [hideTShelfCheck setTitle: NSLocalizedString(@"Autohide Tabbed Shelf", @"")];
	  [launchSingleClick setTitle: NSLocalizedString(@"Single Click Launch", @"")];
	}
    }

  return self;
}

- (NSView *)prefView
{
  return prefbox;
}

- (NSString *)prefName
{
  return NSLocalizedString(@"Desktop", @"");
}

// Color
- (IBAction)setColor:(id)sender
{
  [[manager desktopView] setCurrentColor: [colorWell color]];
  if ([gfinder respondsToSelector: @selector(tshelfBackgroundDidChange)]) [gfinder performSelector: @selector(tshelfBackgroundDidChange)];
}


// Background image
- (IBAction)chooseImage:(id)sender
{
  NSOpenPanel *openPanel;
  NSInteger result;

  openPanel = [NSOpenPanel openPanel];
  [openPanel setTitle: NSLocalizedString(@"Choose Image", @"")];	
  [openPanel setAllowsMultipleSelection: NO];
  [openPanel setCanChooseFiles: YES];
  [openPanel setCanChooseDirectories: NO];
  
  if (imagesDir == nil) {
    ASSIGN (imagesDir, NSHomeDirectory());
  }

  result = [openPanel runModalForDirectory: imagesDir
                                      file: nil 
                                     types: [NSImage imageFileTypes]];
                                     
  if (result == NSOKButton) {
@autoreleasepool {
    NSString *impath = [openPanel filename];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile: impath];

    if (image) {
      [imageView setImage: image];
      ASSIGN (imagePath, impath);
      ASSIGN (imagesDir, [imagePath stringByDeletingLastPathComponent]);
      RELEASE (image);
    }
    
  } // @autoreleasepool
  }

  if (imagePath) {  
    [[manager desktopView] setBackImageAtPath: imagePath];
    [imagePosMatrix selectCellAtRow: [[manager desktopView] backImageStyle] 
                             column: 0];
    if ([gfinder respondsToSelector: @selector(tshelfBackgroundDidChange)]) [gfinder performSelector: @selector(tshelfBackgroundDidChange)];
  }
}

- (IBAction)setImage:(id)sender
{
  // FIXME: Handle image dropped on image view?
}

- (IBAction)setImageStyle:(id)sender
{
  id cell = [imagePosMatrix selectedCell];
  NSInteger row, col;
  
  [imagePosMatrix getRow: &row column: &col ofCell: cell];
  [[manager desktopView] setBackImageStyle: row];  
  if ([gfinder respondsToSelector: @selector(tshelfBackgroundDidChange)]) [gfinder performSelector: @selector(tshelfBackgroundDidChange)];
}

- (IBAction)setUseImage:(id)sender
{
  BOOL useImage = ([sender state] == NSOnState);
  [[manager desktopView] setUseBackImage: useImage];
  if ([gfinder respondsToSelector: @selector(tshelfBackgroundDidChange)]) [gfinder performSelector: @selector(tshelfBackgroundDidChange)];
  [imageView setEnabled: useImage];
  [chooseImageButt setEnabled: useImage];
  [imagePosMatrix setEnabled: useImage];
}


// General
- (IBAction)setOmnipresent:(id)sender
{
  [manager setUsesXBundle: ([sender state] == NSOnState)];  
  if ([manager usesXBundle] == NO) {
    [sender setState: NSOffState];
  }
}

- (IBAction)setTShelfAutohide:(id)sender
{
  // tabbedShelf was removed
}

- (IBAction)setSingleClickLaunch:(id)sender
{
  [manager setSingleClickLaunch: ([sender state] == NSOnState)];
}

@end
