include config.mk

SRC = main.c loop.c lua.c
OBJ = $(SRC:.c=.o)

all: sclop

.c.o:
	$(CC) $(CFLAGS) -c $<

$(OBJ): sclop.h config.mk

sclop: $(OBJ)
	$(CC) -o $@ $(OBJ) $(LDFLAGS)

test: sclop
	./sclop -l test/run.lua

install: sclop
	mkdir -p $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(SHAREDIR)
	cp -f sclop $(DESTDIR)$(PREFIX)/bin/
	cp -Rf lua/. $(DESTDIR)$(SHAREDIR)/

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/sclop
	rm -rf $(DESTDIR)$(SHAREDIR)

clean:
	rm -f sclop $(OBJ)

.PHONY: all test install uninstall clean
