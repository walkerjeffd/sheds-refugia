db_connect <- function() {
  dotenv::load_dot_env()
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("SHEDS_DB_HOST"),
    port = Sys.getenv("SHEDS_DB_PORT"),
    dbname = Sys.getenv("SHEDS_DB_DBNAME"),
    user = Sys.getenv("SHEDS_DB_USER"),
    password = Sys.getenv("SHEDS_DB_PASSWORD")
  )
}
