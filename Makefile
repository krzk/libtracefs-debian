# SPDX-License-Identifier: LGPL-2.1
# libtracefs version
TFS_VERSION = 1
TFS_PATCHLEVEL = 0
TFS_EXTRAVERSION = 2
TRACEFS_VERSION = $(TFS_VERSION).$(TFS_PATCHLEVEL).$(TFS_EXTRAVERSION)

export TFS_VERSION
export TFS_PATCHLEVEL
export TFS_EXTRAVERSION
export TRACEFS_VERSION

# taken from trace-cmd
MAKEFLAGS += --no-print-directory

# Makefiles suck: This macro sets a default value of $(2) for the
# variable named by $(1), unless the variable has been set by
# environment or command line. This is necessary for CC and AR
# because make sets default values, so the simpler ?= approach
# won't work as expected.
define allow-override
  $(if $(or $(findstring environment,$(origin $(1))),\
            $(findstring command line,$(origin $(1)))),,\
    $(eval $(1) = $(2)))
endef

# Allow setting CC and AR, or setting CROSS_COMPILE as a prefix.
$(call allow-override,CC,$(CROSS_COMPILE)gcc)
$(call allow-override,AR,$(CROSS_COMPILE)ar)
$(call allow-override,PKG_CONFIG,pkg-config)
$(call allow-override,LD_SO_CONF_PATH,/etc/ld.so.conf.d/)
$(call allow-override,LDCONFIG,ldconfig)

EXT = -std=gnu99
INSTALL = install

# Use DESTDIR for installing into a different root directory.
# This is useful for building a package. The program will be
# installed in this directory as if it was the root directory.
# Then the build tool can move it later.
DESTDIR ?=
DESTDIR_SQ = '$(subst ','\'',$(DESTDIR))'

LP64 := $(shell echo __LP64__ | ${CC} ${CFLAGS} -E -x c - | tail -n 1)
ifeq ($(LP64), 1)
  libdir_relative_temp = lib64
else
  libdir_relative_temp = lib
endif

libdir_relative ?= $(libdir_relative_temp)
prefix ?= /usr/local
bindir_relative = bin
bindir = $(prefix)/$(bindir_relative)
man_dir = $(prefix)/share/man
man_dir_SQ = '$(subst ','\'',$(man_dir))'
libdir = $(prefix)/$(libdir_relative)
libdir_SQ = '$(subst ','\'',$(libdir))'
includedir_relative ?= include/tracefs
includedir = $(prefix)/$(includedir_relative)
includedir_SQ = '$(subst ','\'',$(includedir))'
pkgconfig_dir ?= $(word 1,$(shell $(PKG_CONFIG) 		\
			--variable pc_path pkg-config | tr ":" " "))

LIBTRACEEVENT_INCLUDES = $(shell $(PKG_CONFIG) --cflags libtraceevent)
LIBTRACEEVENT_LIBS = $(shell $(PKG_CONFIG) --libs libtraceevent)

ifneq ($(MAKECMDGOALS),clean)
 ifeq ("$(LIBTRACEEVENT_INCLUDES)","")
   $(error libtraceevent.so not installed)
 endif
endif

etcdir ?= /etc
etcdir_SQ = '$(subst ','\'',$(etcdir))'

export man_dir man_dir_SQ html_install html_install_SQ INSTALL
export img_install img_install_SQ
export DESTDIR DESTDIR_SQ

# Shell quotes
bindir_SQ = $(subst ','\'',$(bindir))
bindir_relative_SQ = $(subst ','\'',$(bindir_relative))

pound := \#

HELP_DIR = -DHELP_DIR=$(html_install)
HELP_DIR_SQ = '$(subst ','\'',$(HELP_DIR))'
#' emacs highlighting gets confused by the above escaped quote.

BASH_COMPLETE_DIR ?= $(etcdir)/bash_completion.d

# copy a bit from Linux kbuild

ifeq ("$(origin V)", "command line")
  VERBOSE = $(V)
endif
ifndef VERBOSE
  VERBOSE = 0
endif

SILENT := $(if $(findstring s,$(filter-out --%,$(MAKEFLAGS))),1)

# $(call test-build, snippet, ret) -> ret if snippet compiles
#                                  -> empty otherwise
test-build = $(if $(shell sh -c 'echo "$(1)" | \
	$(CC) -o /dev/null -c -x c - > /dev/null 2>&1 && echo y'), $2)

# have flush/fua block layer instead of barriers?
blk-flags := $(call test-build,$(BLK_TC_FLUSH_SOURCE),-DHAVE_BLK_TC_FLUSH)

ifeq ("$(origin O)", "command line")

  saved-output := $(O)
  BUILD_OUTPUT := $(shell cd $(O) && /bin/pwd)
  $(if $(BUILD_OUTPUT),, \
    $(error output directory "$(saved-output)" does not exist))

else
  BUILD_OUTPUT = $(CURDIR)
endif

srctree		:= $(if $(BUILD_SRC),$(BUILD_SRC),$(CURDIR))
objtree		:= $(BUILD_OUTPUT)
src		:= $(srctree)
obj		:= $(objtree)
bdir		:= $(obj)/lib/tracefs

export prefix bindir src obj bdir

LIBTRACEFS_STATIC = $(bdir)/libtracefs.a
LIBTRACEFS_SHARED = $(bdir)/libtracefs.so.$(TRACEFS_VERSION)

PKG_CONFIG_SOURCE_FILE = libtracefs.pc
PKG_CONFIG_FILE := $(addprefix $(obj)/,$(PKG_CONFIG_SOURCE_FILE))

LIBS = $(LIBTRACEEVENT_LIBS)

export LIBS
export LIBTRACEFS_STATIC LIBTRACEFS_SHARED

export Q SILENT VERBOSE EXT

# Include the utils
include scripts/utils.mk

INCLUDES = -I$(src)/include
INCLUDES += -I$(src)/include/tracefs

include $(src)/scripts/features.mk

# Set compile option CFLAGS if not set elsewhere
CFLAGS ?= -g -Wall
CPPFLAGS ?=
LDFLAGS ?=

CUNIT_INSTALLED := $(shell if (printf "$(pound)include <CUnit/Basic.h>\n void main(){CU_initialize_registry();}" | $(CC) -x c - -lcunit -o /dev/null >/dev/null 2>&1) ; then echo 1; else echo 0 ; fi)
export CUNIT_INSTALLED

export CFLAGS
export INCLUDES

# Append required CFLAGS
override CFLAGS += -D_GNU_SOURCE $(LIBTRACEEVENT_INCLUDES) $(INCLUDES)

all: all_cmd

LIB_TARGET  = libtracefs.a libtracefs.so.$(TRACEFS_VERSION)
LIB_INSTALL = libtracefs.a libtracefs.so*
LIB_INSTALL := $(addprefix $(bdir)/,$(LIB_INSTALL))

TARGETS = $(LIBTRACEFS_SHARED) $(LIBTRACEFS_STATIC)

all_cmd: $(TARGETS) $(PKG_CONFIG_FILE)

libtracefs.a: $(LIBTRACEFS_STATIC)
libtracefs.so: $(LIBTRACEFS_SHARED)

libs: libtracefs.a libtracefs.so

test: force $(LIBTRACEFS_STATIC)
ifneq ($(CUNIT_INSTALLED),1)
	$(error CUnit framework not installed, cannot build unit tests))
endif
	$(Q)$(MAKE) -C $(src)/utest $@

define find_tag_files
	find . -name '\.pc' -prune -o -name '*\.[ch]' -print -o -name '*\.[ch]pp' \
		! -name '\.#' -print
endef

define do_make_pkgconfig_file
	cp -f ${PKG_CONFIG_SOURCE_FILE}.template ${PKG_CONFIG_FILE};	\
	sed -i "s|INSTALL_PREFIX|${1}|g" ${PKG_CONFIG_FILE}; 		\
	sed -i "s|LIB_VERSION|${TRACEFS_VERSION}|g" ${PKG_CONFIG_FILE}; \
	sed -i "s|LIB_DIR|${libdir_relative}|g" ${PKG_CONFIG_FILE}; \
	sed -i "s|HEADER_DIR|$(includedir_relative)|g" ${PKG_CONFIG_FILE};
endef

BUILD_PREFIX := $(BUILD_OUTPUT)/build_prefix

$(BUILD_PREFIX): force
	$(Q)$(call build_prefix,$(prefix))

$(PKG_CONFIG_FILE) : ${PKG_CONFIG_SOURCE_FILE}.template $(BUILD_PREFIX)
	$(Q) $(call do_make_pkgconfig_file,$(prefix))

tags:	force
	$(RM) tags
	$(call find_tag_files) | xargs ctags --extra=+f --c-kinds=+px

TAGS:	force
	$(RM) TAGS
	$(call find_tag_files) | xargs etags

cscope: force
	$(RM) cscope*
	$(call find_tag_files) | cscope -b -q

ifeq ("$(DESTDIR)", "")
# If DESTDIR is not defined, then test if after installing the library
# and running ldconfig, if the library is visible by ld.so.
# If not, add the path to /etc/ld.so.conf.d/trace.conf and run ldconfig again.
define install_ld_config
	$(LDCONFIG); \
	if ! grep "^$(libdir)$$" $(LD_SO_CONF_PATH)/* &> /dev/null ; then \
		$(CC) -o $(objtree)/test $(srctree)/test.c -I $(includedir_SQ) \
			-L $(libdir_SQ) -ltracefs &> /dev/null; \
		if ! $(objtree)/test &> /dev/null; then \
			$(call print_install, trace.conf, $(LD_SO_CONF_PATH)) \
			echo $(libdir_SQ) >> $(LD_SO_CONF_PATH)/trace.conf; \
			$(LDCONFIG); \
		fi; \
		$(RM) $(objtree)/test; \
	fi
endef
else
# If installing to a location for another machine or package, do not bother
# with running ldconfig.
define install_ld_config
endef
endif # DESTDIR = ""

install_libs: libs install_pkgconfig
	$(Q)$(call do_install,$(LIBTRACEFS_SHARED),$(libdir_SQ)); \
		cp -fpR $(LIB_INSTALL) $(DESTDIR)$(libdir_SQ)
	$(Q)$(call do_install,$(src)/include/tracefs.h,$(includedir_SQ),644)
	$(Q)$(call install_ld_config)

install: install_libs

install_pkgconfig: $(PKG_CONFIG_FILE)
	$(Q)$(call , $(PKG_CONFIG_FILE)) \
		$(call do_install_pkgconfig_file,$(prefix))

doc:
	$(MAKE) -C $(src)/Documentation all

doc_clean:
	$(MAKE) -C $(src)/Documentation clean

install_doc:
	$(MAKE) -C $(src)/Documentation install

define build_uninstall_script
	$(Q)mkdir $(BUILD_OUTPUT)/tmp_build
	$(Q)$(MAKE) -C $(src) DESTDIR=$(BUILD_OUTPUT)/tmp_build/ O=$(BUILD_OUTPUT) $1 > /dev/null
	$(Q)find $(BUILD_OUTPUT)/tmp_build ! -type d -printf "%P\n" > $(BUILD_OUTPUT)/build_$2
	$(Q)$(RM) -rf $(BUILD_OUTPUT)/tmp_build
endef

build_uninstall: $(BUILD_PREFIX)
	$(call build_uninstall_script,install,uninstall)

$(BUILD_OUTPUT)/build_uninstall: build_uninstall

define uninstall_file
	if [ -f $(DESTDIR)/$1 -o -h $(DESTDIR)/$1 ]; then \
		$(call print_uninstall,$(DESTDIR)/$1)$(RM) $(DESTDIR)/$1; \
	fi;
endef

uninstall: $(BUILD_OUTPUT)/build_uninstall
	@$(foreach file,$(shell cat $(BUILD_OUTPUT)/build_uninstall),$(call uninstall_file,$(file)))

PHONY += force
force:

# Declare the contents of the .PHONY variable as phony.  We keep that
# information in a variable so we can use it in if_changed and friends.
.PHONY: $(PHONY)

DEFAULT_TARGET = $(LIBTRACEFS_STATIC)

OBJS =
OBJS += tracefs-utils.o
OBJS += tracefs-instance.o
OBJS += tracefs-events.o

OBJS := $(OBJS:%.o=$(bdir)/%.o)
DEPS := $(OBJS:$(bdir)/%.o=$(bdir)/.%.d)

all: $(DEFAULT_TARGET)

$(bdir):
	@mkdir -p $(bdir)

$(LIBTRACEFS_STATIC): force
	$(Q)mkdir -p $(bdir)
	$(Q)$(MAKE) -C $(src)/src $@

$(bdir)/libtracefs.so.$(TRACEFS_VERSION): force
	$(Q)mkdir -p $(bdir)
	$(Q)$(MAKE) -C $(src)/src libtracefs.so

clean:
	$(MAKE) -C $(src)/utest clean
	$(MAKE) -C $(src)/src clean
	$(RM) $(TARGETS) $(bdir)/*.a $(bdir)/*.so $(bdir)/*.so.* $(bdir)/*.o $(bdir)/.*.d
	$(RM) $(PKG_CONFIG_FILE)

.PHONY: clean
