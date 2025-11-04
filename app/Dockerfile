# syntax=docker/dockerfile:1

# Base común con toolchain para dependencias nativas (p.ej. sharp)
FROM node:20-alpine AS base
RUN apk add --no-cache libc6-compat python3 make g++ \
  && addgroup -g 1001 -S nodejs \
  && adduser -S nextjs -u 1001
WORKDIR /app

# 1) Instalar deps (incluye dev para poder compilar y hacer el build)
FROM base AS deps
COPY package*.json ./
RUN npm ci

# 2) Build de la app usando las deps ya instaladas
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# 3) Runtime: solo lo necesario para ejecutar en producción
FROM node:20-alpine AS runner
RUN apk add --no-cache libc6-compat
ENV NODE_ENV=production
WORKDIR /app

# Copiamos node_modules desde deps y podamos dev deps
COPY --from=deps /app/node_modules ./node_modules
RUN npm prune --omit=dev

# Copiamos artefactos de build y archivos necesarios
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package*.json ./
# Si tienes next.config.js u otros, cópialos también:
COPY --from=builder /app/next.config.js ./next.config.js

USER node
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
EXPOSE 3000

# Debe existir "start" en package.json -> next start
CMD ["npm","run","start"]


# 4) (Opcional) Objetivo de desarrollo
FROM base AS dev
ENV NODE_ENV=development
COPY package*.json ./
RUN npm install
COPY . .
CMD ["npm","run","dev"]
