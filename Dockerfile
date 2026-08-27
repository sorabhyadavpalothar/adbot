FROM debian:trixie-slim

WORKDIR /app

COPY ./dist/adbot ./dist/adbot
COPY .env ./.env

RUN chmod +x ./dist/adbot

ENTRYPOINT ["./dist/adbot"]