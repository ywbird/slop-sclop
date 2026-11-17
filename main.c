/* sclop: a minimal coding agent */
#include <langinfo.h>
#include <locale.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

#include "sclop.h"

static void onquit(int sig)
{
	loop_quit(128 + sig);
}

static void utf8locale(void)
{
	const char *cs;
	setlocale(LC_CTYPE, "");
	cs = nl_langinfo(CODESET);
	if (!strstr(cs, "UTF-8") && !strstr(cs, "utf8") && !setlocale(LC_CTYPE, "C.UTF-8"))
		setlocale(LC_CTYPE, "en_US.UTF-8");
}

int main(int argc, char *argv[])
{
	int code;

	utf8locale();
	signal(SIGPIPE, SIG_IGN);
	if (loop_init() < 0) {
		perror("sclop");
		return 1;
	}
	loop_signal(SIGINT, onquit);
	loop_signal(SIGTERM, onquit);
	loop_signal(SIGHUP, onquit);

	code = script_start(argc, argv) ? 1 : loop_run(script_idle);
	script_stop();
	return code;
}
