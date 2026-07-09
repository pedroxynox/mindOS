# mindOS API (NestJS) — multi-stage build
FROM node:22-slim AS builder
WORKDIR /app

# Prisma needs OpenSSL
RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./
RUN npm ci

COPY prisma ./prisma
RUN npx prisma generate

COPY . .
RUN npm run build

FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./

# Reuse the builder's node_modules (instead of `npm ci --omit=dev`) so the
# runtime image keeps the Prisma CLI + generated client + engines available.
# That lets `npx prisma migrate deploy` run as a Render preDeploy step (the
# migrations create the tables, RLS policies, the non-owner app role and the
# pgvector extension). See docs/06-infrastructure/DEPLOY_RENDER.md.
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x docker-entrypoint.sh

# main.ts reads process.env.PORT (Render sets it); defaults to 3000 locally.
# The entrypoint runs migrations (as the owner URL) then `node dist/main`.
EXPOSE 3000
CMD ["sh", "./docker-entrypoint.sh"]
