#!/bin/sh
#
# Test ls.exe under DOSBox-X.
#
# Fixtures: the work directory is mounted as C:, and a 2.88 MB FAT
# floppy image built with mtools (volume label LSTEST) as D:.  The image
# holds what a host directory cannot: DOS read-only, hidden, system and
# archive attributes on files and directories, a volume label, a VFAT
# long file name, and exact DOS dates and times.  Every file and
# directory on it is dated 2001-01-01 01:00:00 unless the test needs
# another time.
#
# One batch file runs every DOS-side step, and the results are checked
# on the host afterwards.  Each step N records ls's exit status in
# RN.TXT and its standard output in ON.TXT.  DOS cannot redirect
# standard error, so diagnostics are not checked.  rc.bat uses goto
# rather than "if errorlevel N echo ... >file" because the DOSBox-X
# shell opens the redirection even when the test is false.  Output to
# the console (ls's default columns) is read back from video memory
# with tests/scrdump.asm.
#
# To add a test: add a step to steps.bat (command, then "call c:\rc N")
# and the matching rc/expect/check lines below.
#
# Usage: tests/run.sh [path/to/ls.exe]
# Environment: DOSBOX (default dosbox-x), NASM (default nasm), KEEP=1 to
#              keep the work directory.  Needs mtools.

set -u

top=$(cd "$(dirname "$0")/.." && pwd)
exe=${1:-$top/ls.exe}
DOSBOX=${DOSBOX:-dosbox-x}
NASM=${NASM:-nasm}

for t in "$DOSBOX" "$NASM" mformat mcopy mattrib; do
    command -v "$t" >/dev/null || { echo "$t not found" >&2; exit 2; }
done
[ -f "$exe" ] || { echo "$exe not found" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/dosls.XXXXXX")
pass=0
fail=0
LC_ALL=C
TZ=UTC
MTOOLSRC=/dev/null
MTOOLS_SKIP_CHECK=1
export LC_ALL TZ MTOOLSRC MTOOLS_SKIP_CHECK

# ------------------------------------------------------------------
# fixtures

cd "$work" || exit 2
cp "$exe" ls.exe
"$NASM" -f bin -o scrdump.com "$top/tests/scrdump.asm" || exit 2

# C:\CWD, for the current directory and relative paths
mkdir -p cwd/sub
: > cwd/zeta.txt
: > cwd/alpha.txt
: > cwd/beta
: > cwd/sub/inner.txt

# C:\DEEP\A\A\...: 31 levels, for -R to DOS's 64-character path limit
deep=deep
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
         21 22 23 24 25 26 27 28 29 30 31; do
    deep=$deep/a
done
mkdir -p "$deep"
: > "$deep/bottom.txt"

# D:, built in fix/ and copied into d.img
# mkfile PATH SIZE
mkfile() {
    head -c "$2" /dev/zero > "fix/$1"
}

mkdir -p fix/DIR1/SUB fix/DIR1/HSUB fix/HIDDIR fix/SYSDIR fix/TIMES \
         fix/SIZES fix/COLS/WIDE fix/COLS/MIX
mkfile NORMAL.TXT 10
mkfile RDONLY.TXT 11
mkfile ARCH.TXT 12
mkfile RA.TXT 13
mkfile HIDDEN.TXT 14
mkfile SYSTEM.TXT 15
mkfile HS.TXT 16
mkfile PROG.EXE 17
mkfile TOOL.COM 18
mkfile RUN.BAT 19
mkfile NOTEXE.EXT 20
mkfile README 21
mkfile longfilename.text 22
mkfile DIR1/FILE.TXT 1
mkfile DIR1/SUB/DEEP.TXT 1
mkfile DIR1/HSUB/X.TXT 1
mkfile HIDDIR/IN.TXT 1
mkfile SYSDIR/IN.TXT 1
mkfile TIMES/OLD.TXT 1
mkfile TIMES/MID.TXT 2
mkfile TIMES/NEW.TXT 3
mkfile TIMES/TIE1.TXT 4
mkfile TIMES/TIE2.TXT 5
mkfile TIMES/A_TIE.TXT 6
mkfile TIMES/SEC.TXT 7
mkfile TIMES/HID.TXT 8
mkfile SIZES/A.DAT 0
mkfile SIZES/B.DAT 1023
mkfile SIZES/C.DAT 1024
mkfile SIZES/D.DAT 1025
mkfile SIZES/E.DAT 1536
mkfile SIZES/F.DAT 10239
mkfile SIZES/G.DAT 10240
mkfile SIZES/H.DAT 1048576
mkfile SIZES/I.DAT 1100000
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 \
         16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    mkfile COLS/WIDE/F$i.TXT 0
done
for f in A BB CCCCCCCC.TXT D EE.E F; do
    mkfile COLS/MIX/$f 0
done
find fix -exec touch -d '2001-01-01 01:00:00' {} +
touch -d '2001-01-01 00:00:00' fix/TIMES/OLD.TXT
touch -d '2010-06-15 12:30:00' fix/TIMES/MID.TXT
touch -d '2012-01-01 00:00:00' fix/TIMES/HID.TXT
touch -d '2015-05-05 05:05:04' fix/TIMES/TIE1.TXT fix/TIMES/TIE2.TXT \
                               fix/TIMES/A_TIE.TXT
touch -d '2015-05-05 05:05:06' fix/TIMES/SEC.TXT
touch -d '2020-12-31 23:58:00' fix/TIMES/NEW.TXT

mformat -C -i d.img -f 2880 -v LSTEST :: &&
    (cd fix && mcopy -s -m -i ../d.img * ::) &&
    mattrib -i d.img -a ::/NORMAL.TXT &&
    mattrib -i d.img -a +r ::/RDONLY.TXT &&
    mattrib -i d.img +r ::/RA.TXT &&
    mattrib -i d.img +h ::/HIDDEN.TXT &&
    mattrib -i d.img +s ::/SYSTEM.TXT &&
    mattrib -i d.img +r +h +s ::/HS.TXT &&
    mattrib -i d.img +h ::/HIDDIR &&
    mattrib -i d.img +s ::/SYSDIR &&
    mattrib -i d.img +h ::/DIR1/HSUB &&
    mattrib -i d.img +h ::/TIMES/HID.TXT || exit 2

cat > rc.bat <<'EOS'
@echo off
if errorlevel 2 goto rc2
if errorlevel 1 goto rc1
echo rc0 >c:\r%1.txt
goto end
:rc1
echo rc1 >c:\r%1.txt
goto end
:rc2
echo rc2 >c:\r%1.txt
:end
EOS

cat > steps.bat <<'EOS'
@echo off
rem --- help and version
c:\ls --help >c:\o1.txt
call c:\rc 1
c:\ls -? >c:\o2.txt
call c:\rc 2
c:\ls --version >c:\o3.txt
call c:\rc 3
rem --- bad options
c:\ls -x >c:\o4.txt
call c:\rc 4
c:\ls -lx d:\ >c:\o5.txt
call c:\rc 5
c:\ls --bogus >c:\o6.txt
call c:\rc 6
rem --- visibility at a drive root: default, -a, -A
c:\ls d:\ >c:\o10.txt
call c:\rc 10
c:\ls -a d:\ >c:\o11.txt
call c:\rc 11
c:\ls -A d:\ >c:\o12.txt
call c:\rc 12
rem --- long listing: attributes, sizes, dates
c:\ls -l d:\ >c:\o13.txt
call c:\rc 13
c:\ls -la d:\ >c:\o14.txt
call c:\rc 14
c:\ls -lA d:\ >c:\o15.txt
call c:\rc 15
rem --- visibility in a subdirectory: . and .. come from DOS
c:\ls d:\dir1 >c:\o16.txt
call c:\rc 16
c:\ls -a d:\dir1 >c:\o17.txt
call c:\rc 17
c:\ls -A d:\dir1 >c:\o18.txt
call c:\rc 18
c:\ls -la d:\hiddir >c:\o19.txt
call c:\rc 19
rem --- -F
c:\ls -F d:\ >c:\o20.txt
call c:\rc 20
c:\ls -aF d:\dir1 >c:\o21.txt
call c:\rc 21
rem --- columns, explicit while redirected
c:\ls -C d:\cols\wide >c:\o22.txt
call c:\rc 22
c:\ls -CF d:\ >c:\o23.txt
call c:\rc 23
c:\ls -C -F d:\ >c:\o24.txt
call c:\rc 24
c:\ls -C d:\cols\mix >c:\o25.txt
call c:\rc 25
set COLUMNS=40
c:\ls -C d:\cols\wide >c:\o26.txt
call c:\rc 26
set COLUMNS=20
c:\ls -C d:\cols\mix >c:\o27.txt
call c:\rc 27
set COLUMNS=
rem --- display mode precedence: the last of -C, -1, -l
c:\ls -1C d:\cols\mix >c:\o28.txt
call c:\rc 28
c:\ls -C1 d:\cols\mix >c:\o29.txt
call c:\rc 29
c:\ls -lC d:\cols\mix >c:\o30.txt
call c:\rc 30
c:\ls -Cl d:\cols\mix >c:\o31.txt
call c:\rc 31
c:\ls -l -1 d:\cols\mix >c:\o32.txt
call c:\rc 32
c:\ls -1 d:\cols\mix -C >c:\o33.txt
call c:\rc 33
rem --- sorting by name, by time, reversed
c:\ls d:\times >c:\o40.txt
call c:\rc 40
c:\ls -t d:\times >c:\o41.txt
call c:\rc 41
c:\ls -r d:\times >c:\o42.txt
call c:\rc 42
c:\ls -tr d:\times >c:\o43.txt
call c:\rc 43
c:\ls -ltr d:\times >c:\o44.txt
call c:\rc 44
c:\ls -l -t -r d:\times >c:\o45.txt
call c:\rc 45
c:\ls -tAr d:\times >c:\o46.txt
call c:\rc 46
c:\ls -t -A -r d:\times >c:\o47.txt
call c:\rc 47
c:\ls -lt d:\times >c:\o48.txt
call c:\rc 48
rem --- sizes
c:\ls -l d:\sizes >c:\o50.txt
call c:\rc 50
c:\ls -lh d:\sizes >c:\o51.txt
call c:\rc 51
c:\ls -h d:\sizes >c:\o52.txt
call c:\rc 52
rem --- grouped options equal separate ones
c:\ls -alF d:\ >c:\o53.txt
call c:\rc 53
c:\ls -a -l -F d:\ >c:\o54.txt
call c:\rc 54
c:\ls -1F d:\ >c:\o55.txt
call c:\rc 55
c:\ls -1 -F d:\ >c:\o56.txt
call c:\rc 56
rem --- -d
c:\ls -d d:\dir1 d:\normal.txt >c:\o60.txt
call c:\rc 60
c:\ls -dF d:\dir1 >c:\o61.txt
call c:\rc 61
c:\ls -ld d:\ d:\hiddir >c:\o62.txt
call c:\rc 62
c:\ls -d d:\r* >c:\o63.txt
call c:\rc 63
rem --- -R
c:\ls -R d:\dir1 >c:\o64.txt
call c:\rc 64
c:\ls -RA d:\dir1 >c:\o65.txt
call c:\rc 65
c:\ls -Ra d:\dir1 >c:\o66.txt
call c:\rc 66
c:\ls -RF d:\dir1 >c:\o67.txt
call c:\rc 67
rem --- operands: files first, then directories with headers; errors
c:\ls d:\readme d:\dir1 d:\normal.txt >c:\o70.txt
call c:\rc 70
c:\ls d:\nosuch d:\normal.txt >c:\o71.txt
call c:\rc 71
c:\ls d:\hidden.txt d:\sysdir >c:\o72.txt
call c:\rc 72
c:\ls q:\ >c:\o73.txt
call c:\rc 73
c:\ls -- -l >c:\o74.txt
call c:\rc 74
rem --- wildcards
c:\ls d:\*.txt >c:\o75.txt
call c:\rc 75
c:\ls -A d:\*.txt >c:\o76.txt
call c:\rc 76
c:\ls d:\r* >c:\o77.txt
call c:\rc 77
c:\ls d:\t* >c:\o78.txt
call c:\rc 78
c:\ls d:\*.zzz >c:\o79.txt
call c:\rc 79
c:\ls -a d:\* >c:\o80.txt
call c:\rc 80
c:\ls d:/dir1/sub >c:\o81.txt
call c:\rc 81
rem --- options after operands, and across drives
c:\ls d:\times -t >c:\o82.txt
call c:\rc 82
c:\ls d:\times -l -tr >c:\o83.txt
call c:\rc 83
c:\ls -F d:\dir1 c:\cwd >c:\o84.txt
call c:\rc 84
cd d:\times
c:\ls d: -t >c:\o85.txt
call c:\rc 85
c:\ls -l d:old.txt >c:\o86.txt
call c:\rc 86
d:
c:\ls >c:\o87.txt
call c:\rc 87
c:\ls -a >c:\o88.txt
call c:\rc 88
c:\ls -F .. >c:\o89.txt
call c:\rc 89
c:\ls c:\cwd -F >c:\o90.txt
call c:\rc 90
cd \
c:\ls -a >c:\o91.txt
call c:\rc 91
c:\ls -ld >c:\o92.txt
call c:\rc 92
c:
cd \cwd
c:\ls >c:\o93.txt
call c:\rc 93
c:\ls sub >c:\o94.txt
call c:\rc 94
c:\ls -d . .. >c:\o95.txt
call c:\rc 95
cd \
c:\ls -R c:\deep >c:\o100.txt
call c:\rc 100
rem --- the console: columns by default, at the screen's width
cls
c:\ls d:\cols\wide
scrdump >c:\o96.txt
cls
c:\ls -F d:\
scrdump >c:\o97.txt
cls
c:\ls -1 d:\cols\mix
scrdump >c:\o98.txt
mode co40
cls
c:\ls d:\cols\wide
scrdump >c:\o99.txt
mode co80
EOS

SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout 300 \
    "$DOSBOX" -defaultconf -silent -nogui -nomenu \
    -set "cpu cycles=max" \
    -c "mount c \"$work\"" -c "imgmount d \"$work/d.img\" -t floppy" \
    -c "c:" -c "steps.bat" -c "exit" >dosbox.log 2>&1

# ------------------------------------------------------------------
# checks

ok()     { pass=$((pass + 1)); }
not_ok() { echo "FAIL: $*"; fail=$((fail + 1)); }

# check NAME COMMAND...
check() {
    name=$1
    shift
    if "$@"; then ok; else not_ok "$name"; fi
}

# rc STEP EXPECTED-STATUS
rc() {
    got=$(tr -d ' \r' < "R$1.TXT" 2>/dev/null | sed 's/^rc//')
    if [ "$got" = "$2" ]; then
        ok
    else
        not_ok "step $1: exit status ${got:-missing}, expected $2"
    fi
}

# norm STEP: ON.TXT without CRs or trailing empty lines (a screen dump
# has them)
norm() {
    tr -d '\r' < "O$1.TXT" 2>/dev/null | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

# expect STEP < expected-lines
expect() {
    norm "$1" > got.txt
    cat > want.txt
    if cmp -s got.txt want.txt; then
        ok
    else
        not_ok "step $1: output differs"
        diff want.txt got.txt | sed 's/^/    /'
    fi
}

# same STEP STEP: the two outputs are identical (and not empty)
same() {
    norm "$1" > a.txt
    norm "$2" > b.txt
    if [ -s a.txt ] && cmp -s a.txt b.txt; then
        ok
    else
        not_ok "steps $1 and $2 differ"
    fi
}

# --- help and version
rc 1 0
check "step 1: help" grep -q '^Usage: ls' O1.TXT
rc 2 0
check "step 2: -? same as --help" cmp -s O1.TXT O2.TXT
rc 3 0
expect 3 <<EOS
ls (ls16) $(cat "$top/VERSION")
EOS

# --- bad options: nothing listed
rc 4 1
expect 4 < /dev/null
rc 5 1
expect 5 < /dev/null
rc 6 1
expect 6 < /dev/null

# --- visibility at a drive root.  The volume label LSTEST and the long
# name's VFAT slots never appear; the root has a . with -a but no ..
rc 10 0
expect 10 <<'EOS'
arch.txt
cols
dir1
longfi~1.tex
normal.txt
notexe.ext
prog.exe
ra.txt
rdonly.txt
readme
run.bat
sizes
times
tool.com
EOS
rc 11 0
expect 11 <<'EOS'
.
arch.txt
cols
dir1
hidden.txt
hiddir
hs.txt
longfi~1.tex
normal.txt
notexe.ext
prog.exe
ra.txt
rdonly.txt
readme
run.bat
sizes
sysdir
system.txt
times
tool.com
EOS
rc 12 0
expect 12 <<'EOS'
arch.txt
cols
dir1
hidden.txt
hiddir
hs.txt
longfi~1.tex
normal.txt
notexe.ext
prog.exe
ra.txt
rdonly.txt
readme
run.bat
sizes
sysdir
system.txt
times
tool.com
EOS

# --- long listing.  Read-only and archive files (R---A for both) are
# listed by default; hidden (H) and system (S) ones only with -a or -A.
rc 13 0
expect 13 <<'EOS'
----A  12  2001-01-01 01:00  arch.txt
---D-   0  2001-01-01 01:00  cols
---D-   0  2001-01-01 01:00  dir1
----A  22  2001-01-01 01:00  longfi~1.tex
-----  10  2001-01-01 01:00  normal.txt
----A  20  2001-01-01 01:00  notexe.ext
----A  17  2001-01-01 01:00  prog.exe
R---A  13  2001-01-01 01:00  ra.txt
R----  11  2001-01-01 01:00  rdonly.txt
----A  21  2001-01-01 01:00  readme
----A  19  2001-01-01 01:00  run.bat
---D-   0  2001-01-01 01:00  sizes
---D-   0  2001-01-01 01:00  times
----A  18  2001-01-01 01:00  tool.com
EOS
rc 14 0
expect 14 <<'EOS'
---D-   0                    .
----A  12  2001-01-01 01:00  arch.txt
---D-   0  2001-01-01 01:00  cols
---D-   0  2001-01-01 01:00  dir1
-H--A  14  2001-01-01 01:00  hidden.txt
-H-D-   0  2001-01-01 01:00  hiddir
RHS-A  16  2001-01-01 01:00  hs.txt
----A  22  2001-01-01 01:00  longfi~1.tex
-----  10  2001-01-01 01:00  normal.txt
----A  20  2001-01-01 01:00  notexe.ext
----A  17  2001-01-01 01:00  prog.exe
R---A  13  2001-01-01 01:00  ra.txt
R----  11  2001-01-01 01:00  rdonly.txt
----A  21  2001-01-01 01:00  readme
----A  19  2001-01-01 01:00  run.bat
---D-   0  2001-01-01 01:00  sizes
--SD-   0  2001-01-01 01:00  sysdir
--S-A  15  2001-01-01 01:00  system.txt
---D-   0  2001-01-01 01:00  times
----A  18  2001-01-01 01:00  tool.com
EOS
rc 15 0
norm 14 | sed 1d > a.txt
norm 15 > b.txt
check "step 15: -lA is -la without ." cmp -s a.txt b.txt

# --- a subdirectory: hidden HSUB only with -a or -A, . and .. only
# with -a
rc 16 0
expect 16 <<'EOS'
file.txt
sub
EOS
rc 17 0
expect 17 <<'EOS'
.
..
file.txt
hsub
sub
EOS
rc 18 0
expect 18 <<'EOS'
file.txt
hsub
sub
EOS
rc 19 0
expect 19 <<'EOS'
---D-  0  2001-01-01 01:00  .
---D-  0  2001-01-01 01:00  ..
----A  1  2001-01-01 01:00  in.txt
EOS

# --- -F: / for directories, * for .COM, .EXE and .BAT only
rc 20 0
expect 20 <<'EOS'
arch.txt
cols/
dir1/
longfi~1.tex
normal.txt
notexe.ext
prog.exe*
ra.txt
rdonly.txt
readme
run.bat*
sizes/
times/
tool.com*
EOS
rc 21 0
expect 21 <<'EOS'
./
../
file.txt
hsub/
sub/
EOS

# --- columns, down then across, within 79 of 80 columns
rc 22 0
expect 22 <<'EOS'
f01.txt  f05.txt  f09.txt  f13.txt  f17.txt  f21.txt  f25.txt  f29.txt
f02.txt  f06.txt  f10.txt  f14.txt  f18.txt  f22.txt  f26.txt  f30.txt
f03.txt  f07.txt  f11.txt  f15.txt  f19.txt  f23.txt  f27.txt
f04.txt  f08.txt  f12.txt  f16.txt  f20.txt  f24.txt  f28.txt
EOS
rc 23 0
expect 23 <<'EOS'
arch.txt  dir1/         normal.txt  prog.exe*  rdonly.txt  run.bat*  times/
cols/     longfi~1.tex  notexe.ext  ra.txt     readme      sizes/    tool.com*
EOS
rc 24 0
same 23 24
rc 25 0
expect 25 <<'EOS'
a  bb  cccccccc.txt  d  ee.e  f
EOS
rc 26 0
expect 26 <<'EOS'
f01.txt  f09.txt  f17.txt  f25.txt
f02.txt  f10.txt  f18.txt  f26.txt
f03.txt  f11.txt  f19.txt  f27.txt
f04.txt  f12.txt  f20.txt  f28.txt
f05.txt  f13.txt  f21.txt  f29.txt
f06.txt  f14.txt  f22.txt  f30.txt
f07.txt  f15.txt  f23.txt
f08.txt  f16.txt  f24.txt
EOS
rc 27 0
expect 27 <<'EOS'
a             d
bb            ee.e
cccccccc.txt  f
EOS

# --- display mode precedence
rc 28 0
same 25 28
rc 29 0
expect 29 <<'EOS'
a
bb
cccccccc.txt
d
ee.e
f
EOS
rc 30 0
same 25 30
rc 31 0
expect 31 <<'EOS'
----A  0  2001-01-01 01:00  a
----A  0  2001-01-01 01:00  bb
----A  0  2001-01-01 01:00  cccccccc.txt
----A  0  2001-01-01 01:00  d
----A  0  2001-01-01 01:00  ee.e
----A  0  2001-01-01 01:00  f
EOS
rc 32 0
same 29 32
rc 33 0
same 25 33

# --- sorting.  Equal times (DOS keeps two seconds) are ordered by
# name; -r reverses the whole order, ties included.
rc 40 0
expect 40 <<'EOS'
a_tie.txt
mid.txt
new.txt
old.txt
sec.txt
tie1.txt
tie2.txt
EOS
rc 41 0
expect 41 <<'EOS'
new.txt
sec.txt
a_tie.txt
tie1.txt
tie2.txt
mid.txt
old.txt
EOS
rc 42 0
expect 42 <<'EOS'
tie2.txt
tie1.txt
sec.txt
old.txt
new.txt
mid.txt
a_tie.txt
EOS
rc 43 0
expect 43 <<'EOS'
old.txt
mid.txt
tie2.txt
tie1.txt
a_tie.txt
sec.txt
new.txt
EOS
rc 44 0
expect 44 <<'EOS'
----A  1  2001-01-01 00:00  old.txt
----A  2  2010-06-15 12:30  mid.txt
----A  5  2015-05-05 05:05  tie2.txt
----A  4  2015-05-05 05:05  tie1.txt
----A  6  2015-05-05 05:05  a_tie.txt
----A  7  2015-05-05 05:05  sec.txt
----A  3  2020-12-31 23:58  new.txt
EOS
rc 45 0
same 44 45
rc 46 0
expect 46 <<'EOS'
old.txt
mid.txt
hid.txt
tie2.txt
tie1.txt
a_tie.txt
sec.txt
new.txt
EOS
rc 47 0
same 46 47
rc 48 0
expect 48 <<'EOS'
----A  3  2020-12-31 23:58  new.txt
----A  7  2015-05-05 05:05  sec.txt
----A  6  2015-05-05 05:05  a_tie.txt
----A  4  2015-05-05 05:05  tie1.txt
----A  5  2015-05-05 05:05  tie2.txt
----A  2  2010-06-15 12:30  mid.txt
----A  1  2001-01-01 00:00  old.txt
EOS

# --- sizes; -h rounds up, as POSIX ls -s and GNU ls -h do
rc 50 0
expect 50 <<'EOS'
----A        0  2001-01-01 01:00  a.dat
----A     1023  2001-01-01 01:00  b.dat
----A     1024  2001-01-01 01:00  c.dat
----A     1025  2001-01-01 01:00  d.dat
----A     1536  2001-01-01 01:00  e.dat
----A    10239  2001-01-01 01:00  f.dat
----A    10240  2001-01-01 01:00  g.dat
----A  1048576  2001-01-01 01:00  h.dat
----A  1100000  2001-01-01 01:00  i.dat
EOS
rc 51 0
expect 51 <<'EOS'
----A     0  2001-01-01 01:00  a.dat
----A  1023  2001-01-01 01:00  b.dat
----A  1.0K  2001-01-01 01:00  c.dat
----A  1.1K  2001-01-01 01:00  d.dat
----A  1.5K  2001-01-01 01:00  e.dat
----A   10K  2001-01-01 01:00  f.dat
----A   10K  2001-01-01 01:00  g.dat
----A  1.0M  2001-01-01 01:00  h.dat
----A  1.1M  2001-01-01 01:00  i.dat
EOS
rc 52 0
expect 52 <<'EOS'
a.dat
b.dat
c.dat
d.dat
e.dat
f.dat
g.dat
h.dat
i.dat
EOS

# --- grouped options
rc 53 0
norm 53 > got.txt
check "step 53: -alF" grep -qx -- '---D-   0  2001-01-01 01:00  dir1/' got.txt
rc 54 0
same 53 54
rc 55 0
same 20 55
rc 56 0
same 55 56

# --- -d
rc 60 0
expect 60 <<'EOS'
d:\dir1
d:\normal.txt
EOS
rc 61 0
expect 61 <<'EOS'
d:\dir1/
EOS
rc 62 0
expect 62 <<'EOS'
---D-  0                    d:\
-H-D-  0  2001-01-01 01:00  d:\hiddir
EOS
rc 63 0
expect 63 <<'EOS'
d:\ra.txt
d:\rdonly.txt
d:\readme
d:\run.bat
EOS

# --- -R
rc 64 0
expect 64 <<'EOS'
d:\dir1:
file.txt
sub

d:\dir1\sub:
deep.txt
EOS
rc 65 0
expect 65 <<'EOS'
d:\dir1:
file.txt
hsub
sub

d:\dir1\hsub:
x.txt

d:\dir1\sub:
deep.txt
EOS
rc 66 0
expect 66 <<'EOS'
d:\dir1:
.
..
file.txt
hsub
sub

d:\dir1\hsub:
.
..
x.txt

d:\dir1\sub:
.
..
deep.txt
EOS
rc 67 0
expect 67 <<'EOS'
d:\dir1:
file.txt
sub/

d:\dir1\sub:
deep.txt
EOS

# --- operands
rc 70 0
expect 70 <<'EOS'
d:\normal.txt
d:\readme

d:\dir1:
file.txt
sub
EOS
rc 71 1
expect 71 <<'EOS'
d:\normal.txt
EOS
rc 72 0
expect 72 <<'EOS'
d:\hidden.txt

d:\sysdir:
in.txt
EOS
rc 73 1
expect 73 < /dev/null
rc 74 1
expect 74 < /dev/null

# --- wildcards, matched as DOS does but expanded as a shell would
rc 75 0
expect 75 <<'EOS'
d:\arch.txt
d:\normal.txt
d:\ra.txt
d:\rdonly.txt
EOS
rc 76 0
expect 76 <<'EOS'
d:\arch.txt
d:\hidden.txt
d:\hs.txt
d:\normal.txt
d:\ra.txt
d:\rdonly.txt
d:\system.txt
EOS
rc 77 0
same 63 77
rc 78 0
expect 78 <<'EOS'
d:\tool.com

d:\times:
a_tie.txt
mid.txt
new.txt
old.txt
sec.txt
tie1.txt
tie2.txt
EOS
rc 79 1
expect 79 < /dev/null
rc 80 0
norm 80 > got.txt
check "step 80: -a d:\\* has hidden files" grep -qx 'd:\\hs.txt' got.txt
check "step 80: no volume label" sh -c '! grep -qi lstest got.txt'
check "step 80: no . or .. from a wildcard" sh -c '! grep -qx "d:\\\\\.\.*" got.txt'
rc 81 0
expect 81 <<'EOS'
deep.txt
EOS

# --- options after operands, and across drives
rc 82 0
same 41 82
rc 83 0
same 44 83
rc 84 0
expect 84 <<'EOS'
c:\cwd:
alpha.txt
beta
sub/
zeta.txt

d:\dir1:
file.txt
sub/
EOS
rc 85 0
same 41 85
rc 86 0
expect 86 <<'EOS'
----A  1  2001-01-01 00:00  d:old.txt
EOS
rc 87 0
same 40 87
rc 88 0
expect 88 <<'EOS'
.
..
a_tie.txt
hid.txt
mid.txt
new.txt
old.txt
sec.txt
tie1.txt
tie2.txt
EOS
rc 89 0
same 20 89
rc 90 0
expect 90 <<'EOS'
alpha.txt
beta
sub/
zeta.txt
EOS
rc 91 0
same 11 91
rc 92 0
expect 92 <<'EOS'
---D-  0                    .
EOS
rc 93 0
expect 93 <<'EOS'
alpha.txt
beta
sub
zeta.txt
EOS
rc 94 0
expect 94 <<'EOS'
inner.txt
EOS
rc 95 0
expect 95 <<'EOS'
.
..
EOS

rc 100 0
norm 100 > got.txt
check "step 100: 32 directories" test "$(grep -c ':$' got.txt)" = 32
check "step 100: the bottom" test "$(tail -n 1 got.txt)" = bottom.txt

# --- the console
same 22 96
same 23 97
same 29 98
same 26 99

# ------------------------------------------------------------------

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ] || [ "${KEEP:-0}" = 1 ]; then
    echo "work directory: $work"
else
    rm -rf "$work"
fi
[ "$fail" -eq 0 ]
