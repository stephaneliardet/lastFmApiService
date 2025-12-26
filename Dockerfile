FROM ballerina/ballerina:2201.10.0 AS build

WORKDIR /app
COPY *.bal ./
COPY Ballerina.toml ./

RUN bal build

# Runtime image
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY --from=build /app/target/bin/lastfm_history.jar ./

# Config via variables d'environnement ou volume
# Monter Config.toml via: -v /path/to/Config.toml:/app/Config.toml

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "lastfm_history.jar"]
