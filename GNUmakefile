ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
  ifeq ($(GNUSTEP_MAKEFILES),)
    $(warning )
    $(warning Unable to obtain GNUSTEP_MAKEFILES setting from gnustep-config!)
    $(warning Perhaps gnustep-make is not properly installed,)
    $(warning so gnustep-config is not in your PATH.)
    $(warning )
    $(warning Your PATH is currently $(PATH))
    $(warning )
  endif
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

PACKAGE_NEEDS_CONFIGURE = YES

PACKAGE_NAME = gfinder
export PACKAGE_NAME
include $(GNUSTEP_MAKEFILES)/common.make

VERSION = 1.1.0
SVN_MODULE_NAME = gfinder

BUILD_GWMETADATA = 0

#
# subprojects
#
SUBPROJECTS = FSNode \
	      DBKit \
	      Tools \
	      Inspector \
	      Operation \
	      Recycler \
	      GFinder

ifeq ($(BUILD_GWMETADATA),1)
SUBPROJECTS += GFMetadata
endif


-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

include GNUmakefile.postamble

include $(GNUSTEP_MAKEFILES)/Master/nsis.make
