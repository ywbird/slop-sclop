# sclop version
VERSION = 0.1

# paths
PREFIX = /usr/local
SHAREDIR = $(PREFIX)/share/sclop

# libraries
PKG_CONFIG = pkg-config
PKGS = luajit libcurl
INCS != $(PKG_CONFIG) --cflags $(PKGS)
LIBS != $(PKG_CONFIG) --libs $(PKGS)

# flags
CPPFLAGS = -D_DEFAULT_SOURCE -D_XOPEN_SOURCE=700 -D_DARWIN_C_SOURCE -DVERSION=\"$(VERSION)\" -DSHAREDIR=\"$(SHAREDIR)\"
CFLAGS = -std=c99 -pedantic -Wall -Wextra -O2 $(INCS) $(CPPFLAGS)
LDFLAGS = $(LIBS) -lm

CC = cc
