include Makefile.in
#from kernel build
ifneq ($(KERNELRELEASE),)
#from shell build
else
	ifeq ($(KERNELVER),)
		KERNELVER	:= $(shell uname -r)
	endif
	KERNELDIR	:= /lib/modules/$(KERNELVER)/build
	CWD			:= $(shell pwd)/mwv206linuxdev/
default:
	make -C $(KERNELDIR) M=$(CWD) modules
clean:
	rm -rf *.[iso] 
	rm -rf *.ko
	rm -rf .*.cmd
	rm -rf $(shell pwd)/mwv206hal/*.[iso]
	rm -rf $(shell pwd)/mwv206hal/.*.o.cmd
	make -C $(KERNELDIR) M=$(CWD) clean
depend:
	make -C $(KERNELDIR) M=$(CWD) depend 
install:

ifeq ($(OS), deepin)
	mkdir -p /lib/modules/$(KERNELVER)/kernel/drivers/gpu/jingjia
	sudo cp $(CWD)/mwv206.ko /lib/modules/$(KERNELVER)/kernel/drivers/gpu/jingjia/mwv206.ko
else	

	sudo cp $(CWD)/mwv206.ko /lib/modules/$(KERNELVER)/kernel/mwv206.ko
endif
	sudo depmod
	sync
endif
