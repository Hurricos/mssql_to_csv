src/sed: sed-4.8
	pushd $<; ./configure LDFLAGS=-static && make -j8; popd; cp $</sed/sed $@

sed-4.8.tar.gz:
	wget -O "$@" "https://ftp.gnu.org/gnu/sed/sed-4.8.tar.gz"

sed-4.8: sed-4.8.tar.gz
	rm -rf $@; mkdir $@; \
	tar -xvf $< -C $@ --strip-components=1

