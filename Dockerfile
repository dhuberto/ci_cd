# =============================================================================
# Dockerfile — TodoList (Go + PostgreSQL)
# =============================================================================
# Multi-stage: builder Go estático + Alpine final. Imagem ~20 MB.
# =============================================================================

# ---------- Stage 1: builder ----------
FROM golang:alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY src/ ./src/

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /build/todolist ./src

# ---------- Stage 2: final ----------
FROM alpine:3.21

RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=builder /build/todolist /app/todolist

RUN addgroup -g 1001 -S appgroup && \
    adduser  -S appuser -u 1001 -G appgroup

USER appuser

EXPOSE 5000

ARG IMAGE_TAGS=""
ENV IMAGE_TAGS=$IMAGE_TAGS

CMD ["/app/todolist"]
