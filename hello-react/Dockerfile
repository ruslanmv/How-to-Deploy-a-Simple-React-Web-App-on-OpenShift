# Builder stage
FROM node:23-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY --from=builder /app/build /usr/share/nginx/html
# No need for IPv6 patch, already non-root & listens on 8080
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
