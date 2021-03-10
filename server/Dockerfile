FROM alpine:latest

RUN apk add nginx

COPY nginx /nginx

CMD ["nginx", "-c", "/nginx/nginx.conf"]
