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

# 3. 安装依赖
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install

RUN pnpm run -r build

RUN pnpm deploy --filter=server --prod /app
RUN pnpm deploy --filter=server --prod /app-sqlite

# 【核心修复1】修改为 postgresql 驱动并清理 MySQL 方言
RUN cd /app && \
    sed -i 's/provider = "mysql"/provider = "postgresql"/g' prisma/schema.prisma && \
    sed -i 's/ @db.Int()//g' prisma/schema.prisma && \
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
ENV DATABASE_TYPE="postgres"

RUN chmod +x ./docker-bootstrap.sh

# 【核心修复2】修改启动命令！在程序正式跑起来前，先强制执行 db push，把所有数据表（货架）在 Neon 里创建出来
CMD ["sh", "-c", "pnpm exec prisma db push && ./docker-bootstrap.sh"]
