// Test d'initialisation de la base de données SQLite

import ballerina/file;
import ballerina/io;
import ballerina/sql;
import ballerina/test;
import prive/lastfm_history.db;

@test:Config {
    before: cleanupTestDb
}
function testDbInitialization() returns error? {
    io:println("Testing SQLite database initialization...");

    // Configuration de test
    db:DbConfig config = {
        dbType: db:SQLITE,
        database: "data/lastfm.db"
    };

    // Créer le client (devrait créer la DB et exécuter les migrations)
    db:DbClient dbClient = check db:createDbClient(config);

    // Vérifier que la connexion est active
    test:assertTrue(dbClient.isConnected(), "Database should be connected");

    // Vérifier que les tables ont été créées
    record {}? artistsTable = check dbClient.queryOne(
        `SELECT name FROM sqlite_master WHERE type='table' AND name='artists'`
    );
    test:assertTrue(artistsTable is record {}, "Table 'artists' should exist");

    record {}? tracksTable = check dbClient.queryOne(
        `SELECT name FROM sqlite_master WHERE type='table' AND name='tracks'`
    );
    test:assertTrue(tracksTable is record {}, "Table 'tracks' should exist");

    record {}? scrobblesTable = check dbClient.queryOne(
        `SELECT name FROM sqlite_master WHERE type='table' AND name='scrobbles'`
    );
    test:assertTrue(scrobblesTable is record {}, "Table 'scrobbles' should exist");

    // Vérifier la version du schéma
    record {}? version = check dbClient.queryOne(
        `SELECT MAX(version) as version FROM schema_migrations`
    );
    test:assertTrue(version is record {}, "Schema version should exist");
    io:println(string `Schema version: ${version.toString()}`);

    // Fermer la connexion
    check dbClient.close();

    io:println("Database initialization test passed!");
}

// Nettoie la DB de test avant chaque test
function cleanupTestDb() returns error? {
    string testDbPath = "data/lastfm.db";
    if check file:test(testDbPath, file:EXISTS) {
        check file:remove(testDbPath);
        io:println("Cleaned up test database");
    }
}

@test:Config {
    dependsOn: [testDbInitialization]
}
function testJsonMigration() returns error? {
    io:println("Testing JSON to SQLite migration...");

    // Configuration
    db:DbConfig config = {
        dbType: db:SQLITE,
        database: "data/lastfm.db"
    };

    // Créer le client DB
    db:DbClient dbClient = check db:createDbClient(config);

    // Migrer les données depuis le cache JSON
    db:MigrationResult result = check db:migrateFromJsonCache("data/cache.json", dbClient);

    io:println(string `Migration completed:`);
    io:println(string `  - Artists migrated: ${result.artistsMigrated}`);
    io:println(string `  - Tracks migrated: ${result.tracksMigrated}`);
    io:println(string `  - Errors: ${result.errors.length()}`);

    if result.errors.length() > 0 {
        foreach string err in result.errors {
            io:println(string `    Error: ${err}`);
        }
    }

    // Vérifier que les données ont été migrées
    test:assertTrue(result.artistsMigrated > 0 || result.tracksMigrated > 0,
        "At least some data should be migrated");

    // Fermer la connexion
    check dbClient.close();

    io:println("JSON migration test passed!");
}

@test:Config {
    dependsOn: [testJsonMigration]
}
function testListArtists() returns error? {
    io:println("\n=== Contenu de la table artists ===\n");

    db:DbConfig config = {
        dbType: db:SQLITE,
        database: "data/lastfm.db"
    };

    db:DbClient dbClient = check db:createDbClient(config);

    // Lister tous les artistes
    stream<record {}, sql:Error?> artistStream = check dbClient.query(
        `SELECT id, name, genres, quality_score, enriched_by_ai FROM artists ORDER BY name`
    );

    int count = 0;
    check from record {} artist in artistStream
        do {
            count += 1;
            string name = <string>artist["name"];
            string genres = <string>artist["genres"];
            decimal score = <decimal>artist["quality_score"];
            int ai = <int>artist["enriched_by_ai"];
            io:println(string `${count}. ${name} | genres: ${genres} | score: ${score} | AI: ${ai == 1 ? "oui" : "non"}`);
        };

    io:println(string `\nTotal: ${count} artistes`);

    check dbClient.close();
}
