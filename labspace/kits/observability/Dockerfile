FROM golang:1.25-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY backend/ .
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/observability .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/observability /observability
EXPOSE 8090
ENTRYPOINT ["/observability"]
