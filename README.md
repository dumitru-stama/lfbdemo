# lfbdemo
Linux Framebuffer Demo - Snow

This project uses Linux framebuffer in console mode to simulate snow falling. Snowflakes are pixels and they actually collide with each other and with other objects.

You can see it on youtube at this link : https://www.youtube.com/watch?v=u6dAp42kSNk

I chose AMD64 assembly because of these two goals set up before I started the project:

    - Finish it in one day
    - Make it under 1KB to be able to submit it to Hackaday 1KB challenge

Both goals were met, the binary part of the program has 1000 bytes. 
The problem is there are very little comments in the code and also it's not optimized at the algorythm level. Will revisit once I will have some spare time on my hands.


How it works
------------
It uses hardcoded 64bit syscalls for system access (open, mmap, ioctl, nsleep). It opens /dev/fb0, maps it into memory and starts using it as a simple raster display. I took the precautions to make it adaptable to other resolutions, however some of the elements assume a fullHD 1920/1080 resolution.
I am usind "rdrand" instruction to generate random numbers. This is available if you have a fairly recent processor.

How to Run 
----------
You must be in a console in framebuffer mode. You can boot in text mode or switch to a console from your window manager using CTRL+ALT+F1/2.

How to Build
------------

	yasm test.asm -o test.bin
	yasm -f elf64 -g dwarf2 test.asm -o test.obj
	ld -o test.elf test.obj

You need yasm which is available in standard packages for all distributions. It might work with nasm but I didn't try it.
I provided a build script as well.

Demo
----

[![Demo on youtube](https://github.com/dumitru-stama/lfbdemo/blob/master/docs/from_youtube.png?raw=true)](http://www.youtube.com/watch?v=u6dAp42kSNk "Linux framebuffer Snow demo")

