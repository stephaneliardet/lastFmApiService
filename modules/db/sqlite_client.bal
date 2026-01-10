// Implémentation du client SQLite via JDBC

import ballerina/file;
import ballerina/log;
import ballerina/sql;
import ballerinax/java.jdbc;

# Client SQLite implémentant l'interface DbClient
public isolated class SqliteClient {
    *DbClient;

    private final jdbc:Client dbClient;
    private final string dbPath;

    # Initialise le client SQLite
    #
    # + config - Configuration de la base de données
    # + autoMigrate - Exécuter automatiquement les migrations si true
    # + return - Erreur éventuelle
    public isolated function init(DbConfig config, boolean autoMigrate = true) returns error? {
        self.dbPath = config.database;

        // Vérifier si la base de données existe déjà
        boolean dbExists = check file:test(self.dbPath, file:EXISTS);

        // Créer le répertoire parent si nécessaire
        string? parentDir = check file:parentPath(self.dbPath);
        if parentDir is string && parentDir.length() > 0 {
            if !check file:test(parentDir, file:EXISTS) {
                check file:createDir(parentDir, file:RECURSIVE);
                log:printInfo(string `Created directory: ${parentDir}`);
            }
        }

        // Construire l'URL JDBC pour SQLite
        // SQLite crée automatiquement le fichier s'il n'existe pas
        string jdbcUrl = string `jdbc:sqlite:${self.dbPath}`;

        self.dbClient = check new (
            url = jdbcUrl,
            options = {
                properties: {
                    "foreign_keys": "ON"
                }
            }
        );

        if dbExists {
            log:printInfo(string `SQLite database connected: ${self.dbPath}`);
        } else {
            log:printInfo(string `SQLite database created: ${self.dbPath}`);
        }

        // Exécuter les migrations automatiquement si demandé
        if autoMigrate {
            check self.initializeSchema();
        }
    }

    # Initialise le schéma de la base de données via les migrations
    #
    # + return - Erreur éventuelle
    public isolated function initializeSchema() returns error? {
        check runMigrations(self);
    }

    # Exécute une requête SQL qui ne retourne pas de résultat
    #
    # + query - Requête SQL paramétrée
    # + return - Résultat de l'exécution ou erreur
    public isolated function execute(sql:ParameterizedQuery query) returns ExecutionResult|error {
        sql:ExecutionResult result = check self.dbClient->execute(query);
        int? lastId = ();
        if result.lastInsertId is int {
            lastId = <int>result.lastInsertId;
        }
        return {
            affectedRows: <int>result.affectedRowCount,
            lastInsertId: lastId
        };
    }

    # Exécute une requête SQL qui retourne des résultats
    #
    # + query - Requête SQL paramétrée
    # + return - Stream de résultats ou erreur
    public isolated function query(sql:ParameterizedQuery query)
            returns stream<record {}, sql:Error?>|error {
        return self.dbClient->query(query);
    }

    # Exécute une requête SQL qui retourne une seule ligne
    #
    # + query - Requête SQL paramétrée
    # + return - Ligne ou nil si non trouvée, ou erreur
    public isolated function queryOne(sql:ParameterizedQuery query)
            returns record {}?|error {
        stream<record {}, sql:Error?> resultStream = check self.query(query);
        record {|record {} value;|}? next = check resultStream.next();
        check resultStream.close();
        if next is record {|record {} value;|} {
            return next.value;
        }
        return ();
    }

    # Exécute plusieurs requêtes SQL en batch
    #
    # + queries - Liste de requêtes SQL paramétrées
    # + return - Résultats de l'exécution ou erreur
    public isolated function batchExecute(sql:ParameterizedQuery[] queries) returns ExecutionResult[]|error {
        sql:ExecutionResult[] results = check self.dbClient->batchExecute(queries);
        ExecutionResult[] executionResults = [];
        foreach sql:ExecutionResult result in results {
            int? lastId = ();
            if result.lastInsertId is int {
                lastId = <int>result.lastInsertId;
            }
            executionResults.push({
                affectedRows: <int>result.affectedRowCount,
                lastInsertId: lastId
            });
        }
        return executionResults;
    }

    # Démarre une transaction (SQLite gère automatiquement les transactions)
    #
    # + return - Erreur éventuelle
    public isolated function beginTransaction() returns error? {
        _ = check self.dbClient->execute(`BEGIN TRANSACTION`);
    }

    # Valide une transaction
    #
    # + return - Erreur éventuelle
    public isolated function commitTransaction() returns error? {
        _ = check self.dbClient->execute(`COMMIT`);
    }

    # Annule une transaction
    #
    # + return - Erreur éventuelle
    public isolated function rollbackTransaction() returns error? {
        _ = check self.dbClient->execute(`ROLLBACK`);
    }

    # Ferme la connexion à la base de données
    #
    # + return - Erreur éventuelle
    public isolated function close() returns error? {
        check self.dbClient.close();
        log:printInfo("SQLite connection closed");
    }

    # Vérifie si la connexion est active
    #
    # + return - true si connecté, false sinon
    public isolated function isConnected() returns boolean {
        // Tenter une requête simple pour vérifier la connexion
        sql:ParameterizedQuery query = `SELECT 1`;
        record {}?|error result = self.queryOne(query);
        return result is record {};
    }

    # Retourne le type de base de données
    #
    # + return - SQLITE
    public isolated function getDbType() returns DbType {
        return SQLITE;
    }
}
