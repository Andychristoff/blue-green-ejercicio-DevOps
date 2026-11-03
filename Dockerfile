FROM node:24-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM node:24-alpine

WORKDIR /app

RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
    /opt/yarn* /usr/local/bin/yarn /usr/local/bin/yarnpkg

COPY --from=build --chown=1000:1000 /app/package.json /app/vite.config.js /app/.env.production ./
COPY --from=build --chown=1000:1000 /app/src/data ./src/data
COPY --from=build --chown=1000:1000 /app/node_modules ./node_modules
COPY --from=build --chown=1000:1000 /app/dist ./dist

USER 1000

EXPOSE 4173

CMD ["node", "node_modules/vite/bin/vite.js", "preview", "--host", "0.0.0.0", "--port", "4173"]
