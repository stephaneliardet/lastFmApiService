FROM ballerina/ballerina:2201.13.1 AS build

WORKDIR /app
COPY --chmod=644 *.bal ./
COPY --chmod=644 Ballerina.toml ./
COPY --chmod=755 modules/ ./modules/

RUN bal build

# Runtime image
FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /app/target/bin/lastfm_history.jar ./

# Créer le répertoire data pour SQLite
RUN mkdir -p /app/data

# Ports: 8098 (enriched), 8099 (lastfm brut)
EXPOSE 8098 8099

ENTRYPOINT ["java", "-jar", "lastfm_history.jar"]