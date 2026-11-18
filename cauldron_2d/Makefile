CFLAGS ?= -fPIC -O3 -Wall -Wextra
override CFLAGS += -ffp-contract=off
LDFLAGS ?=

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
	LDFLAGS += -shared
endif

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~s/include", [code:root_dir() ++ "/erts-" ++ erlang:system_info(version)])' -s init stop)

PRIV_DIR ?= priv
NIFS = $(PRIV_DIR)/plane_nif.so $(PRIV_DIR)/volume_nif.so $(PRIV_DIR)/blend_nif.so $(PRIV_DIR)/sector_nif.so

all: $(NIFS)

$(PRIV_DIR)/%.so: c_src/%.c | $(PRIV_DIR)
	@$(CC) $(CFLAGS) -I$(ERTS_INCLUDE_DIR) -o $@.tmp $< $(LDFLAGS) \
		&& mv -f $@.tmp $@ && rm -rf $@.tmp.dSYM \
		|| echo "cauldron_2d: $< did not build, its work will be done in Elixir"

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

STATIC_DIR ?= priv/static
STATIC_NIFS = $(STATIC_DIR)/plane_nif.a $(STATIC_DIR)/volume_nif.a $(STATIC_DIR)/blend_nif.a $(STATIC_DIR)/sector_nif.a

static: $(STATIC_NIFS)

$(STATIC_DIR)/%.a: c_src/%.c | $(STATIC_DIR)
	$(CC) $(CFLAGS) -DSTATIC_ERLANG_NIF_LIBNAME=$* -I$(ERTS_INCLUDE_DIR) -c -o $(STATIC_DIR)/$*.o $<
	$(AR) rcs $@ $(STATIC_DIR)/$*.o

$(STATIC_DIR):
	mkdir -p $(STATIC_DIR)

clean:
	rm -f $(PRIV_DIR)/*.so $(PRIV_DIR)/*.tmp
	rm -rf $(PRIV_DIR)/*.tmp.dSYM

.PHONY: all static clean
