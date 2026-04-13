/* DDBDirsManager.m
 *  
 * Copyright (C) 2005-2012 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: July 2005
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

#include "DBKBTreeNode.h"
#include "DBKVarLenRecordsFile.h"
#include "DDBDirsManager.h"
#include "ddbd.h"

@implementation	DDBDirsManager

- (void)dealloc
{
  RELEASE (vlfile);
  RELEASE (tree);
  RELEASE (dummyPaths[0]);
  RELEASE (dummyPaths[1]);
  RELEASE (dummyOffsets[0]);
  RELEASE (dummyOffsets[1]);
      
}

- (id)initWithBasePath:(NSString *)bpath
{
  self = [super init];

  if (self) {
    NSString *path;

    ulen = sizeof(unsigned);
    llen = sizeof(unsigned long);

    path = [bpath stringByAppendingPathComponent: @"directories"];
    vlfile = [[DBKVarLenRecordsFile alloc] initWithPath: path cacheLength: 10];

    path = [bpath stringByAppendingPathComponent: @"directories.index"];
    tree = [[DBKBTree alloc] initWithPath: path order: 16 delegate: self];

    ASSIGN (dummyOffsets[0], [NSNumber numberWithUnsignedLong: 1L]);
    ASSIGN (dummyOffsets[1], [NSNumber numberWithUnsignedLong: 2L]);
  
    fm = [NSFileManager defaultManager];
    
    [self addDirectory: pathsep()];
    [self synchronize];
  }

  return self;
}

- (void)synchronize
{
  [vlfile flush];
  [tree synchronize];
}

- (void)addDirectory:(NSString *)dir
{
@autoreleasepool {
  DBKBTreeNode *node;
  
  DESTROY (dummyPaths[1]);  
  ASSIGN (dummyPaths[0], dir);
  
  [tree begin];
  node = [tree insertKey: dummyOffsets[0]];

  if (node) {
    NSData *data = [dir dataUsingEncoding: NSUTF8StringEncoding];
    NSNumber *offset = [vlfile writeData: data];
    
    [node replaceKey: dummyOffsets[0] withKey: offset];
  }
  
  [tree end];
  
  } // @autoreleasepool
}

- (void)removeDirectory:(NSString *)dir
{
  DBKBTreeNode *node; 
  NSUInteger index;
  BOOL exists;

  DESTROY (dummyPaths[1]);
  ASSIGN (dummyPaths[0], dir);
  
  [tree begin];
  node = [tree nodeOfKey: dummyOffsets[0] getIndex: &index didExist: &exists];

  if (exists) {
    NSNumber *offset = [node keyAtIndex: index];
    
    [tree deleteKey: offset];
    [vlfile deleteDataAtOffset: offset]; 
    RELEASE (offset);
  }
  
  [tree end];
}

- (void)insertDirsFromPaths:(NSArray *)paths
{
  NSUInteger i;

  for (i = 0; i < [paths count]; i++) {
    @autoreleasepool {
      NSString *base = [paths objectAtIndex: i];
      NSDictionary *attributes = [fm fileAttributesAtPath: base traverseLink: NO];
      NSString *type = [attributes fileType];

      if (type == NSFileTypeDirectory) {
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath: base];
        IMP nxtImp = [enumerator methodForSelector: @selector(nextObject)];

        while (1) {
          @autoreleasepool {
            NSString *path = (*nxtImp)(enumerator, @selector(nextObject));

            if (path) {
              if ([[enumerator fileAttributes] fileType] == NSFileTypeDirectory) {
                [self addDirectory: [base stringByAppendingPathComponent: path]];
              }
            } else {
              break;
            }
          }
        }

        [self addDirectory: base];
      }
    }
  }

  [self synchronize];
}

- (void)removeDirsFromPaths:(NSArray *)paths
{
  NSUInteger i, j;
  
  for (i = 0; i < [paths count]; i++) {  
@autoreleasepool {
    NSString *base = [paths objectAtIndex: i];
    NSArray *treepaths = [self dirsFromPath: base];
    int count = [treepaths count];
    
    if (count) {
      for (j = 0; j < [treepaths count]; j++) {
        [self removeDirectory: [treepaths objectAtIndex: j]];
      }
    }

  } // @autoreleasepool
  }
  
  [self synchronize];
}

- (NSArray *)dirsFromPath:(NSString *)path
{
  NSMutableArray *paths = [NSMutableArray array];

@autoreleasepool {
  NSMutableArray *toremove = [NSMutableArray array];
  NSArray *keys = nil;
  NSUInteger i;

  [tree begin];
  
  if ([path isEqual: pathsep()] == NO) {
    ASSIGN (dummyPaths[0], [path stringByAppendingString: pathsep()]);
    ASSIGN (dummyPaths[1], [path stringByAppendingString: @"0"]);
  } else {
    ASSIGN (dummyPaths[0], path);
    ASSIGN (dummyPaths[1], @"0");
  }

  keys = [tree keysGreaterThenKey: dummyOffsets[0] 
                 andLesserThenKey: dummyOffsets[1]];

  [tree end];
  
  if (keys) {
    for (i = 0; i < [keys count]; i++) {
@autoreleasepool {
      NSData *data = [vlfile dataAtOffset: [keys objectAtIndex: i]];
      NSString *path = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
      BOOL isdir;

      if ([fm fileExistsAtPath: path isDirectory: &isdir] &&isdir) {
        [paths addObject: path];
      } else {
        [toremove addObject: path];
      }

      RELEASE (path);
  } // @autoreleasepool
    }  
  }

  for (i = 0; i < [toremove count]; i++) {
    [self removeDirectory: [toremove objectAtIndex: i]];
  }
  
  } // @autoreleasepool
  
  return paths;
}


//
// DBKBTreeDelegate methods
//

- (unsigned long)nodesize
{
  return 512;
} 

- (NSArray *)keysFromData:(NSData *)data
               withLength:(unsigned *)dlen
{
  NSMutableArray *keys = [NSMutableArray array];
  NSRange range;
  unsigned kcount;
  unsigned long key;
  unsigned i;
  
  range = NSMakeRange(0, sizeof(unsigned));
  [data getBytes: &kcount range: range];
  range.location += sizeof(unsigned);
  
  range.length = sizeof(unsigned long);

  for (i = 0; i < kcount; i++) {
    [data getBytes: &key range: range];
    [keys addObject: [NSNumber numberWithUnsignedLong: key]];
    range.location += sizeof(unsigned long);
  }
  
  *dlen = range.location;
  
  return keys;
}

- (NSData *)dataFromKeys:(NSArray *)keys
{
  NSMutableData *data = [NSMutableData dataWithCapacity: 1];
  NSUInteger kcount = [keys count];
  NSUInteger i;
  
  [data appendData: [NSData dataWithBytes: &kcount length: sizeof(unsigned)]];
    
  for (i = 0; i < kcount; i++) {
    unsigned long kl = [[keys objectAtIndex: i] unsignedLongValue];
    [data appendData: [NSData dataWithBytes: &kl length: sizeof(unsigned long)]];
  }
  
  return data;  
}

- (NSComparisonResult)compareNodeKey:(id)akey
                             withKey:(id)bkey
{
  NSComparisonResult result = NSOrderedSame;

@autoreleasepool {
  NSString *astr;
  NSString *bstr;
  
  if ([akey isEqual: dummyOffsets[0]]) {
    astr = RETAIN (dummyPaths[0]);
  } else {
    NSData *data = [vlfile dataAtOffset: (NSNumber *)akey];
    astr = [[NSString alloc] initWithData: data
                                 encoding: NSUTF8StringEncoding];
  }
  
  if ([bkey isEqual: dummyOffsets[0]]) {
    bstr = RETAIN (dummyPaths[0]);
  } else if ([bkey isEqual: dummyOffsets[1]]) {
    bstr = RETAIN (dummyPaths[1]);
  } else {
    NSData *data = [vlfile dataAtOffset: (NSNumber *)bkey];
    bstr = [[NSString alloc] initWithData: data
                                 encoding: NSUTF8StringEncoding];
  }

  result = [astr compare: bstr];
  
  RELEASE (astr);
  RELEASE (bstr);
  } // @autoreleasepool
  
  return result;  
}

@end
