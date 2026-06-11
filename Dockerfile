FROM node:22-alpine AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# 1. 安装 openssl 依赖
RUN apk add --no-cache openssl

# 2. 全局安装 pnpm v8
RUN npm i -g pnpm@8

FROM base AS build
COPY . /usr/src/app
WORKDIR /usr/src/app

# 3. 干净的一行安装，同时保留 Render 的缓存加速
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install

RUN pnpm run -r build

RUN pnpm deploy --filter=server --prod /app
RUN pnpm deploy --filter=server --prod /app-sqlite

# 【核心修复】因为你使用的是 Neon (PostgreSQL)，而源码默认配置的是 mysql。
# 我们在编译前，用 sed 命令把 schema.prisma 里的 provider 动态修改为 postgresql，完美对接 Neon！
RUN cd /app && \
    sed -i 's/provider = "mysql"/provider = "postgresql"/g' prisma/schema.prisma && \
    pnpm exec prisma generate

RUN cd /app-sqlite && \
    rm -rf ./prisma && \
    mv prisma-sqlite prisma && \
    pnpm exec prisma generate

FROM base AS app-sqlite
COPY --from=build /app-sqlite /app

WORKDIR /app

EXPOSE 4000

ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL="file:../data/wewe-rss.db"
ENV DATABASE_TYPE="sqlite"

RUN chmod +x ./docker-bootstrap.sh

CMD ["./docker-bootstrap.sh"]


FROM base AS app
COPY --from=build /app /app

WORKDIR /app

EXPOSE 4000

ENV NODE_ENV=production
ENV HOST="0.0.0.0"
ENV SERVER_ORIGIN_URL=""
ENV MAX_REQUEST_PER_MINUTE=60
ENV AUTH_CODE=""
ENV DATABASE_URL=""
# 【配套配置】告诉 wewe-rss 运行时我们用的是 postgres
ENV DATABASE_TYPE="postgres"

RUN chmod +x ./docker-bootstrap.sh

CMD ["./docker-bootstrap.sh"]
CMD ["./docker-bootstrap.sh"]
