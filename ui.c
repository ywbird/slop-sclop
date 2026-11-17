/* inline screen: a live region redrawn by diff, finished text committed above it */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wchar.h>

#include "sclop.h"

typedef struct {
	char *s;
	size_t len, cap;
	int w; /* display width, for rows */
} Buf;

static Buf out;   /* pending terminal output */
static Buf *prev; /* rows of the last frame */
static int nprev;
static int currow; /* terminal cursor row inside the live region */
static int drawrow, drawcol; /* where the last draw left the cursor */
static int cols = 80, rows = 24;
static int geometry; /* the size changed: repaint everything */
static int syncing;

static void bput(Buf *b, const char *s, size_t n)
{
	if (b->len + n > b->cap) {
		b->cap = (b->len + n) * 2 + 64;
		if (!(b->s = realloc(b->s, b->cap)))
			abort();
	}
	memcpy(b->s + b->len, s, n);
	b->len += n;
}

static void put(const char *s)
{
	bput(&out, s, strlen(s));
}

static void putn(const char *fmt, int n)
{
	char tmp[32];
	snprintf(tmp, sizeof tmp, fmt, n);
	put(tmp);
}

/* decode one character; invalid input yields U+FFFD and length 1 */
size_t utf8_decode(const char *str, size_t n, unsigned *cp)
{
	const unsigned char *s = (const unsigned char *)str;
	size_t len;
	unsigned min;
	if (s[0] < 0x80) {
		*cp = s[0];
		return 1;
	}
	if (s[0] >= 0xc2 && s[0] <= 0xdf)
		len = 2, min = 0x80, *cp = s[0] & 0x1f;
	else if (s[0] >= 0xe0 && s[0] <= 0xef)
		len = 3, min = 0x800, *cp = s[0] & 0x0f;
	else if (s[0] >= 0xf0 && s[0] <= 0xf4)
		len = 4, min = 0x10000, *cp = s[0] & 0x07;
	else
		goto bad;
	if (n < len)
		goto bad;
	for (size_t i = 1; i < len; i++) {
		if ((s[i] & 0xc0) != 0x80)
			goto bad;
		*cp = *cp << 6 | (s[i] & 0x3f);
	}
	if (*cp < min || *cp > 0x10ffff || (*cp >= 0xd800 && *cp <= 0xdfff))
		goto bad;
	return len;
bad:
	*cp = 0xfffd;
	return 1;
}

static int cpwidth(unsigned cp)
{
	int w = wcwidth((wchar_t)cp);
	return w < 0 ? 1 : w;
}

/* length of the escape sequence at s (s[0] is ESC) */
static size_t esclen(const char *s, size_t n)
{
	size_t i = 2;
	if (n < 2)
		return n;
	if (s[1] == '[') {
		while (i < n && ((unsigned char)s[i] < 0x40 || (unsigned char)s[i] > 0x7e))
			i++;
		return i < n ? i + 1 : n;
	}
	if (s[1] == ']') {
		for (; i < n; i++) {
			if (s[i] == '\a')
				return i + 1;
			if (s[i] == 0x1b && i + 1 < n && s[i + 1] == '\\')
				return i + 2;
		}
		return n;
	}
	return 2;
}

/* colors and OSC 8 links pass; anything else could move the cursor */
static int keepesc(const char *s, size_t n)
{
	return (n > 2 && s[1] == '[' && s[n - 1] == 'm') || (n > 4 && !memcmp(s, "\x1b]8;", 4));
}

int ui_width(const char *s, size_t n)
{
	int w = 0;
	for (size_t i = 0; i < n;) {
		unsigned char c = s[i];
		unsigned cp;
		if (c == 0x1b)
			i += esclen(s + i, n - i);
		else if (c == '\t')
			w += 8 - w % 8, i++;
		else if (c < 0x20 || c == 0x7f)
			i++;
		else
			i += utf8_decode(s + i, n - i, &cp), w += cpwidth(cp);
	}
	return w;
}

static void begin(void)
{
	if (!syncing) {
		put("\x1b[?2026h\x1b[?25l");
		syncing = 1;
	}
}

void ui_flush(void)
{
	if (syncing) {
		put("\x1b[?25h\x1b[?2026l");
		syncing = 0;
	}
	for (size_t off = 0; off < out.len;) {
		ssize_t w = write(STDOUT_FILENO, out.s + off, out.len - off);
		if (w < 0 && errno == EINTR)
			continue;
		if (w <= 0)
			break;
		off += w;
	}
	out.len = 0;
}

static void moveto(int r)
{
	if (r < currow)
		putn("\x1b[%dA", currow - r);
	else if (r > currow)
		putn("\x1b[%dB", r - currow);
	currow = r;
}

static void freerows(Buf *r, int n)
{
	for (int i = 0; i < n; i++)
		free(r[i].s);
}

void ui_reset(void)
{
	freerows(prev, nprev);
	nprev = 0;
	currow = drawrow = drawcol = 0;
}

void ui_resize(int c, int r)
{
	cols = c > 0 ? c : 80;
	rows = r > 0 ? r : 24;
	/* most terminals rewrap the rows we drew: follow the cursor there */
	currow = drawcol / cols;
	for (int i = 0; i < drawrow && i < nprev; i++)
		currow += prev[i].w > cols ? (prev[i].w + cols - 1) / cols : 1;
	geometry = 1;
}

/* clear from the top of the live region to the end of the screen. Never send ED
 * from the top-left corner: tmux moves the whole screen into its history then. */
static void cleartop(void)
{
	moveto(0);
	put("\r\x1b[2K");
	put(nprev > 1 ? "\x1b[B\x1b[J\x1b[A" : "\x1b[J");
}

static void addrow(Buf **rowsp, int *n, int *cap, Buf *b, int w)
{
	if (*n == *cap) {
		*cap = *cap ? *cap * 2 : 16;
		if (!(*rowsp = realloc(*rowsp, *cap * sizeof **rowsp)))
			abort();
	}
	b->w = w;
	(*rowsp)[(*n)++] = *b;
	*b = (Buf){ 0 };
}

/* wrap logical lines into rows of the terminal width; finds the cursor row/column */
static int layout(const char **lines, const size_t *lens, int n, int row, size_t col,
                  Buf **out_rows, int *crow, int *ccol)
{
	Buf *fr = NULL, b = { 0 };
	int nfr = 0, cap = 0;
	char sgr[256];

	*crow = -1;
	*ccol = 0;
	for (int l = 0; l < n; l++) {
		const char *s = lines[l];
		size_t len = lens[l], sgrlen = 0, i = 0;
		int w = 0, here = (l == row - 1);
		for (;;) {
			if (here && *crow < 0 && (i >= col || i >= len))
				*crow = nfr, *ccol = w;
			if (i >= len)
				break;
			unsigned char c = s[i];
			if (c == 0x1b) {
				size_t e = esclen(s + i, len - i);
				if (keepesc(s + i, e)) {
					bput(&b, s + i, e);
					if (s[i + 1] == '[' && (e == 3 || (e == 4 && s[i + 2] == '0')))
						sgrlen = 0;
					else if (s[i + 1] == '[' && sgrlen + e <= sizeof sgr)
						memcpy(sgr + sgrlen, s + i, e), sgrlen += e;
				}
				i += e;
				continue;
			}
			if ((c < 0x20 && c != '\t') || c == 0x7f) {
				i++;
				continue;
			}
			const char *o = s + i;
			size_t adv = 1, olen = 1;
			int cw;
			unsigned cp;
			if (c == '\t') {
				cw = 8 - w % 8;
				o = "        ";
				olen = cw;
			} else {
				adv = olen = utf8_decode(s + i, len - i, &cp);
				cw = cpwidth(cp);
				if (adv == 1 && c >= 0x80)
					o = "\xef\xbf\xbd", olen = 3;
			}
			if (w + cw > cols && w > 0) {
				addrow(&fr, &nfr, &cap, &b, w);
				if (here && *crow == nfr - 1 && *ccol >= cols)
					*crow = nfr, *ccol = 0;
				bput(&b, sgr, sgrlen);
				w = 0;
				if (c == '\t')
					cw = olen = cols < 8 ? cols : 8;
			}
			bput(&b, o, olen);
			w += cw;
			i += adv;
		}
		addrow(&fr, &nfr, &cap, &b, w);
		if (here && *crow == nfr - 1 && *ccol >= cols) {
			addrow(&fr, &nfr, &cap, &b, 0);
			*crow = nfr - 1, *ccol = 0;
		}
	}
	*out_rows = fr;
	return nfr;
}

void ui_draw(const char **lines, const size_t *lens, int n, int row, size_t col)
{
	Buf *fr;
	int crow, ccol, nfr, start = 0, h, first = 0;

	if (!term_active())
		return;
	nfr = layout(lines, lens, n, row, col, &fr, &crow, &ccol);
	h = nfr;
	if (h > rows) {
		start = nfr - rows;
		if (crow >= 0 && crow < start)
			start = crow;
		h = rows;
	}
	Buf *vis = fr + start;
	if (crow < 0) {
		crow = h ? h - 1 : 0;
		ccol = h ? vis[h - 1].w : 0;
	} else {
		crow -= start;
	}

	begin();
	if (geometry) {
		/* rows may have been rewrapped: clear everything below the top */
		cleartop();
		for (int i = 0; i < h; i++) {
			if (i)
				put("\r\n");
			bput(&out, vis[i].s, vis[i].len);
			put("\x1b[0m");
		}
		currow = h ? h - 1 : 0;
	} else {
		while (first < h && first < nprev && vis[first].len == prev[first].len &&
		       !memcmp(vis[first].s, prev[first].s, vis[first].len))
			first++;
		/* erase lines one by one: a cleared screen at 0,0 would land in tmux's history */
		for (int i = first; i < h; i++) {
			if (i < nprev || i == 0) {
				moveto(i);
			} else {
				moveto(i - 1);
				put("\r\n");
				currow = i;
			}
			put("\r\x1b[2K");
			bput(&out, vis[i].s, vis[i].len);
			put("\x1b[0m");
		}
		for (int i = h; i < nprev; i++) {
			moveto(i);
			put("\r\x1b[2K");
		}
	}
	moveto(crow);
	put("\r");
	if (ccol > 0)
		putn("\x1b[%dC", ccol);
	drawrow = crow;
	drawcol = ccol;

	freerows(prev, nprev);
	free(prev);
	freerows(fr, start);
	freerows(fr + start + h, nfr - start - h);
	if (!(prev = malloc((h ? h : 1) * sizeof *prev)))
		abort();
	memcpy(prev, vis, h * sizeof *prev);
	nprev = h;
	free(fr);
	geometry = 0;
}

/* erase the live region and put the cursor at its top */
static void erase(void)
{
	if (geometry) {
		cleartop();
	} else {
		for (int i = nprev - 1; i >= 0; i--) {
			moveto(i);
			put("\r\x1b[2K");
		}
		moveto(0);
	}
	ui_reset();
	geometry = 0;
}

void ui_commit(const char *s, size_t n)
{
	if (!term_active()) {
		bput(&out, s, n);
		if (!n || s[n - 1] != '\n')
			put("\n");
		ui_flush();
		return;
	}
	begin();
	erase();
	for (size_t i = 0; i < n;) {
		unsigned char c = s[i];
		if (c == '\n') {
			put("\r\n");
			i++;
		} else if (c == 0x1b) {
			size_t e = esclen(s + i, n - i);
			if (keepesc(s + i, e))
				bput(&out, s + i, e);
			i += e;
		} else if ((c < 0x20 && c != '\t') || c == 0x7f) {
			i++;
		} else {
			bput(&out, s + i, 1);
			i++;
		}
	}
	put("\x1b[0m");
	if (!n || s[n - 1] != '\n')
		put("\r\n");
}

void ui_write(const char *s, size_t n)
{
	begin();
	bput(&out, s, n);
}

void ui_clear(void)
{
	if (!term_active())
		return;
	begin();
	erase();
	ui_flush();
}
