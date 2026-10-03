# Makefile para FreeBSD, esto es casi que exclusivamente para mi uso (Mattio)
GMAKE ?= gmake

.MAIN: help

.DEFAULT:
	@command -v ${GMAKE} >/dev/null 2>&1 || { \
		echo "Error: este Makefile necesita GNU make en FreeBSD." >&2; \
		exit 1; \
	}
	@${GMAKE} --no-print-directory -f GNUmakefile $@
