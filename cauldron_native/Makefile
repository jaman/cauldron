STATIC_DIR ?= priv/static

static: c_src/cauldron_native.c c_src/cauldron_native.h | $(STATIC_DIR)
	$(CC) $(CFLAGS) -DSTATIC_ERLANG_NIF_LIBNAME=cauldron_native -I$(ERTS_INCLUDE_DIR) -Ic_src -c -o $(STATIC_DIR)/cauldron_native.o c_src/cauldron_native.c
	$(AR) rcs $(STATIC_DIR)/cauldron_native.a $(STATIC_DIR)/cauldron_native.o

$(STATIC_DIR):
	mkdir -p $(STATIC_DIR)

.PHONY: static
