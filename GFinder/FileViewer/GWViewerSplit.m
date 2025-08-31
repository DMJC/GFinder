/* GWViewerSplit.m
 *  
 * Copyright (C) 2004-2012 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
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

#import <AppKit/AppKit.h>
#import "GWViewerSplit.h"

@implementation GWViewerSplit 

- (void)dealloc
{
  RELEASE (diskInfoField);
  RELEASE (fileCountField);
  [super dealloc];
}

- (id)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame: frameRect]; 

  diskInfoField = [NSTextFieldCell new];
  [diskInfoField setFont: [NSFont systemFontOfSize: 10]];
  [diskInfoField setBordered: NO];
  [diskInfoField setAlignment: NSLeftTextAlignment];
  [diskInfoField setTextColor: [NSColor controlShadowColor]];
  diskInfoRect = NSZeroRect;

  fileCountField = [NSTextFieldCell new];
  [fileCountField setFont: [NSFont systemFontOfSize: 10]];
  [fileCountField setBordered: NO];
  [fileCountField setAlignment: NSLeftTextAlignment];
  [fileCountField setTextColor: [NSColor controlShadowColor]];
  fileCountRect = NSZeroRect;

  return self;
}

- (void)updateDiskSpaceInfo:(NSString *)info
{
	if (info) {
  	[diskInfoField setStringValue: info]; 
	} else {
  	[diskInfoField setStringValue: @""]; 
  }
  
  if (NSEqualRects(diskInfoRect, NSZeroRect) == NO) {
    [diskInfoField drawWithFrame: diskInfoRect inView: self];
  }
}

- (void)updateFileCountInfo:(NSString *)info
{
  if (info) {
    [fileCountField setStringValue: info];
  } else {
    [fileCountField setStringValue: @""];
  }

  if (NSEqualRects(fileCountRect, NSZeroRect) == NO) {
    [fileCountField drawWithFrame: fileCountRect inView: self];
  }
}

- (CGFloat)dividerThickness
{
  return 11;
}

- (void)drawDividerInRect:(NSRect)aRect
{
  [super drawDividerInRect: aRect];
  [diskInfoField setBackgroundColor: [self backgroundColor]];
  [fileCountField setBackgroundColor: [self backgroundColor]];
  [diskInfoField drawWithFrame: diskInfoRect inView: self];
  [fileCountField drawWithFrame: fileCountRect inView: self];
}

@end
