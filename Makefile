
all: wait

serve:
	mkdir _serve || true
	cd _site && python -m SimpleHTTPServer 4000

compile:
	../jekyll/bin/jekyll

wait:
	make compile
	while [ 1 ]; do \
		inotifywait -e modify,move,delete -r ./*; \
		sleep 0.1; \
		make compile; \
	done


clean:
	rm -rf _site
