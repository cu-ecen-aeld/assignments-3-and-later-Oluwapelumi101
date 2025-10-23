# Build with: make -C server
# Cross-compile with: make -C server CC=aarch64-linux-gnu-gcc
APP := aesdsocket

CC ?= gcc
CFLAGS ?= -Wall -Wextra -Werror -O2 -std=gnu11
LDFLAGS ?=
SRCS := aesdsocket.c
OBJS := $(SRCS:.c=.o)

.PHONY: all default clean
all: $(APP)
default: all

$(APP): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(APP) $(OBJS)
