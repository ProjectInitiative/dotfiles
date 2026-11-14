ratedtdp-probe.so: ratedtdp-probe.c
	$(CC) -O2 -Wall -shared -fPIC -o $@ $< -ldl

clean:
	rm -f ratedtdp-probe.so
