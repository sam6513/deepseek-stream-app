FROM node:22-alpine AS build

ARG DEEPSEEK_API_KEY
ENV VITE_DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

FROM node:22-alpine

WORKDIR /app

COPY --from=build /app/build ./build
COPY --from=build /app/package*.json ./

ENV HOST=0.0.0.0
ENV PORT=3000

EXPOSE 3000

CMD ["node", "build/index.js"]
