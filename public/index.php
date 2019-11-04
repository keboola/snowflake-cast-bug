<?php
require_once __DIR__ . '/../vendor/autoload.php';

$dotenv = new Symfony\Component\Dotenv\Dotenv();
$dotenv->loadEnv(__DIR__ . '/../.env');

$database = getenv('SNOWFLAKE_DATABASE');
$schema = getenv('SNOWFLAKE_SCHEMA');
$table = getenv('SNOWFLAKE_TABLE');

$randomString1 = createRandomString(20000, "🐱️👬🐇🐐🦖");
$randomString2 = createRandomString(20000, "🐱️👬🐇🐐🦖");
$insertQuery = "insert into $database.$schema.$table values ('$randomString1', '$randomString2')";

$snowflakeConnection = new SnowflakePDOConnection();
$snowflakeConnection
    // ->executeCommand("create database if not exists $database")
    // ->executeCommand("create schema if not exists $database.$schema")
    ->executeCommand("create table if not exists $database.$schema.$table (col1 varchar, col2 varchar)")
    ->executeCommand("truncate $database.$schema.$table")
    ->executeCommand($insertQuery);

$selectQuery = "
select
    CAST(SUBSTRING(col1, 0, 256) as VARCHAR(256)) as col1,
    CAST(SUBSTRING(col2, 0, 256) as VARCHAR(256)) as col2
from $database.$schema.$table
";

echo '<pre>';
echo $selectQuery;

$rows = $snowflakeConnection->fetchAll($selectQuery);

var_dump($rows);

class SnowflakePDOConnection
{
    /**
     * @var PDO
     */
    private $connection;

    public function __construct()
    {
        $connection = new PDO("snowflake:account=" . getenv('SNOWFLAKE_ACCOUNT'), getenv('SNOWFLAKE_USERNAME'), getenv('SNOWFLAKE_PASSWORD'));
        $connection->query("USE DATABASE " . getenv('SNOWFLAKE_DATABASE'));
        $connection->query("USE WAREHOUSE " . getenv('SNOWFLAKE_WAREHOUSE'));
        $connection->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->connection = $connection;
    }

    public function fetchAll(string $sql): array
    {
        return $this->connection->query($sql)->fetchAll();
    }

    public function executeCommand(string $sql): SnowflakePDOConnection
    {
        $this->connection->query($sql);
        return $this;
    }
}

class SnowflakeConnection
{
    private $connection;

    public function __construct()
    {
        $dsn = 'Driver=SnowflakeDSIIDriver;';
        $dsn .= 'Server=' . getenv('SNOWFLAKE_SERVER') . ';';
        $dsn .= 'Port=443;';
        $dsn .= 'Tracing=0;';
        $dsn .= 'Database="' . getenv('SNOWFLAKE_DATABASE') . '";';
        $dsn .= 'Warehouse="' . getenv('SNOWFLAKE_WAREHOUSE') . '"';

        $attemptNumber = 0;
        $maxBackoffAttempts = 5;
        while ($this->connection === null) {
            try {
                $this->connection = odbc_connect($dsn, getenv('SNOWFLAKE_USERNAME'), getenv('SNOWFLAKE_PASSWORD'));
            } catch (\Throwable $e) {
                // try again if it is a failed rest request
                if (stristr($e->getMessage(), "S1000") !== false) {
                    $attemptNumber++;
                    if ($attemptNumber > $maxBackoffAttempts) {
                        throw new \Exception("Initializing Snowflake connection failed: " . $e->getMessage(), 0, $e);
                    }
                } else {
                    throw new \Exception("Initializing Snowflake connection failed: " . $e->getMessage(), 0, $e);
                }
            }
        }
    }

    public function fetchAll(string $sql): array
    {
        try {
            $stmt = odbc_prepare($this->connection, $sql);
            odbc_execute($stmt);
            $rows = [];
            while ($row = odbc_fetch_array($stmt)) {
                $rows[] = $row;
            }
            odbc_free_result($stmt);
        } catch (\Throwable $e) {
            throw (new \Exception())->createException($e);
        }
        return $rows;
    }

    public function executeCommand(string $sql): SnowflakeConnection
    {
        try {
            $stmt = odbc_prepare($this->connection, $sql);
            odbc_execute($stmt);
            odbc_free_result($stmt);
        } catch (\Throwable $e) {
            throw (new \Exception())->createException($e);
        }
        return $this;
    }
}

function createRandomString(int $length, $alphabet = "abcdefghijklmnopqrstvuwxyz0123456789 ")
{
    $randStr = "";
    for ($i = 0; $i < $length; $i++) {
        $randStr .= mb_substr($alphabet, rand(0, mb_strlen($alphabet) - 1), 1);
    }
    return $randStr;
}
