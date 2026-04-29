/* GWSidebarView.h
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

#ifndef GW_SIDEBAR_VIEW_H
#define GW_SIDEBAR_VIEW_H

#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import <AppKit/NSOutlineView.h>

@interface GWSidebarView : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
  NSScrollView  *scrollView;
  NSOutlineView *outlineView;
  NSMutableArray *sections;
  id viewer;
  NSNotificationCenter *nc;
}

- (id)initWithFrame:(NSRect)frame forViewer:(id)vwr;

- (void)reloadDevices;

@end

#endif /* GW_SIDEBAR_VIEW_H */
