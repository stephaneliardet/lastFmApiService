// Interface abstraite pour les clients de base de données
// Permet de changer de moteur DB sans modifier le code métier

import ballerina/sql;

# Interface abstraite pour un client de base de données.
# Toute implémentation (SQLite, PostgreSQL, MySQL) doit implémenter cette interface.
public type DbClient isolated object {

    # Exécute une requête SQL qui ne retourne pas de résultat (INSERT, UPDATE, DELETE)
    #
    # + query - Requête SQL paramétrée
    # + return - Résultat de l'exécution ou erreur
    public isolated function execute(sql:ParameterizedQuery query) returns ExecutionResult|error;

    # Exécute une requête SQL qui retourne des résultats (SELECT)
    #
    # + query - Requête SQL paramétrée
    # + return - Stream de résultats ou erreur
    public isolated function query(sql:ParameterizedQuery query)
        returns stream<record {}, sql:Error?>|error;

    # Exécute une requête SQL qui retourne une seule ligne
    #
    # + query - Requête SQL paramétrée
    # + return - Ligne ou nil si non trouvée, ou erreur
    public isolated function queryOne(sql:ParameterizedQuery query)
        returns record {}?|error;

    # Exécute plusieurs requêtes SQL en batch
    #
    # + queries - Liste de requêtes SQL paramétrées
    # + return - Résultats de l'exécution ou erreur
    public isolated function batchExecute(sql:ParameterizedQuery[] queries) returns ExecutionResult[]|error;

    # Démarre une transaction
    #
    # + return - Erreur éventuelle
    public isolated function beginTransaction() returns error?;

    # Valide une transaction
    #
    # + return - Erreur éventuelle
    public isolated function commitTransaction() returns error?;

    # Annule une transaction
    #
    # + return - Erreur éventuelle
    public isolated function rollbackTransaction() returns error?;

    # Ferme la connexion à la base de données
    #
    # + return - Erreur éventuelle
    public isolated function close() returns error?;

    # Vérifie si la connexion est active
    #
    # + return - true si connecté, false sinon
    public isolated function isConnected() returns boolean;

    # Retourne le type de base de données
    #
    # + return - Type de DB (SQLITE, POSTGRESQL, etc.)
    public isolated function getDbType() returns DbType;

    # Initialise le schéma de la base de données (crée les tables si nécessaire)
    #
    # + return - Erreur éventuelle
    public isolated function initializeSchema() returns error?;
};

# Factory pour créer un client de base de données selon la configuration
#
# + config - Configuration de la base de données
# + autoMigrate - Exécuter automatiquement les migrations (défaut: true)
# + return - Client DB ou erreur
public isolated function createDbClient(DbConfig config, boolean autoMigrate = true) returns DbClient|error {
    match config.dbType {
        SQLITE => {
            return new SqliteClient(config, autoMigrate);
        }
        POSTGRESQL => {
            return error("PostgreSQL client not yet implemented");
        }
        MYSQL => {
            return error("MySQL client not yet implemented");
        }
        _ => {
            return error("Unknown database type");
        }
    }
}
