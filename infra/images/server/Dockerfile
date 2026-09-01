# syntax=docker/dockerfile:1.7

ARG BUILDER_IMAGE=elixir:1.20.2-otp-29@sha256:c915d900894e1d664cd8ed72fd2c38fce72b612cc1757d57f86a0cc62e62dd79
ARG RUNTIME_IMAGE=debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

FROM ${BUILDER_IMAGE} AS builder

ARG KEEPLING_BUILD_ERL_FLAGS
ENV MIX_ENV=prod
ENV ERL_FLAGS=${KEEPLING_BUILD_ERL_FLAGS}
WORKDIR /build

RUN test "$(elixir -e 'IO.write(System.version())')" = "1.20.2" \
    && test "$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')" = "29" \
    && test "$(cat /usr/local/lib/erlang/releases/29/OTP_VERSION)" = "29.0.5"
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY lib lib
COPY priv priv
RUN mix compile --warnings-as-errors && mix release

FROM ${RUNTIME_IMAGE} AS runtime

ARG OCI_REVISION
ARG OCI_SOURCE=https://github.com/szTheory/keepling
ARG KEEPLING_RELEASE=0.1.0
ARG KEEPLING_PROTOCOL_MIN=1
ARG KEEPLING_PROTOCOL_MAX=1
ARG KEEPLING_SCHEMA_MIN=1
ARG KEEPLING_SCHEMA_MAX=14

LABEL org.opencontainers.image.title="Keepling Server" \
      org.opencontainers.image.description="Keepling Phoenix release" \
      org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.version="${KEEPLING_RELEASE}" \
      io.keepling.release="${KEEPLING_RELEASE}" \
      io.keepling.protocol.minimum="${KEEPLING_PROTOCOL_MIN}" \
      io.keepling.protocol.maximum="${KEEPLING_PROTOCOL_MAX}" \
      io.keepling.schema.minimum="${KEEPLING_SCHEMA_MIN}" \
      io.keepling.schema.maximum="${KEEPLING_SCHEMA_MAX}"

RUN groupadd --system --gid 10001 keepling \
    && useradd --system --uid 10001 --gid keepling --home-dir /app --shell /usr/sbin/nologin keepling

WORKDIR /app
COPY --from=builder --chown=keepling:keepling /build/_build/prod/rel/keepling ./

ENV HOME=/app \
    LANG=C.UTF-8 \
    PHX_SERVER=true \
    PORT=4000

USER 10001:10001
EXPOSE 4000

ENTRYPOINT ["/app/bin/keepling"]
CMD ["start"]
