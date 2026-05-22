FROM oven/bun:1.2.14-alpine

WORKDIR /app

COPY package.json ./
RUN bun install --frozen-lockfile 2>/dev/null || bun install

COPY tsconfig.json ./
COPY src/ ./src/
COPY public/ ./public/

EXPOSE 8080

CMD ["bun", "run", "src/server.ts"]
