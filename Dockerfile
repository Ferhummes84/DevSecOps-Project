FROM node:16.17.0-alpine AS builder
WORKDIR /app
COPY ./package.json .
COPY ./yarn.lock .
# Instala só o que está no yarn.lock e sem executar scripts de pacotes de terceiros
RUN yarn install --frozen-lockfile --ignore-scripts
COPY . .
ENV VITE_APP_API_ENDPOINT_URL="https://api.themoviedb.org/3"
RUN --mount=type=secret,id=tmdb_key \
    VITE_APP_TMDB_V3_API_KEY="$(cat /run/secrets/tmdb_key)" yarn build

FROM nginx:stable-alpine
WORKDIR /usr/share/nginx/html
RUN rm -rf ./*
COPY --from=builder /app/dist .
EXPOSE 80
ENTRYPOINT ["nginx", "-g", "daemon off;"]
