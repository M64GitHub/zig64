LD = cl65

# Output PRG file
TARGET = test.prg

SRC = test.asm

# Object file
OBJ = test.o

# Config file (memory layout)
CFG = c64.cfg

# Default rule: assemble and link
all:
	$(LD) -o $(TARGET) -t c64 -C c64-asm.cfg --start-addr 49152 $(SRC)

# Clean up
clean:
	rm -f *.o $(TARGET)
