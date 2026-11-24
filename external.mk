# Copyright 2026 X-HEEP contributors

# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

# Author(s): Juan Sapriza (juan.sapriza@epfl.ch)
#            Michele Caon (michele.caon@epfl.ch)
#            Luigi Giuffrida (luigi.giuffrida@polito.it): X-ALP version of X-HEEP's external.mk

# Gives a project outside X-ALP (e.g. one vendoring it in hw/vendor/x-alp) X-ALP's targets, and builds
# the software in the project's own sw/ directory. Include it as the LAST line of your Makefile, as its
# '%' rule catches every target your Makefile does not define:
#
#   include hw/vendor/x-alp/external.mk

# X-ALP's base directory (where this file is), unless the including Makefile sets it.
ifndef X_ALP_DIR
X_ALP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
endif

# Relative path from X-ALP's base directory to the project (where make runs), e.g. for EXTERNAL_MCU_GEN_TEMPLATES.
X_ALP_REL_PATH := $(shell python3 -c "import os; print(os.path.relpath('.', '$(X_ALP_DIR)'))")

# The project's software sources: X-ALP's sw/Makefile resolves SOURCE from its own directory and looks for
# PROJECT in $(SOURCE)/applications. Set it when calling make if your sources are not in ./sw. Exported,
# so that the including Makefile's own recipes can also call $(MAKE) -C $(X_ALP_DIR) <target>.
export SOURCE ?= ../$(X_ALP_REL_PATH)/sw/

# Software build parameters of the app target: set them in the including Makefile (before the include) or on
# the command line. Defaults as in X-ALP's Makefile: keep them in sync.
PROJECT         ?= hello_world
LINKER          ?= spm
LINK_FOLDER     ?= $(X_ALP_DIR)/sw/linker
COMPILER        ?= gcc
COMPILER_PREFIX ?= riscv32-corev-
COMPILER_FLAGS  ?= -mabi=lp64d
ARCH            ?= rv64gc_zifencei
# Parameters for the app's own makefile ($(SOURCE)applications/$(PROJECT)/Makefile), if it has one
APP_PARAMS      ?=
APP_MAKE         = $(wildcard $(X_ALP_DIR)/sw/$(SOURCE)applications/$(PROJECT)/*akefile)

# Builds the app PROJECT (the project's sw/applications first, then X-ALP's), running its own makefile first
.PHONY: app
app:
ifneq ($(APP_MAKE),)
	@echo "### Calling application-specific makefile '$(APP_MAKE)'..."
	$(MAKE) -C $(dir $(APP_MAKE)) APP_PARAMS="$(APP_PARAMS)"
endif
	$(MAKE) -C $(X_ALP_DIR) app SOURCE=$(SOURCE) PROJECT=$(PROJECT) LINKER=$(LINKER) LINK_FOLDER=$(LINK_FOLDER) \
		COMPILER=$(COMPILER) COMPILER_PREFIX=$(COMPILER_PREFIX) COMPILER_FLAGS="$(COMPILER_FLAGS)" ARCH=$(ARCH)

# Any target not defined in the including Makefile runs in X-ALP.
%:
	@echo "[X-ALP] > Parent project is $(abspath .)"
	@echo "[X-ALP] > Your relative software sources path is $(SOURCE)"
	$(MAKE) -C $(X_ALP_DIR) $@ SOURCE=$(SOURCE)
