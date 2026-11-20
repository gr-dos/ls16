# ls16

A POSIX-style `ls` for 16-bit MS-DOS and GR-DOS: an alternative to
`DIR` with familiar `ls` options, adapted to DOS file attributes. Built
with Open Watcom and [libc16](https://github.com/gr-dos/libc16).

The resulting `ls.exe` is a small-model, real-mode 8086 executable
(about 10 KB) that runs on any DOS from an original PC up, including
XT-class machines such as the NuXT.

## Usage

    ls [-aACdFhlrRt1] [FILE]...

| Option | Meaning |
| --- | --- |
| `-a` | all entries: hidden and system ones, and `.` and `..` |
| `-A` | hidden and system entries, but not `.` and `..` |
| `-C` | names in columns, down then across (the default on the screen) |
| `-1` | one name a line (the default when redirected) |
| `-l` | long listing: attributes, size, date and time, name |
| `-h` | with `-l`, human-readable sizes (`1.5K`, `23M`) |
| `-F` | append `/` to directories and `*` to `.COM`, `.EXE` and `.BAT` files |
| `-d` | list directories themselves, not their contents |
| `-R` | list subdirectories recursively |
| `-t` | sort by date and time last modified, newest first |
| `-r` | reverse the order of the sort |
| `--help`, `-?` | show help |
| `--version` | show version |
| `--` | treat the remaining arguments as operands |

Every single-letter option can be grouped with the others in any
combination (`-ltr` is `-l -t -r`, `-CF` is `-C -F`), and options may
come before or after the operands (`ls C:\DOS -l`). Options are
case-sensitive, as in POSIX: `-a` and `-A`, `-r` and `-R` differ.

FILE may have a drive, a path and the wildcards `*` and `?`:
`ls`, `ls C:\DOS`, `ls -l A:`, `ls ..\*.TXT`, `ls -ltr D:\GAMES *.BAT`.
`/` is accepted as well as `\`.

The exit status is 0 on success and 1 if an operand was not found, a
directory could not be read, or an option was not valid.

GR-DOS's `HELP LS` topic is [`help/topics/LS.txt`](help/topics/LS.txt).

## Behaviour

POSIX `ls` is the baseline. What follows is where DOS differs, and
the choices POSIX leaves open.

**Names** are shown in lower case, including the upper-case names DOS
returns. Nothing on the disk is renamed. Operands are shown as typed,
lower-cased, with `/` shown as `\`.

**Visibility.** DOS has no dot files; its Hidden (`H`, 0x02) and System
(`S`, 0x04) attributes play their part.

| | default | `-A` | `-a` |
| --- | --- | --- | --- |
| ordinary files and directories, including read-only (`R`) and archive (`A`) | yes | yes | yes |
| Hidden or System entries (files or directories, whatever other bits are set) | no | yes | yes |
| `.` and `..` | no | no | yes |
| the volume label (0x08) | no | no | no |
| VFAT long-name slots (0x0F) | no | no | no |

A name starting with `.` gets no special treatment. A file or
directory named on the command line is always listed, hidden or not, as
POSIX `ls` lists a dot file it is given.

**`.` and `..`** with `-a` are DOS's own entries in a subdirectory. A
drive's root directory has none on the disk, so `ls -a` lists a `.`
for it and no `..`, since a root has no parent (`CD ..` fails there). If
a file system leaves them out of a subdirectory, ls adds them itself.

**Long listing (`-l`):**

    RHS-A  1.5K  1994-05-31 06:22  io.sys
    ---D-     0  2001-01-01 01:00  dos
    R---A    13  2001-01-01 01:00  readme.txt

- The attributes, always five positions in the order `R`, `H`, `S`,
  `D`, `A` (read-only, hidden, system, directory, archive), with `-` for
  one not set. There are no Unix permission bits, link counts, owners or
  groups, and no `total` line.
- The size in bytes, right-aligned to the widest in the listing, as DOS
  reports it (0 for a directory on FAT). With `-h`, sizes of 1024 bytes
  or more are shown in K, M or G (powers of 1024), with one decimal below
  10, rounded up, as GNU `ls -h` does: `1.0K`, `1.5K`, `10K`, `1.1M`.
- The date and time last modified, `YYYY-MM-DD HH:MM`, the same width
  for every entry whatever its age. A root directory has no directory
  entry and so no date: its date and time are left blank.
- The name, with the `-F` suffix if asked for.

**`-F`** appends `/` to directories (the DOS Directory attribute) and `*`
to files whose extension is `.COM`, `.EXE` or `.BAT`, in any case. That
is a heuristic: DOS has no executable attribute. Nothing else is marked;
DOS has no symbolic links, sockets or FIFOs.

**Display modes.** Of `-C`, `-1` and `-l`, the last given wins, read
left to right: `-1C` and `-lC` list in columns, `-C1` one a line, `-Cl`
in long form. With none of them, ls lists in columns when standard
output is the console (INT 21h 4400h: a character device that is the
console output), and one a line otherwise (redirected to a file, a pipe,
`NUL` or `PRN`). `-C` always means columns, redirected too.

**Columns** are filled down then across, as many as fit, two spaces
apart, each as wide as its longest name. The width is the `COLUMNS`
environment variable if set, else the screen's (the BIOS's column
count, so 40-column modes work), else 80. Lines are kept one character
shorter than the width, since DOS moves the cursor to the next line after
writing in the last column, and that would leave blank lines.

**Sorting.** By name, in character order of the lower-cased name, so
the order is the same whatever case DOS returned. Operands are sorted
by their names as typed. `-t` sorts by the DOS date and time, newest
first; entries with equal times (DOS keeps time to two seconds) are
then sorted by name. `-r` reverses the whole order, ties included, so
`ls -ltr` lists the oldest first and the newest last, and equal times in
reverse name order. A root, with no date, sorts as the oldest.

**Operands.** As in POSIX: files (and, with `-d`, directories) are
listed first, together, then each directory's contents. With more than
one operand, or with `-R`, each directory's listing starts with its name
and a colon, and listings are separated by a blank line. An operand that
does not exist is reported on standard error and the others are still
listed. `C:` is drive C's current directory and `C:\` its root, as in
DOS.

**Wildcards.** DOS has no shell globbing, so ls expands wildcard
operands itself, as a shell would: each match is an operand, and a
directory that matches is listed with its contents unless `-d` is given
(`ls D:\T*` lists `D:\TOOL.COM` and what is in `D:\TEMP`). Matching is
DOS's own (INT 21h 4Eh), with one change: a `*` in the last component
with no `.` after it matches extensions too, as on Unix, so `ls *` is
`ls *.*` and `ls A*` matches `ABC.TXT`. A match is listed only if `ls`
would list it in a directory (hidden and system ones only with `-a` or
`-A`), and `.` and `..` never match. A wildcard that matches nothing is
reported as not found.

**`-R`** lists each directory and then, in the listing's order, each of
its subdirectories that it showed, recursively; `.` and `..` are never
followed. Subdirectories of `.` are named `sub`, `sub\deep`, and so on.

**Memory and speed.** ls reads a directory's entries into memory to
sort them, 28 bytes each, in the small model's 64 KB data segment: about
2,000 entries in one directory. A larger directory is reported (`too
many entries`, exit status 1) and the entries read are listed. While
recursing, only the subdirectories' names are kept for each level. The
stack is 4 KB, enough for DOS's deepest paths. Entries are sorted with
a Shell sort of pointers to them, and output is written a 512-byte
buffer at a time: in DOSBox-X at about the speed of a 4.77 MHz 8088, a
directory of 1,889 files lists in about 11 seconds (`ls -1`) to 18
(`ls -l`), and one of a hundred files in under a second.

## Building and testing

ls follows the [hello16](https://github.com/gr-dos/hello16) conventions,
in its layout 1 (C only).

    make                         # fetches libc16 if needed, builds ls.exe
    make LIBC16_ROOT=../libc16   # or use a built local libc16 checkout
    make test                    # checks the help topic, then the DOS tests
    make dist                    # the release ZIP, ls16-VERSION.zip
    make clean

`ls.exe` links [libc16](https://github.com/gr-dos/libc16), a C runtime
for small-model DOS programs, instead of Open Watcom's own, and is built
with the Open Watcom toolchain that libc16 pins. By default `make` runs
`scripts/fetch-libc16`, which downloads the libc16 release pinned in
that script (`libc16-VERSION.zip`), checks it against the SHA-256
written there before unpacking it, and unpacks it into `build/libc16`.
The release's `tools/fetch-watcom` then fetches the Open Watcom snapshot
libc16 was built with into `build/tools`, also checked by SHA-256. This
needs `curl`, `unzip`, `sha256sum` and `xz`. To move to a newer libc16,
set `version` and `sha256` in `scripts/fetch-libc16` to the new
release's (its `.sha256` asset), both in the same change.

`make test` runs `tests/run.sh` under DOSBox-X (`dosbox-x`, override
with `DOSBOX=`; set `KEEP=1` to keep the work directory). It needs
`mtools`, to build the FAT floppy image mounted as `D:`, whose files
have DOS attributes (read-only, hidden, system, archive, on files and
directories), a volume label, a VFAT long name and exact dates, and
`nasm`, for `tests/scrdump.asm`, which reads ls's console output back
from video memory to test the default columns at 80 and 40 columns.
`scripts/check-help` checks the help topic the way GR-DOS's
`scripts/mkhelp` does: ASCII, lines of at most 79 characters, and the
header.

## Releases

`main` is protected: it changes only through a pull request whose `ci`
workflow's `test` check passes, for administrators too, with no force
pushes or deletion.

The version is the one line in `VERSION`, DOS style (0.01, 0.02, ...
1.00), not semantic versioning; `ls --version` prints it. When a pull
request that changes it is merged, the release workflow tags the merge
commit `v<VERSION>` and publishes a GitHub release with:

- `ls.exe`, the program, and
- `ls16-VERSION.zip`, holding `ls.exe`, the GR-DOS help topic at
  `help/topics/LS.txt` (gr-dos/gr-dos#90), `LICENSE` and `README.md`.

## Files

- `ls.c`: the program
- `Makefile`: the Open Watcom and libc16 build
- `scripts/fetch-libc16`: fetch the pinned libc16 release
- `scripts/check-help`: check the help topic
- `help/topics/LS.txt`: the GR-DOS `HELP LS` topic
- `VERSION`: the version, compiled in and printed by `--version`
- `tests/run.sh`: the test suite, run under DOSBox-X by `make test`
- `tests/scrdump.asm`: writes the text screen to standard output, for
  the tests
- `.github/workflows/ci.yml`: build and test on PRs and pushes to `main`
- `.github/workflows/release.yml`: tag and release when `VERSION` changes

## License

MIT. See `LICENSE`.
