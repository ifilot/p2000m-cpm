ROOT := $(abspath ../..)
IMAGE := z88dk/z88dk:latest
EMULATOR ?= /mnt/d/PROGRAMMING/P2000M/p2000m-emulator
RUN_IMAGE := $(ROOT)/build/othello-run.img

.PHONY: hello othello run

hello:

	mkdir -p $(ROOT)/build

	docker run --rm -v $(ROOT):/work -w /work $(IMAGE) \
		zcc +cpm -create-app -o build/HELLO.COM programs/othello/hello.c

othello:

	mkdir -p $(ROOT)/build

	docker run --rm -v $(ROOT):/work -w /work $(IMAGE) \
		zcc +cpm -create-app -o build/OTHELLO.COM programs/othello/othello.c

run: othello

	@test -f $(ROOT)/build/cartridge.bin -a -f $(ROOT)/build/kernel.bin || \
		(cd $(ROOT) && python3 tools/build.py)

	cmake --build $(EMULATOR)/build --target p2000m -j2

	$(RM) $(RUN_IMAGE)

	cd $(ROOT) && python3 tools/sd_image.py $(RUN_IMAGE) \
		--kernel build/kernel.bin --a build/OTHELLO.COM

	$(EMULATOR)/build/p2000m \
		--cartridge $(ROOT)/build/cartridge.bin \
		--sd-card $(RUN_IMAGE) --co-board --run OTHELLO
