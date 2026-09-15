# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS build
# 小内存机器上的构建降峰。Go 1.20+ 不再预编译标准库，首次构建要现编 net/http、
# crypto/tls 等一大批包；`-p` 默认 = CPU 核数，多个编译单元并行会把峰值顶到近 1GB，
# 叠加正在运行的服务即触发 OOM。本项目仅 26 个文件，串行只多几秒。
#   注：ENV 只作用于本 build 阶段，最终 alpine 阶段是全新环境，不会带入运行时。
ENV GOGC=30
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -p 1 -trimpath -ldflags="-s -w" -o /out/wb2api ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache wget ca-certificates tzdata \
 && adduser -D -u 10001 app \
 && mkdir -p /app/auths /app/data \
 && chown -R app:app /app
USER app
WORKDIR /app
COPY --from=build /out/wb2api /app/wb2api
COPY config.json /app/config.json
EXPOSE 7863
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD wget -qO- http://127.0.0.1:7863/healthz || exit 1
ENTRYPOINT ["/app/wb2api", "-config", "/app/config.json"]
