/* terminal: raw mode, key decoding, bracketed paste, window size */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include "sclop.h"

#define ESCDELAY 50
#define PASTE_START "\x1b[200~"
#define PASTE_END "\x1b[201~"

static const TermEvents *ev;
static struct termios saved;
static int active, cols = 80, rows = 24;
static char *in;
static size_t inlen, incap;
static int esctimer;

void term_init(const TermEvents *e)
{
	ev = e;
}

int term_active(void)
{
	return active;
}

void term_size(int *c, int *r)
{
	*c = cols;
	*r = rows;
}

static void getsize(void)
{
	struct winsize ws;
	if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0) {
		cols = ws.ws_col;
		rows = ws.ws_row;
	}
}

/* key decoding */

/* mods: 1 shift, 2 meta, 4 ctrl (xterm modifier parameter minus one) */
static void keyname(char *key, size_t sz, int mods, const char *base, int special)
{
	if (!mods && !special)
		snprintf(key, sz, "%s", base);
	else
		snprintf(key, sz, "<%s%s%s%s>", mods & 4 ? "C-" : "", mods & 2 ? "M-" : "",
		         mods & 1 ? "S-" : "", base);
}

static int csikey(int final, int p0, int mods, char *key, size_t sz)
{
	static const char *const tilde[] = {
		[1] = "Home", [2] = "Insert", [3] = "Delete", [4] = "End", [5] = "PageUp",
		[6] = "PageDown", [7] = "Home", [8] = "End", [11] = "F1", [12] = "F2",
		[13] = "F3", [14] = "F4", [15] = "F5", [17] = "F6", [18] = "F7", [19] = "F8",
		[20] = "F9", [21] = "F10", [23] = "F11", [24] = "F12",
	};
	const char *base = NULL;
	switch (final) {
	case 'A': base = "Up"; break;
	case 'B': base = "Down"; break;
	case 'C': base = "Right"; break;
	case 'D': base = "Left"; break;
	case 'H': base = "Home"; break;
	case 'F': base = "End"; break;
	case 'P': base = "F1"; break;
	case 'Q': base = "F2"; break;
	case 'R': base = "F3"; break;
	case 'S': base = "F4"; break;
	case 'Z': base = "Tab"; mods |= 1; break;
	case 'M': base = "Enter"; break;
	case '~':
		if (p0 > 0 && p0 < (int)LENGTH(tilde))
			base = tilde[p0];
		break;
	}
	if (!base)
		return 0;
	keyname(key, sz, mods, base, 1);
	return 1;
}

/* decode one key at s[0..n); returns bytes used, 0 when more input is needed.
 * key is set to "" for sequences that are consumed but ignored. */
static size_t decode(const char *s, size_t n, int flush, char *key, size_t sz)
{
	unsigned char c = s[0];
	key[0] = '\0';
	if (c == 0x1b) {
		if (n == 1) {
			if (!flush)
				return 0;
			keyname(key, sz, 0, "Escape", 1);
			return 1;
		}
		if (s[1] == '[') {
			size_t i = 2;
			int p[2] = { 0, 0 }, np = 0;
			for (; i < n && (unsigned char)s[i] >= 0x20 && (unsigned char)s[i] < 0x40; i++) {
				if (s[i] >= '0' && s[i] <= '9' && np < 2)
					p[np] = p[np] * 10 + s[i] - '0';
				else if (s[i] == ';' && ++np > 2)
					np = 2;
			}
			if (i == n) {
				if (!flush)
					return 0;
				keyname(key, sz, 2, "[", 0);
				return 2;
			}
			csikey(s[i], p[0], p[1] > 1 ? p[1] - 1 : 0, key, sz);
			return i + 1;
		}
		if (s[1] == 'O') {
			if (n < 3) {
				if (!flush)
					return 0;
				keyname(key, sz, 2, "O", 0);
				return 2;
			}
			csikey(s[2], 0, 0, key, sz);
			return 3;
		}
		/* meta: ESC followed by a key */
		char sub[48];
		size_t used = decode(s + 1, n - 1, flush, sub, sizeof sub);
		if (!used)
			return 0;
		if (!sub[0])
			return used + 1;
		if (sub[0] == '<' && sub[1])
			snprintf(key, sz, "<%s%s", strncmp(sub + 1, "C-", 2) ? "M-" : "C-M-",
			         strncmp(sub + 1, "C-", 2) ? sub + 1 : sub + 3);
		else
			snprintf(key, sz, "<M-%s>", sub);
		return used + 1;
	}
	if (c == '\r')
		keyname(key, sz, 0, "Enter", 1);
	else if (c == '\t')
		keyname(key, sz, 0, "Tab", 1);
	else if (c == 0x7f)
		keyname(key, sz, 0, "Backspace", 1);
	else if (c == 0)
		keyname(key, sz, 4, "Space", 1);
	else if (c < 0x1b)
		keyname(key, sz, 4, (char[]){ 'a' + c - 1, '\0' }, 1);
	else if (c < 0x20)
		keyname(key, sz, 4, (char[]){ "\\]^_"[c - 0x1c], '\0' }, 1);
	else if (c < 0x80)
		keyname(key, sz, 0, (char[]){ c, '\0' }, 0);
	else {
		unsigned cp;
		size_t need = c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : 2, k = 1;
		while (k < n && ((unsigned char)s[k] & 0xc0) == 0x80)
			k++;
		if (!flush && n < need && k == n && c >= 0xc2 && c <= 0xf4)
			return 0; /* the rest of the character is still coming */
		size_t len = utf8_decode(s, n, &cp);
		if (len == 1)
			memcpy(key, "\xef\xbf\xbd", 4);
		else
			memcpy(key, s, len), key[len] = '\0';
		return len;
	}
	return 1;
}

static const char *find(const char *s, size_t n, const char *pat)
{
	size_t m = strlen(pat);
	for (size_t i = 0; i + m <= n; i++)
		if (!memcmp(s + i, pat, m))
			return s + i;
	return NULL;
}

/* dispatch every complete key in s[0..n); returns bytes used */
static size_t parse(const char *s, size_t n, int flush)
{
	size_t i = 0;
	char key[64];
	while (i < n) {
		const char *p = s + i, *end;
		size_t len = n - i, used;
		if (len >= 6 && !memcmp(p, PASTE_START, 6)) {
			if (!(end = find(p + 6, len - 6, PASTE_END)) && !flush)
				break;
			if (!end)
				end = p + len;
			if (ev && ev->paste)
				ev->paste(p + 6, end - (p + 6));
			i = end + (end < s + n ? 6 : 0) - s;
			continue;
		}
		if (!(used = decode(p, len, flush, key, sizeof key)))
			break;
		i += used;
		if (key[0] && ev && ev->key)
			ev->key(key);
	}
	return i;
}

static void consume(size_t used)
{
	memmove(in, in + used, inlen - used);
	inlen -= used;
}

static void escflush(void *data)
{
	(void)data;
	esctimer = 0;
	consume(parse(in, inlen, 1));
}

static void oninput(int fd, int revents, void *data)
{
	char buf[4096];
	ssize_t n = read(fd, buf, sizeof buf);
	(void)revents;
	(void)data;
	if (n <= 0) {
		if (n < 0 && (errno == EINTR || errno == EAGAIN))
			return;
		loop_quit(1); /* the terminal went away */
		return;
	}
	if (inlen + n > incap) {
		incap = (inlen + n) * 2;
		if (!(in = realloc(in, incap)))
			abort();
	}
	memcpy(in + inlen, buf, n);
	inlen += n;
	consume(parse(in, inlen, 0));
	if (esctimer)
		loop_timer_stop(esctimer), esctimer = 0;
	if (inlen && !(inlen >= 6 && !memcmp(in, PASTE_START, 6)))
		esctimer = loop_timer(ESCDELAY, 0, escflush, NULL);
}

void term_feed(const char *s, size_t n)
{
	parse(s, n, 1);
}

/* raw mode */

static void writeall(const char *s)
{
	size_t n = strlen(s);
	while (n) {
		ssize_t w = write(STDOUT_FILENO, s, n);
		if (w < 0 && errno == EINTR)
			continue;
		if (w <= 0)
			return;
		s += w;
		n -= w;
	}
}

static void onwinch(int sig)
{
	(void)sig;
	getsize();
	ui_resize(cols, rows);
	if (ev && ev->resize)
		ev->resize(cols, rows);
}

int term_start(void)
{
	static int once;
	struct termios raw;
	if (active)
		return 0;
	if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO) || tcgetattr(STDIN_FILENO, &saved) < 0)
		return -1;
	raw = saved;
	raw.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
	raw.c_oflag &= ~OPOST;
	raw.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
	raw.c_cflag &= ~(CSIZE | PARENB);
	raw.c_cflag |= CS8;
	raw.c_cc[VMIN] = 1;
	raw.c_cc[VTIME] = 0;
	if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) < 0)
		return -1;
	active = 1;
	if (!once) {
		once = 1;
		atexit(term_stop);
		loop_signal(SIGWINCH, onwinch);
	}
	writeall("\x1b[?2004h");
	getsize();
	ui_resize(cols, rows);
	loop_watch(STDIN_FILENO, LOOP_READ, oninput, NULL);
	return 0;
}

void term_stop(void)
{
	if (!active)
		return;
	active = 0;
	loop_unwatch(STDIN_FILENO);
	writeall("\x1b[?2004l\x1b[0m\x1b[?25h");
	tcsetattr(STDIN_FILENO, TCSADRAIN, &saved);
}
