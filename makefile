#!/usr/bin/make -f
#
# Makefile for Zapper tech demo for NES
# Copyright 2011 Damian Yerrick
#
# Copying and distribution of this file, with or without
# modification, are permitted in any medium without royalty
# provided the copyright notice and this notice are preserved.
# This file is offered as-is, without any warranty.
#

# These are used in the title of the NES program and the zip file.
title = ruder
version = 0.03

# Space-separated list of assembly language files that make up the
# PRG ROM.  If it gets too long for one line, you can add a backslash
# (the \ character) at the end of the line and continue on the next.
objlist := zapkernels main ppuclear title menu testpatterns \
           drawball kinematics tennis tennisgfx \
           axe sound music musicseq ntscPeriods \
           bcd math pads unpkb

objlistnsf := nsfshell sound music musicseq ntscPeriods

AS65 = ca65
LD65 = ld65
CFLAGS65 := -DZAPPER_TO_A_BUTTON=1 -DSOUND_NTSC_ONLY=1 \
  -DMUSIC_USE_ROW_CALLBACK=1
objdir = obj/nes
srcdir = src
imgdir = tilesets

#EMU := "/C/Program Files/Nintendulator/Nintendulator.exe"
#EMU := fceux --input1 GamePad.0 --input2 Zapper.0
EMU := mednafen -nes.pal 0 -nes.input.port1 gamepad -nes.input.port2 zapper

# other options for EMU are start (Windows) or gnome-open (GNOME)

# Occasionally, you need to make "build tools", or programs that run
# on a PC that convert, compress, or otherwise translate PC data
# files into the format that the NES program expects.  Some people
# write their build tools in C or C++; others prefer to write them in
# Perl, PHP, or Python.  This program doesn't use any C build tools,
# but if yours does, it might include definitions of variables that
# Make uses to call a C compiler.
CC = gcc
CFLAGS = -std=gnu99 -Wall -DNDEBUG -O

# Windows needs .exe suffixed to the names of executables; UNIX does
# not.  COMSPEC will be set to the name of the shell on Windows and
# not defined on UNIX.
ifdef COMSPEC
DOTEXE=.exe
else
DOTEXE=
endif

.PHONY: run dist zip

run: $(title).nes
	$(EMU) $<

# Rule to create or update the distribution zipfile by adding all
# files listed in zip.in.  Actually the zipfile depends on every
# single file in zip.in, but currently we use changes to the compiled
# program, makefile, and README as a heuristic for when something was
# changed.  It won't see changes to docs or tools, but usually when
# docs changes, README also changes, and when tools changes, the
# makefile changes.
dist: zip
zip: $(title)-$(version).zip
$(title)-$(version).zip: zip.in $(title).nes $(title).nsf \
  README.txt $(objdir)/index.txt
	zip -9 -u $@ -@ < $<

# Build zip.in from the list of files in the Git tree
zip.in:
	git ls-files | grep -e "^[^.]" > $@
	echo zip.in >> $@

%.nes: %.prg %.chr
	cat $^ > $@

$(objdir)/index.txt: makefile
	echo Files produced by build tools go here, but caulk goes where? > $@

# Rules for PRG ROM

objlistntsc := $(foreach o,$(objlist),$(objdir)/$(o).o)
objlistnsf := $(foreach o,$(objlistnsf),$(objdir)/$(o).o)

map.txt $(title).prg: nes.ini $(objlistntsc)
	$(LD65) -C $^ -m map.txt -o $(title).prg

nsfmap.txt $(title).nsf: nsf.ini $(objlistnsf)
	$(LD65) -C $^ -m nsfmap.txt -o $(title).nsf

$(objdir)/%.o: $(srcdir)/%.s $(srcdir)/nes.h $(srcdir)/ram.h
	$(AS65) $(CFLAGS65) $< -o $@

$(objdir)/%.o: $(objdir)/%.s
	$(AS65) $(CFLAGS65) $< -o $@

# Files that depend on .incbin'd files or on other headers
$(objdir)/testpatterns.o: $(srcdir)/ballbg.pkb $(srcdir)/fullbright.pkb \
    $(srcdir)/hlines.pkb $(srcdir)/menu.pkb $(srcdir)/vlines.pkb \
    $(srcdir)/pulltrigger.pkb

$(objdir)/tennis.o: $(srcdir)/tennis.h
$(objdir)/tennisgfx.o: $(srcdir)/tennis.h $(srcdir)/tennis_title.pkb 
$(objdir)/math.o: $(srcdir)/tennis.h
$(objdir)/kinematics.o: $(srcdir)/tennis.h
$(objdir)/title.o: $(srcdir)/title.pkb

# Generate lookup tables at build time
$(objdir)/ntscPeriods.s: tools/mktables.py
	$< period $@

# Rules for CHR ROM

$(title).chr: $(objdir)/bggfx.chr $(objdir)/spritegfx.chr
	cat $^ > $@

$(objdir)/%.chr: $(imgdir)/%.png
	tools/pilbmp2nes.py $< $@

$(objdir)/%16.chr: $(imgdir)/%.png
	tools/pilbmp2nes.py -H 16 $< $@


