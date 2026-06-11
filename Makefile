SRC      = src/alu.v src/control_unit.v src/cpu.v src/data_memory.v \
           src/full_adder.v src/half_adder.v src/instruction_memory.v \
           src/program_counter.v src/register_file.v
IVERILOG = iverilog -g2012

all: tools program sim/cpu_tb sim/run_tb verilator

# --- C++ assembler + simulator ---
tools:
	$(MAKE) -C cpp assembler simulator

# --- assemble the standard test program into the ROM image ---
program: tools
	./cpp/assembler cpp/test_program.asm tests/program.hex

fib.hex: tools
	./cpp/assembler cpp/fib.asm fib.hex

timer_irq.hex: tools
	./cpp/assembler cpp/timer_irq.asm timer_irq.hex

privilege.hex: tools
	./cpp/assembler cpp/privilege.asm privilege.hex

invalid_opcode.hex: tools
	./cpp/assembler cpp/invalid_opcode.asm invalid_opcode.hex

# --- Icarus builds ---
sim/cpu_tb: tests/cpu_tb.v $(SRC)
	$(IVERILOG) -o $@ $< $(SRC)

sim/run_tb: tests/run_tb.v $(SRC)
	$(IVERILOG) -o $@ $< $(SRC)

sim/control_unit_tb: tests/control_unit_tb.v src/control_unit.v
	$(IVERILOG) -o $@ $^

sim/alu_tb: tests/alu_tb.v src/alu.v src/full_adder.v src/half_adder.v
	$(IVERILOG) -o $@ $^

# --- Verilator build of the generic runner ---
verilator: $(SRC) tests/run_tb.v
	verilator --binary --timing -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	    --top-module run_tb -o Vrun_tb tests/run_tb.v $(SRC)

# --- run everything ---
test: program sim/cpu_tb sim/control_unit_tb
	vvp sim/control_unit_tb
	vvp sim/cpu_tb

cosim: program fib.hex timer_irq.hex privilege.hex invalid_opcode.hex sim/run_tb verilator
	tests/cosim.sh tests/program.hex
	tests/cosim.sh fib.hex
	tests/cosim.sh timer_irq.hex
	tests/cosim.sh privilege.hex
	tests/cosim.sh invalid_opcode.hex

clean:
	rm -f sim/cpu_tb sim/run_tb sim/control_unit_tb sim/alu_tb \
	      fib.hex timer_irq.hex privilege.hex invalid_opcode.hex
	rm -rf obj_dir
	$(MAKE) -C cpp clean

.PHONY: all tools program verilator test cosim clean
