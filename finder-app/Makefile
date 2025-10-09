# Makefile for writer program
# Usage:
#   make                               # native build with gcc
#   make CROSS_COMPILE=aarch64-linux-gnu-   # cross build for ARM64

CROSS_COMPILE ?=
CC      := $(CROSS_COMPILE)gcc
CFLAGS  := -Wall -Werror -g
TARGET  := writer
SRC     := writer.c
OBJ     := $(SRC:.c=.o)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<



.PHONY: all clean

clean:
	rm -f $(TARGET) $(OBJ)
