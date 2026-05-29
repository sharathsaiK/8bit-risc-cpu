CXX      = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2

all: assembler simulator

assembler: assembler.cpp
	$(CXX) $(CXXFLAGS) -o assembler assembler.cpp

simulator: simulator.cpp
	$(CXX) $(CXXFLAGS) -o simulator simulator.cpp

test: assembler simulator
	./assembler test_program.asm out.hex
	./simulator out.hex

clean:
	rm -f assembler simulator out.hex

.PHONY: all test clean
