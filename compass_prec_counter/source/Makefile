AMT	= /home/mkernel2/src/d-corner/lib
AMTINC	= ${AMT}
AMTLIB	= ${AMT}
BZ	= /usr/local/Blitz++
BZINC	= ${BZ}/include
BZLIB	= ${BZ}/lib
MK2	= /home/mkernel2/src/d-corner/database/MeshKernel2/lib
MK2INC	= ${MK2}
MK2LIB	= ${MK2}
VT	= /home/mkernel2/src/d-corner/util/value_transformer
VTINC	= ${VT}
VTLIB	= ${VT}
WLIB	= /usr/local/wlib
WLIBINC	= ${WLIB}
WLIBLIB	= ${WLIB}

ARCH	= -m32
DEFS	= -DWLIB_MTSAFE
INCS	= -I${AMTINC} -I${BZINC} -I${MK2INC} -I${VTINC} -I${WLIBINC}
OPTS	= -Wall -Wno-deprecated -g
ifdef DEBUG
DEFS	+= -DBZ_DEBUG
else
OPTS	+= -O
endif
CFLAGS	= ${ARCH} ${DEFS} ${INCS} ${OPTS}
CXXFLAGS= ${ARCH} ${DEFS} ${INCS} ${OPTS}
LDFLAGS	= ${ARCH} ${OPTS}
LDLIBS	= -L${MK2LIB} -lconndb2 -lmkernel \
	-L${VTLIB} -lvaltrans \
	-L${AMTLIB} -lthreadutil \
	-L${WLIBLIB} -lmeta -lmetapystub -lwniutil -lwnicompress -lwregex \
	-L${BZLIB} -lblitz \
	-lgdbm -lz

TARGET1	= compass_prec_counter
CFILES1	= compass_prec_counter.cpp
OFILES1	= compass_prec_counter.o

TARGETS	= ${TARGET1}
OFILES	= ${OFILES1}

all:	${TARGETS}

clean:
	${RM} ${TARGETS} ${OFILES}

${TARGET1}: ${OFILES1}
	${CXX} ${LDFLAGS} -o $@ ${OFILES1} ${LDLIBS}
