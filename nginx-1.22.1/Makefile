
default:	build

clean:
	rm -rf Makefile objs

.PHONY:	default clean

build:
	$(MAKE) -f objs/Makefile

install:
	$(MAKE) -f objs/Makefile install

modules:
	$(MAKE) -f objs/Makefile modules

upgrade:
	/usr/share/nginx/sbin/nginx -t

	kill -USR2 `cat /run/nginx.pid`
	sleep 1
	test -f /run/nginx.pid.oldbin

	kill -QUIT `cat /run/nginx.pid.oldbin`

.PHONY:	build install modules upgrade
