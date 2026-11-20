/*
 * ls - list directory contents, POSIX style, for 16-bit DOS
 *
 * Open Watcom C with libc16, small model, 8086.  See README.md for the
 * behaviour and help/topics/LS.txt for the GR-DOS help topic.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dos.h>

#ifndef VERSION
#define VERSION   "unknown"
#endif

#define PATHMAX   160               /* longest operand or path built */
#define CHUNK     64                /* entries added at a time */

#define ATTR_LFN  0x0F              /* a VFAT long-name slot */
#define SEARCH    (_A_HIDDEN | _A_SYSTEM | _A_SUBDIR)

/* An entry to show: a directory's entry (path is null) or an operand
 * (path is the operand as typed, lower-cased, and is what is shown). */
struct ent {
    unsigned long size;
    unsigned date, time;
    char *path;
    unsigned char attr;
    unsigned char nodate;           /* date and time unknown (a root) */
    unsigned char len;              /* shown length, with any suffix */
    char name[13];
};

/* A growable array of entries, and after sort() ix, pointers to them in
 * order: sorting 2-byte pointers rather than whole entries is much
 * quicker on an 8088.  Both are one block, the pointers after cap
 * entries, so that the block grows in place at the top of the heap. */
struct list {
    struct ent *e;
    struct ent **ix;
    unsigned n, cap;
};

/* Options */
static char mode;                   /* 'C', '1' or 'l'; 0 for the default */
static char all;                    /* 0, 'A' or 'a' */
static char opt_d, opt_F, opt_h, opt_R, opt_r, opt_t;

static int status;                  /* the exit status */
static int printed;                 /* something is on stdout already */
static char pathbuf[PATHMAX];
static char outbuf[512];            /* standard output, see out() */
static unsigned outlen;
static char write_failed;

/* ------------------------------------------------------------------ */
/* output */

/* Standard output is buffered here and written with INT 21h 40h, a
 * buffer at a time, with each \n written as CR LF: on an 8088, writing
 * through stdio a byte at a time took longer than reading and sorting a
 * directory. */
static void flush_out(void)
{
    unsigned done;

    if (outlen && !write_failed &&
        (_dos_write(1, outbuf, outlen, &done) != 0 || done != outlen)) {
        write_failed = 1;
        fputs("ls: write error\n", stderr);
        status = 1;
    }
    outlen = 0;
}

static void outc(char c)
{
    if (c == '\n') {
        if (outlen >= sizeof outbuf - 1)
            flush_out();
        outbuf[outlen++] = '\r';
    } else if (outlen == sizeof outbuf) {
        flush_out();
    }
    outbuf[outlen++] = c;
}

static void out(const char *s)
{
    for (; *s; s++) {
        if (*s == '\n' || outlen == sizeof outbuf) {
            outc(*s);
        } else {
            outbuf[outlen++] = *s;
        }
    }
}

static void spaces(int n)
{
    static const char sp[] = "                ";     /* 16 */

    for (; n > 16; n -= 16)
        out(sp);
    if (n > 0)
        out(sp + 16 - n);
}

/* "ls: WHAT: WHY", after what stdout holds, and the status set to 1 */
static void error(const char *what, const char *why)
{
    flush_out();
    fputs("ls: ", stderr);
    fputs(what, stderr);
    fputs(": ", stderr);
    fputs(why, stderr);
    fputs("\n", stderr);
    status = 1;
}

static void bad_option(const char *what, const char *arg)
{
    fputs("ls: ", stderr);
    fputs(what, stderr);
    fputs(" '", stderr);
    fputs(arg, stderr);
    fputs("'\nTry 'ls --help' for more information.\n", stderr);
}

static void usage(void)
{
    out("Usage: ls [OPTION]... [FILE]...\n"
        "List information about the FILEs (the current directory by default),\n"
        "sorted by name.  Names are shown in lower case.\n"
        "\n"
        "  -a   all entries: hidden and system ones, and . and ..\n"
        "  -A   hidden and system entries, but not . and ..\n"
        "  -C   names in columns, down then across (default on the screen)\n"
        "  -1   one name a line (default when redirected)\n"
        "  -l   long listing: attributes RHSDA, size, date and time, name\n"
        "  -h   with -l, sizes as 1.5K, 23M and so on\n"
        "  -F   append / to directories and * to .COM, .EXE and .BAT files\n"
        "  -d   list directories themselves, not their contents\n"
        "  -R   list subdirectories recursively\n"
        "  -t   sort by date and time last modified, newest first\n"
        "  -r   reverse the order of the sort\n"
        "      --help     display this help and exit\n"
        "      --version  output version information and exit\n"
        "\n"
        "Options may be grouped (-ltr) and may follow FILEs; of -C, -1 and -l\n"
        "the last given wins.  FILE may have a drive, a path and the wildcards\n"
        "* and ?.  Exit status: 0 if OK, 1 if a FILE was not found or an\n"
        "option was bad.\n");
}

/* ------------------------------------------------------------------ */
/* entries */

static void lower(char *s)
{
    for (; *s; s++)
        if (*s >= 'A' && *s <= 'Z')
            *s += 'a' - 'A';
}

static const char *shown(const struct ent *e)
{
    return e->path ? e->path : e->name;
}

/* The last component of a path, for -F */
static const char *base(const char *p)
{
    const char *b = p;

    for (; *p; p++)
        if (*p == '\\' || *p == ':')
            b = p + 1;
    return b;
}

static int is_exec(const char *name)
{
    const char *dot = strrchr(base(name), '.');

    return dot && (stricmp(dot, ".com") == 0 || stricmp(dot, ".exe") == 0 ||
                   stricmp(dot, ".bat") == 0);
}

/* -F's suffix for an entry, or 0 */
static char suffix(const struct ent *e)
{
    if (!opt_F)
        return 0;
    if (e->attr & _A_SUBDIR)
        return '/';
    if (is_exec(shown(e)))
        return '*';
    return 0;
}

/* A new entry at the end of l, zeroed; null when memory has run out */
static struct ent *add(struct list *l)
{
    struct ent *e;

    if (l->n == l->cap) {
        unsigned cap = l->cap + CHUNK;
        struct ent *ne;

        if (cap > 0xFFF0u / (sizeof *ne + sizeof *l->ix))
            return 0;
        ne = realloc(l->e, cap * (sizeof *ne + sizeof *l->ix));
        if (!ne)
            return 0;
        l->e = ne;
        l->cap = cap;
    }
    e = &l->e[l->n++];
    memset(e, 0, sizeof *e);
    return e;
}

static void from_find(struct ent *e, const struct find_t *f)
{
    e->size = f->size;
    e->date = f->wr_date;
    e->time = f->wr_time;
    e->attr = f->attrib;
    strcpy(e->name, f->name);
    lower(e->name);
}

static void free_list(struct list *l)
{
    unsigned i;

    for (i = 0; i < l->n; i++)
        free(l->e[i].path);
    free(l->e);
    l->e = 0;
    l->ix = 0;
    l->n = l->cap = 0;
}

static int is_dots(const char *name)
{
    return name[0] == '.' && (name[1] == 0 || (name[1] == '.' && name[2] == 0));
}

/* Whether a directory search's entry is shown: never a volume label or
 * a long-name slot; . and .. only with -a; hidden and system entries
 * only with -a or -A. */
static int visible(const struct find_t *f, int dots)
{
    if ((f->attrib & ATTR_LFN) == ATTR_LFN || (f->attrib & _A_VOLID))
        return 0;
    if (is_dots(f->name))
        return dots && all == 'a';
    if (f->attrib & (_A_HIDDEN | _A_SYSTEM))
        return all != 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/* sorting */

/* Whether a sorts after b: by name, or with -t newest first and then by
 * name; -r reverses the whole order.  A root, with no date, has date and
 * time 0, the oldest. */
static int after(const struct ent *a, const struct ent *b)
{
    int r = 0;

    if (opt_t) {
        if (a->date != b->date)
            r = a->date > b->date ? -1 : 1;
        else if (a->time != b->time)
            r = a->time > b->time ? -1 : 1;
    }
    if (r == 0)
        r = strcmp(shown(a), shown(b));     /* already lower case */
    return opt_r ? r < 0 : r > 0;
}

/* Sorts l into l->ix.  A Shell sort of the pointers (Ciura's gaps): no
 * memory beyond them, and on an 8088 quicker than libc16's heapsort,
 * which exchanges elements a byte at a time and multiplies to index
 * them.  Names in one directory differ, so its order is total. */
static void sort(struct list *l)
{
    static const unsigned gaps[] = { 1750, 701, 301, 132, 57, 23, 10, 4, 1 };
    struct ent **ix = (struct ent **)(l->e + l->cap);
    unsigned g, i, j, k;

    l->ix = ix;
    for (i = 0; i < l->n; i++)
        ix[i] = &l->e[i];
    for (k = 0; k < sizeof gaps / sizeof gaps[0]; k++) {
        g = gaps[k];
        for (i = g; i < l->n; i++) {
            struct ent *t = ix[i];

            for (j = i; j >= g && after(ix[j - g], t); j -= g)
                ix[j] = ix[j - g];
            ix[j] = t;
        }
    }
}

/* ------------------------------------------------------------------ */
/* formats */

/* Two digits of n at p */
static char *put2(char *p, unsigned n)
{
    *p++ = (char)('0' + n / 10 % 10);
    *p++ = (char)('0' + n % 10);
    return p;
}

/* v in decimal in buf: 16-bit division when it fits, since the 32-bit
 * division helper is slow on an 8088 */
static char *decimal(unsigned long v, char *buf)
{
    char tmp[12], *t = tmp + sizeof tmp - 1;
    unsigned w;

    *t = 0;
    while (v > 0xFFFFu) {
        *--t = (char)('0' + (unsigned)(v % 10));
        v /= 10;
    }
    w = (unsigned)v;
    do {
        *--t = (char)('0' + w % 10);
        w /= 10;
    } while (w);
    strcpy(buf, t);
    return buf;
}

/* The size as -l shows it, in buf */
static char *size_text(unsigned long size, char *buf)
{
    static const char units[] = "KMG";
    unsigned long div = 1024, q, r;
    int u = 0;
    char *p;

    if (!opt_h || size < 1024)
        return decimal(size, buf);

    while (u < 2 && size / div >= 1024) {
        div <<= 10;
        u++;
    }
    q = size / div;
    r = size % div;
    if (q < 10) {
        /* one decimal, rounded up: tenths of div in the remainder */
        unsigned long low = div >> 10;      /* r / low < 1024 */
        unsigned long t10 = r / low * 10;
        unsigned tenths = (unsigned)(t10 / 1024);

        if (t10 % 1024 || r % low)
            tenths++;
        if (tenths == 10) {
            q++;
            tenths = 0;
        }
        if (q < 10) {
            p = decimal(q, buf);
            p += strlen(p);
            *p++ = '.';
            *p++ = (char)('0' + tenths);
            *p++ = units[u];
            *p = 0;
            return buf;
        }
    } else if (r) {
        q++;                                /* rounded up */
    }
    if (q >= 1024 && u < 2) {
        q = 1;
        u++;
        strcpy(buf, "1.0");
        buf[3] = units[u];
        buf[4] = 0;
        return buf;
    }
    p = decimal(q, buf);
    p += strlen(p);
    *p++ = units[u];
    *p = 0;
    return buf;
}

static void put_name(const struct ent *e)
{
    char s = suffix(e);

    out(shown(e));
    if (s)
        outc(s);
}

static void print_long(const struct list *l)
{
    char buf[16], line[40];
    unsigned i;
    int w = 1;

    for (i = 0; i < l->n; i++) {
        int n = (int)strlen(size_text(l->ix[i]->size, buf));

        if (n > w)
            w = n;
    }
    for (i = 0; i < l->n; i++) {
        const struct ent *e = l->ix[i];
        unsigned char a = e->attr;
        char *p = line;

        *p++ = a & _A_RDONLY ? 'R' : '-';
        *p++ = a & _A_HIDDEN ? 'H' : '-';
        *p++ = a & _A_SYSTEM ? 'S' : '-';
        *p++ = a & _A_SUBDIR ? 'D' : '-';
        *p++ = a & _A_ARCH ? 'A' : '-';
        *p = 0;
        out(line);
        size_text(e->size, buf);
        spaces(2 + w - (int)strlen(buf));
        out(buf);
        p = line;
        *p++ = ' ';
        *p++ = ' ';
        if (e->nodate) {
            memset(p, ' ', 16);
            p += 16;
        } else {
            unsigned y = 1980 + (e->date >> 9);

            p = put2(p, y / 100);
            p = put2(p, y);
            *p++ = '-';
            p = put2(p, (e->date >> 5) & 15);
            *p++ = '-';
            p = put2(p, e->date & 31);
            *p++ = ' ';
            p = put2(p, e->time >> 11);
            *p++ = ':';
            p = put2(p, (e->time >> 5) & 63);
        }
        *p++ = ' ';
        *p++ = ' ';
        *p = 0;
        out(line);
        put_name(e);
        outc('\n');
    }
}

/* Whether standard output is the console (a character device that is
 * the standard output device) */
static int console(void)
{
    union REGS r;

    r.x.ax = 0x4400;
    r.x.bx = 1;
    intdos(&r, &r);
    return !r.x.cflag && (r.x.dx & 0x82) == 0x82;
}

/* The screen's width: COLUMNS if set, else the BIOS's for the console,
 * else 80. */
static int width(void)
{
    const char *c = getenv("COLUMNS");

    if (c) {
        int n = atoi(c);

        if (n > 0)
            return n > 255 ? 255 : n;
    }
    if (console()) {
        unsigned cols = *(unsigned __far *)MK_FP(0x40, 0x4A);

        if (cols >= 20 && cols <= 255)
            return (int)cols;
    }
    return 80;
}

/* Columns, sorted down then across, in as few rows as fit in one less
 * than the screen's width (DOS moves the cursor to the next line after
 * writing the last column), two spaces between columns. */
static void print_columns(const struct list *l)
{
    unsigned char w[128];               /* each column's width */
    unsigned n = l->n, rows, cols, r, c, i;
    unsigned long sum = 0;
    int max = width() - 1;

    if (n == 0)
        return;
    /* Fewer rows cannot fit: a column is at least as wide as the mean
     * of its names, so the names' total length over rows, plus two
     * between each of the n / rows columns, is at most max. */
    for (i = 0; i < n; i++)
        sum += l->ix[i]->len + 2;
    rows = (unsigned)((sum + max + 1) / (max + 2));
    if (rows < 1)
        rows = 1;
    for (; rows < n; rows++) {
        int total = -2;

        cols = (n + rows - 1) / rows;
        if (cols > sizeof w)
            continue;
        for (c = 0; c < cols && total <= max; c++) {
            unsigned char cw = 0;

            for (i = c * rows; i < n && i < (c + 1) * rows; i++)
                if (l->ix[i]->len > cw)
                    cw = l->ix[i]->len;
            w[c] = cw;
            total += cw + 2;
        }
        if (total <= max)
            break;
    }
    if (rows >= n) {                    /* one column */
        rows = n;
        w[0] = 0;
    }
    cols = (n + rows - 1) / rows;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++) {
            i = c * rows + r;
            if (i >= n)
                break;
            put_name(l->ix[i]);
            if (i + rows < n)
                spaces(w[c] + 2 - l->ix[i]->len);
        }
        outc('\n');
    }
}

static void print_list(struct list *l)
{
    unsigned i;

    for (i = 0; i < l->n; i++) {
        struct ent *e = l->ix[i];
        size_t n = strlen(shown(e)) + (suffix(e) ? 1 : 0);

        e->len = (unsigned char)(n > 255 ? 255 : n);
    }
    if (mode == 'l')
        print_long(l);
    else if (mode == 'C')
        print_columns(l);
    else
        for (i = 0; i < l->n; i++) {
            put_name(l->ix[i]);
            outc('\n');
        }
    if (l->n)
        printed = 1;
}

/* ------------------------------------------------------------------ */
/* paths */

/* Whether path p of length n needs a \ before a name is added */
static int needs_sep(const char *p, size_t n)
{
    return n && p[n - 1] != '\\' && p[n - 1] != ':';
}

/* Looks up path's own entry: 0 and *e filled in, or -1 if it does not
 * exist.  A root has no entry, so it is a directory with no date. */
static int stat_path(const char *path, struct ent *e)
{
    char full[PATHMAX];
    struct find_t f;

    if (!_fullpath(full, path, sizeof full))
        return -1;
    if (strlen(full) == 3) {                /* X:\ */
        unsigned rc;

        strcat(full, "*.*");
        rc = _dos_findfirst(full, SEARCH, &f);
        if (rc != 0 && rc != 2 && rc != 18)
            return -1;
        e->attr = _A_SUBDIR;
        e->nodate = 1;
        e->size = 0;
        return 0;
    }
    if (strpbrk(full, "*?") || _dos_findfirst(full, SEARCH, &f))
        return -1;
    e->size = f.size;
    e->date = f.wr_date;
    e->time = f.wr_time;
    e->attr = f.attrib;
    e->nodate = 0;
    return 0;
}

/* Adds . or .. to l, for -a, when DOS did not list it.  A root has
 * no parent, so no .. is added there. */
static void add_dots(struct list *l, const char *dir, size_t n, const char *dots)
{
    struct ent *e;
    char full[PATHMAX];

    if (n + 4 > sizeof full)
        return;
    memcpy(full, dir, n);
    if (needs_sep(full, n))
        full[n++] = '\\';
    strcpy(full + n, dots);
    if (dots[1]) {
        char abs[PATHMAX];

        if (!_fullpath(abs, n ? dir : ".", sizeof abs) || strlen(abs) == 3)
            return;
    }
    e = add(l);
    if (!e)
        return;
    if (stat_path(full, e) != 0)
        e->nodate = 1;
    e->attr |= _A_SUBDIR;
    strcpy(e->name, dots);
}

/* Lists the directory in pathbuf[0..n), and with -R its subdirectories */
static void list_dir(size_t n)
{
    static struct find_t f;             /* searches never overlap */
    struct list l = { 0, 0, 0, 0 };
    unsigned rc;
    int dot = 0, dotdot = 0, full = 0;
    char *names;
    unsigned i, k;

    if (n + (needs_sep(pathbuf, n) ? 1 : 0) + 4 > sizeof pathbuf) {
        pathbuf[n] = 0;
        error(pathbuf, "path too long");
        return;
    }
    {
        size_t m = n;

        if (needs_sep(pathbuf, m))
            pathbuf[m++] = '\\';
        strcpy(pathbuf + m, "*.*");
    }
    for (rc = _dos_findfirst(pathbuf, SEARCH, &f); rc == 0;
         rc = _dos_findnext(&f)) {
        struct ent *e;

        if (!visible(&f, 1))
            continue;
        if (f.name[0] == '.' && f.name[1] == 0)
            dot = 1;
        else if (is_dots(f.name))
            dotdot = 1;
        e = add(&l);
        if (!e) {
            full = 1;
            break;
        }
        from_find(e, &f);
    }
    pathbuf[n] = 0;
    if (rc != 0 && rc != 2 && rc != 18 && !full) {
        error(n ? pathbuf : ".", "cannot read directory");
        free_list(&l);
        return;
    }
    if (all == 'a' && !full) {
        if (!dot)
            add_dots(&l, pathbuf, n, ".");
        if (!dotdot)
            add_dots(&l, pathbuf, n, "..");
    }
    if (full)
        error(n ? pathbuf : ".", "too many entries; listing those read");
    sort(&l);
    print_list(&l);
    flush_out();

    if (!opt_R) {
        free_list(&l);
        return;
    }
    /* keep only the subdirectories' names while recursing */
    for (i = k = 0; i < l.n; i++)
        if ((l.ix[i]->attr & _A_SUBDIR) && !is_dots(l.ix[i]->name))
            k++;
    names = k ? malloc(k * 13) : 0;
    if (k && !names) {
        error(pathbuf, "out of memory");
        free_list(&l);
        return;
    }
    for (i = k = 0; i < l.n; i++)
        if ((l.ix[i]->attr & _A_SUBDIR) && !is_dots(l.ix[i]->name))
            strcpy(names + 13 * k++, l.ix[i]->name);
    free_list(&l);
    for (i = 0; i < k; i++) {
        size_t m = n;

        if (needs_sep(pathbuf, m))
            pathbuf[m++] = '\\';
        if (m + strlen(names + 13 * i) >= sizeof pathbuf) {
            pathbuf[n] = 0;
            error(pathbuf, "path too long");
            continue;
        }
        strcpy(pathbuf + m, names + 13 * i);
        outc('\n');
        out(pathbuf);
        out(":\n");
        printed = 1;
        list_dir(strlen(pathbuf));
        pathbuf[n] = 0;
    }
    free(names);
}

/* ------------------------------------------------------------------ */
/* operands */

static struct list files, dirs;
static unsigned operands;           /* how many, after wildcards */

/* Files go in files, directories in dirs (or files, with -d) */
static int add_operand(const char *path, const struct ent *meta)
{
    struct list *l = (meta->attr & _A_SUBDIR) && !opt_d ? &dirs : &files;
    struct ent *e = add(l);

    operands++;
    if (!e || !(e->path = strdup(path))) {
        if (e)
            l->n--;
        error(path, "out of memory");
        return -1;
    }
    e->size = meta->size;
    e->date = meta->date;
    e->time = meta->time;
    e->attr = meta->attr;
    e->nodate = meta->nodate;
    return 0;
}

/* Expands a wildcard operand as a shell would, but with DOS's matching
 * and attributes */
static void expand(const char *op)
{
    char pat[PATHMAX], path[PATHMAX];
    const char *b = base(op);
    size_t pre = (size_t)(b - op);
    struct find_t f;
    struct ent meta;
    unsigned rc;
    int found = 0;

    if (strlen(op) + 3 > sizeof pat) {
        operands++;
        error(op, "path too long");
        return;
    }
    strcpy(pat, op);
    /* "*" and "foo*" match names with extensions too, as on Unix */
    if (strchr(b, '*') && !strchr(b, '.'))
        strcat(pat, ".*");
    memcpy(path, op, pre);
    for (rc = _dos_findfirst(pat, SEARCH, &f); rc == 0;
         rc = _dos_findnext(&f)) {
        if (!visible(&f, 0))
            continue;
        lower(f.name);
        if (pre + strlen(f.name) >= sizeof path)
            continue;
        strcpy(path + pre, f.name);
        memset(&meta, 0, sizeof meta);
        meta.size = f.size;
        meta.date = f.wr_date;
        meta.time = f.wr_time;
        meta.attr = f.attrib;
        found = 1;
        if (add_operand(path, &meta))
            break;
    }
    if (!found) {
        operands++;
        error(op, "No such file or directory");
    }
}

static void operand(char *op)
{
    struct ent meta;
    char *s;

    for (s = op; *s; s++)
        if (*s == '/')
            *s = '\\';
    lower(op);
    if (strlen(op) >= PATHMAX) {
        operands++;
        error(op, "path too long");
        return;
    }
    if (strpbrk(op, "*?")) {
        expand(op);
        return;
    }
    memset(&meta, 0, sizeof meta);
    if (stat_path(op, &meta) != 0) {
        operands++;
        error(op, "No such file or directory");
        return;
    }
    add_operand(op, &meta);
}

/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
    int i, opts_done = 0, nops = 0;
    unsigned j;

    /* options first, wherever they are; "--" ends them */
    for (i = 1; i < argc; i++) {
        const char *a = argv[i];

        if (opts_done || a[0] != '-' || a[1] == 0) {
            nops++;
            continue;
        }
        if (a[1] == '-') {
            if (a[2] == 0) {
                opts_done = 1;
            } else if (strcmp(a, "--help") == 0) {
                usage();
                flush_out();
                return 0;
            } else if (strcmp(a, "--version") == 0) {
                out("ls (ls16) " VERSION "\n");
                flush_out();
                return 0;
            } else {
                bad_option("unrecognized option", a);
                return 1;
            }
            continue;
        }
        for (a++; *a; a++) {
            switch (*a) {
            case 'a': case 'A': all = *a; break;
            case 'C': case '1': case 'l': mode = *a; break;
            case 'd': opt_d = 1; break;
            case 'F': opt_F = 1; break;
            case 'h': opt_h = 1; break;
            case 'R': opt_R = 1; break;
            case 'r': opt_r = 1; break;
            case 't': opt_t = 1; break;
            case '?': usage(); flush_out(); return 0;
            default: {
                char bad[3];

                bad[0] = '-';
                bad[1] = *a;
                bad[2] = 0;
                bad_option("invalid option", bad);
                return 1;
            }
            }
        }
    }
    if (!mode)
        mode = console() ? 'C' : '1';

    opts_done = 0;
    for (i = 1; i < argc; i++) {
        char *a = argv[i];

        if (!opts_done && a[0] == '-' && a[1] != 0) {
            if (strcmp(a, "--") == 0)
                opts_done = 1;
            continue;
        }
        operand(a);
    }
    if (nops == 0) {
        static char dot[] = ".";

        operand(dot);
    }

    sort(&files);
    print_list(&files);
    sort(&dirs);
    for (j = 0; j < dirs.n; j++) {
        const char *p = dirs.ix[j]->path;

        if (printed)
            outc('\n');
        if (operands > 1 || opt_R) {
            out(p);
            out(":\n");
            printed = 1;
        }
        strcpy(pathbuf, p);
        /* "." is listed as the current directory, so its subdirectories
         * are "sub" rather than ".\\sub" */
        list_dir(strcmp(p, ".") == 0 ? 0 : strlen(pathbuf));
    }
    flush_out();
    return status;
}
