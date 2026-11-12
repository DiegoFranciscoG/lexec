# syntax=docker/dockerfile:1
# Multi-stage build: compile the release with the full toolchain, run it on a slim
# Debian image as a non-root user. Versions are pinned (never :latest).
ARG ELIXIR_IMAGE=hexpm/elixir:1.20.5-erlang-29.1.2-debian-trixie-20261104-slim
ARG RUNNER_IMAGE=debian:trixie-20261104-slim

FROM ${ELIXIR_IMAGE} AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.setup && mix compile && mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM ${RUNNER_IMAGE} AS runner
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates poppler-utils curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /app --shell /usr/sbin/nologin lexec \
 && mkdir -p /data /cache \
 && chown lexec:lexec /data /cache

WORKDIR /app
ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    DATABASE_PATH=/data/lexec.db \
    BUMBLEBEE_CACHE_DIR=/cache/bumblebee \
    XLA_CACHE_DIR=/cache/xla

COPY --from=build --chown=lexec:lexec /app/_build/prod/rel/lexec ./
USER lexec
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=5 \
  CMD curl -fsS http://localhost:4000/health || exit 1
CMD ["/app/bin/server"]
