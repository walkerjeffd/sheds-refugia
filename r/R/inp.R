# functions ---------------------------------------------------------------

get_daymet <- function (featureids) {
  dotenv::load_dot_env()
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("OSENSEI_DAYMET_DB_HOST"),
    port = Sys.getenv("OSENSEI_DAYMET_DB_PORT"),
    dbname = Sys.getenv("OSENSEI_DAYMET_DB_DBNAME"),
    user = Sys.getenv("OSENSEI_DAYMET_DB_USER"),
    password = Sys.getenv("OSENSEI_DAYMET_DB_PASSWORD")
  )
  
  sql <- glue_sql("
    WITH t1 AS (
      SELECT
        featureid, year,
        unnest(tmax) AS tmax,
        unnest(tmin) AS tmin,
        unnest(prcp) AS prcp
      FROM daymet
      WHERE featureid IN ({featureids*})
    ), t2 AS (
      SELECT
        featureid, year,
        row_number() OVER () as i,
        tmax, tmin, prcp
      FROM t1
    )
    SELECT
      featureid,
      (DATE (year || '-01-01')) + ((row_number() OVER (PARTITION BY featureid, year ORDER BY i)) - 1)::integer AS date,
      (tmax + tmin) / 2 as airTemp, prcp
    FROM t2
  ", .con = con)
  x <- DBI::dbGetQuery(con, sql)
  DBI::dbDisconnect(con)
  
  x |>
    as_tibble() |>
    rename(airTemp = airtemp) |> 
    mutate(
      featureid = as.numeric(featureid),
      temp7p = zoo::rollapply(
        data = lag(airTemp, n = 1, fill = NA),
        width = 7,
        FUN = mean,
        align = "right",
        fill = NA,
        na.rm = TRUE
      ),
      prcp2 = zoo::rollsum(x = prcp, 2, align = "right", fill = NA),
      prcp30 = zoo::rollsum(x = prcp, 30, align = "right", fill = NA)
    )
}
# get_daymet(c(201411588, 201411589))

get_daymet_stats <- function (featureids, std, batch_size = 500) {
  # featureids: vector
  # std: df[var, mean, sd]
  
  batch_featureids <- featureids[1:min(batch_size, length(featureids))]
  remaining_featureids <- setdiff(featureids, batch_featureids)
  logger::log_info(glue::glue("fetching {length(batch_featureids)} ({length(remaining_featureids)} remaining)"))
  
  x_day <- get_daymet(featureids) |>
    select(featureid, date, airTemp, temp7p, prcp2, prcp30) |> 
    filter(month(date) == 7)
  
  x_day_std <- x_day |> 
    pivot_longer(-c(featureid, date)) |> 
    left_join(std, by = c("name" = "var")) |> 
    mutate(value = (value - mean) / sd) |> 
    select(-mean, -sd) |> 
    pivot_wider()
  
  x_mean <- x_day |> 
    nest_by(featureid) |> 
    summarise(
      daymet = list({
        tibble(
          airTemp = mean(data$airTemp), 
          temp7p = mean(data$temp7p), 
          prcp2 = mean(data$prcp2), 
          prcp30 = mean(data$prcp30))
      }),
      .groups = "drop"
    )
  
  x_cov <- x_day_std |> 
    nest_by(featureid) |> 
    summarise(
      cov = list({
        tibble(
          airTemp.prcp2 = cov(data$airTemp, data$prcp2),
          airTemp.prcp30 = cov(data$airTemp, data$prcp30)
        )
      }),
      .groups = "drop"
    )
  
  x_stats <- left_join(x_mean, x_cov, by = "featureid")
  
  
  if (length(remaining_featureids) > 0) {
    return(bind_rows(x_stats, get_daymet_stats(remaining_featureids, batch_size = batch_size)))
  } else {
    return(x_stats)
  }
}

# targets -----------------------------------------------------------------

targets_inp <- list(
  # tar_target(inp_daymet, get_daymet_stats(featureids[1:1000], temp_model_std)),
  tar_target(inp_daymet, read_rds("daymet.rds")),
  tar_target(inp_covariates, {
    temp_model_covariates |>
      filter(featureid %in% featureids) |>
      mutate(
        allonnet = if_else(allonnet > 70, NA_real_, allonnet),
        impoundArea = AreaSqKM * allonnet / 100
      ) |>
      select(-allonnet) |>
      nest_by(featureid, .key = "covariates")
  }),
  tar_target(inp, {
    inp_daymet |> 
      full_join(inp_covariates, by = "featureid") |> 
      full_join(temp_model_coef, by = "featureid") |> 
      rowwise() |> 
      transmute(
        featureid,
        covariates = list(c(daymet, covariates)),
        covariances = list(c(cov)),
        coefficients = list(c(coef))
      )
  })
)