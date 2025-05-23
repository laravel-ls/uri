# -----------------------------------------------------------------------------
# global

.DEFAULT_GOAL := test
comma := ,
empty :=
space := $(empty) $(empty)

# -----------------------------------------------------------------------------
# go

GO ?= go
GO_PATH ?= $(shell $(GO) env GOPATH)
GO_OS ?= $(shell $(GO) env GOOS)
GO_ARCH ?= $(shell $(GO) env GOARCH)

PKG := $(subst $(GO_PATH)/src/,,$(CURDIR))
CGO_ENABLED ?= 0
GO_BUILDTAGS=osusergo netgo static
GO_LDFLAGS=-s -w "-extldflags=-static"
GO_FLAGS ?= -tags='$(subst $(space),$(comma),${GO_BUILDTAGS})' -ldflags='${GO_LDFLAGS}' -installsuffix=netgo

GO_PKGS := $(shell $(GO) list ./...)
GO_TEST ?= ${TOOLS_BIN}/gotestsum --
GO_TEST_PKGS ?= $(shell $(GO) list -f='{{if or .TestGoFiles .XTestGoFiles}}{{.ImportPath}}{{end}}' ./...)
GO_TEST_FLAGS ?= -race -count=1
GO_TEST_FUNC ?= .
GO_COVERAGE_OUT ?= coverage.out
GO_BENCH_FLAGS ?= -benchmem
GO_BENCH_FUNC ?= .
GO_LINT_FLAGS ?=

TOOLS_BIN := ${CURDIR}/tools/bin

# Set build environment
JOBS := $(shell getconf _NPROCESSORS_CONF)

# -----------------------------------------------------------------------------
# defines

define target
@printf "+ $(patsubst ,$@,$(1))\\n" >&2
endef

# -----------------------------------------------------------------------------
# target

##@ test, bench, coverage

export GOTESTSUM_FORMAT=standard-verbose

.PHONY: test
test: CGO_ENABLED=1
test: GO_FLAGS=-tags='$(subst ${space},${comma},${GO_BUILDTAGS})'
test: tools/bin/gotestsum  ## Runs package test including race condition.
	$(call target)
	@CGO_ENABLED=${CGO_ENABLED} ${GO_TEST} ${GO_TEST_FLAGS} -run=${GO_TEST_FUNC} $(strip ${GO_FLAGS}) ${GO_TEST_PKGS}

.PHONY: bench
bench:  ## Take a package benchmark.
	$(call target)
	@CGO_ENABLED=${CGO_ENABLED} ${GO_TEST} -run='^$$' -bench=${GO_BENCH_FUNC} ${GO_BENCH_FLAGS} $(strip ${GO_FLAGS}) ${GO_TEST_PKGS}

.PHONY: coverage
coverage: CGO_ENABLED=1
coverage: GO_FLAGS=-tags='$(subst ${space},${comma},${GO_BUILDTAGS})'
coverage: tools/bin/gotestsum  ## Takes packages test coverage.
	$(call target)
	@CGO_ENABLED=${CGO_ENABLED} ${GO_TEST} ${GO_TEST_FLAGS} -covermode=atomic -coverpkg=${PKG}/... -coverprofile=${GO_COVERAGE_OUT} $(strip ${GO_FLAGS}) ${GO_PKGS}


##@ fmt, lint

.PHONY: lint
lint: fmt lint/golangci-lint  ## Run all linters.

.PHONY: fmt
fmt: tools/bin/goimports tools/bin/gofumpt  ## Run goimports and gofumpt.
	find . -iname "*.go" -not -path "./vendor/**" | xargs -P ${JOBS} ${TOOLS_BIN}/goimports -local=${PKG},$(subst /uri,,$(PKG)) -w
	find . -iname "*.go" -not -path "./vendor/**" | xargs -P ${JOBS} ${TOOLS_BIN}/gofumpt -extra -w

.PHONY: lint/golangci-lint
lint/golangci-lint: tools/bin/golangci-lint .golangci.yml  ## Run golangci-lint.
	$(call target)
	@${TOOLS_BIN}/golangci-lint -j ${JOBS} run $(strip ${GO_LINT_FLAGS}) ./...


##@ tools

.PHONY: tools
tools: tools/bin/''  ## Install tools

tools/%: tools/bin/%  ## install an individual dependent tool

tools/bin/golangci-lint:
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
		| sh -s -- -b ${TOOLS_BIN} v2.1.6

tools/bin/gofumpt:
	GOBIN=${TOOLS_BIN} $(GO) install mvdan.cc/gofumpt@v0.6.0

tools/bin/goimports:
	GOBIN=${TOOLS_BIN} $(GO) install golang.org/x/tools/cmd/goimports@v0.10.0

tools/bin/gotestsum:
	GOBIN=${TOOLS_BIN} $(GO) install gotest.tools/gotestsum@v1.6.2

##@ clean

.PHONY: clean
clean:  ## Cleanups binaries and extra files in the package.
	$(call target)
	@rm -rf *.out *.test *.prof trace.txt ${TOOLS_BIN}


##@ miscellaneous

.PHONY: todo
TODO:  ## Print the all of (TODO|BUG|XXX|FIXME|NOTE) in packages.
	@grep -E '(TODO|BUG|XXX|FIXME)(\(.+\):|:)' $(shell find . -type f -name '*.go' -and -not -iwholename '*vendor*')

.PHONY: env/%
env/%: ## Print the value of MAKEFILE_VARIABLE. Use `make env/GO_FLAGS` or etc.
	@echo $($*)


##@ help

.PHONY: help
help:  ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[33m<target>\033[0m\n"} /^[a-zA-Z_0-9\/%_-]+:.*?##/ { printf "  \033[1;32m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
