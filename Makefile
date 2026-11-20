# Build ls.exe for 16-bit MS-DOS with Open Watcom and libc16.
#   make                         fetch the pinned libc16 release into
#                                build/libc16, then build ls.exe
#   make LIBC16_ROOT=../libc16   use a libc16 checkout built with its make
#   make test                    check the help topic, then run
#                                tests/run.sh under DOSBox-X
#   make dist                    the release ZIP, ls16-VERSION.zip
#
# -R lists a directory's subdirectories recursively, so ls.exe has a
# 4 KB stack rather than libc16's default 2 KB: room for DOS's deepest
# paths.
#
# ls.exe is compiled and linked against libc16 only (its ABI is in
# libc16's docs/ABI.md), with the Open Watcom snapshot libc16 was built
# with: the libc16 tree's tools/fetch-watcom fetches it into build/tools.

LIBC16_ROOT ?= build/libc16
# A release tree, or a checkout, whose make stages the same layout in
# build/stage.
LIBC16_DIR  := $(if $(wildcard $(LIBC16_ROOT)/build/stage/VERSION),$(LIBC16_ROOT)/build/stage,$(LIBC16_ROOT))
LIBC16      := $(LIBC16_DIR)/lib/LIBC16.LIB
TOOLS_ENV   := build/tools.env
WATCOM_ENV   = . ./$(TOOLS_ENV) && PATH=$$WATCOM/binl64:$$PATH

VERSION := $(shell cat VERSION)
DIST    := ls16-$(VERSION).zip
TOPIC   := help/topics/LS.txt

CC     = wcc
CFLAGS = -q -zq -zl -zld -x -ms -0 -os -s -bt=dos -wx -we \
         -I$(LIBC16_DIR)/include '-DVERSION="$(VERSION)"'

ls.exe: ls.obj $(LIBC16) $(TOOLS_ENV)
	$(WATCOM_ENV) && wlink option quiet, nodefaultlibs, map=ls.map \
	  option stack=4096 format dos name $@ file ls.obj library $(LIBC16)

ls.obj: ls.c VERSION $(LIBC16) $(TOOLS_ENV)
	$(WATCOM_ENV) && $(CC) $(CFLAGS) -fo=$@ ls.c

# The pinned libc16 release (scripts/fetch-libc16). A LIBC16_ROOT given
# on the command line must already be built.
ifeq ($(LIBC16_ROOT),build/libc16)
$(LIBC16): scripts/fetch-libc16
	scripts/fetch-libc16 $(LIBC16_ROOT)
endif

# The Open Watcom snapshot libc16 names, as shell assignments.
$(TOOLS_ENV): $(LIBC16)
	mkdir -p build
	watcom=$$(sh $(LIBC16_DIR)/tools/fetch-watcom $(CURDIR)/build/tools) \
	  && printf 'WATCOM=%s\nexport WATCOM\n' "$$watcom" > $@

test: ls.exe
	sh scripts/check-help $(TOPIC)
	sh tests/run.sh $(CURDIR)/ls.exe

# The release ZIP: ls.exe and its GR-DOS help topic at
# help/topics/LS.txt (gr-dos/gr-dos#90), with the license and README.
dist: $(DIST)

$(DIST): ls.exe $(TOPIC) LICENSE README.md
	sh scripts/check-help $(TOPIC)
	rm -rf build/dist $@
	mkdir -p build/dist/help/topics
	cp ls.exe LICENSE README.md build/dist/
	cp $(TOPIC) build/dist/help/topics/
	cd build/dist && zip -q -X -r ../../$@ ls.exe help LICENSE README.md

clean:
	rm -f *.o *.obj *.err *.map ls.exe ls16-*.zip
	rm -rf build/dist

.PHONY: test dist clean
