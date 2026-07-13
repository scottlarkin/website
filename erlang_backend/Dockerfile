FROM elixir:1.17-otp-27-alpine

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git build-base nodejs npm

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./

# Get dependencies
RUN mix deps.get

# Copy source
COPY lib ./lib
COPY config ./config
COPY priv ./priv
COPY assets ./assets

# Build assets
RUN mix esbuild.install --if-missing
RUN MIX_ENV=prod mix assets.deploy

# Compile
RUN MIX_ENV=prod mix compile

ENV MIX_ENV=prod

EXPOSE 3000

CMD ["mix", "phx.server"]