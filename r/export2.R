library(tidyverse)
library(lubridate)
library(DBI)
library(sf)

catchments <- st_read("../public/data/geojson/catchments_ma.json")
featureids <- catchments$FEATUREID
# featureids <- 201411588

model_wd <- "~/data/ecosheds/temp-model/1.3.0/"
df_huc <- read_rds(file.path(model_wd, "data-huc.rds"))
m_in <- read_rds(file.path(model_wd, "model-input.rds"))
m_out <- read_rds(file.path(model_wd, "model-output.rds"))


# daymet ------------------------------------------------------------------

get_daymet_stats <- function (featureids, batch_size = 100) {
  batch_featureids <- featureids[1:min(batch_size, length(featureids))]
  remaining_featureids <- setdiff(featureids, batch_featureids)
  logger::log_info(glue::glue("fetching {length(batch_featureids)} ({length(remaining_featureids)} remaining)"))

  con <- dbConnect(RPostgres::Postgres(), host = "osensei.cns.umass.edu", port = 5434, dbname = "daymet", user = "jeff")
  sql <- paste0("
    WITH t1 AS (
    SELECT
      featureid, year,
      unnest(tmax) AS tmax,
      unnest(tmin) AS tmin,
      unnest(prcp) AS prcp
    FROM daymet
    WHERE featureid IN (",
      paste0("$", seq_along(batch_featureids), collapse = ", "),
    ")),
    t2 AS (
      SELECT
      featureid, year,
      row_number() OVER () as i,
      tmax, tmin, prcp
      FROM t1
    ),
    t3 AS (
      SELECT
      featureid, year,
      (DATE (year || '-01-01')) + ((row_number() OVER (PARTITION BY featureid, year ORDER BY i)) - 1)::integer AS date,
      tmax, tmin, prcp
      FROM t2
    )
    SELECT featureid, date, (tmax + tmin) / 2 as airTemp, prcp
    FROM t3
  ")
  rs <- dbSendQuery(con, sql, batch_featureids)
  df <- dbFetch(rs)
  dbClearResult(rs)
  dbDisconnect(con)
  
  x_day <- df %>%
    as_tibble() %>% 
    rename(airTemp = airtemp) %>% 
    group_by(featureid) %>% 
    mutate(
      featureid = as.numeric(featureid),
      airTempLagged1 = lag(airTemp, n = 1, fill = NA),
      temp7p = zoo::rollapply(
        data = airTempLagged1,
        width = 7,
        FUN = mean,
        align = "right",
        fill = NA,
        na.rm = TRUE
      ),
      prcp2 = zoo::rollsum(x = prcp, 2, align = "right", fill = NA),
      prcp30 = zoo::rollsum(x = prcp, 30, align = "right", fill = NA)
    ) %>%
    filter(month(date) == 7) %>% 
    select(featureid, date, airTemp, temp7p, prcp2, prcp30) %>% 
    ungroup()
  
  x_day_std <- x_day %>% 
    pivot_longer(-c(featureid, date)) %>% 
    left_join(m_in$std, by = c("name" = "var")) %>% 
    mutate(value = (value - mean) / sd) %>% 
    select(-mean, -sd) %>% 
    pivot_wider()
  
  x_mean <- x_day %>% 
    nest_by(featureid) %>% 
    summarise(
      daymet = list({
        tibble(airTemp = mean(data$airTemp), temp7p = mean(data$temp7p), prcp2 = mean(data$prcp2), prcp30 = mean(data$prcp30))
      }),
      .groups = "drop"
    )
  
  x_cov <- x_day_std %>% 
    nest_by(featureid) %>% 
    summarise(
      cov = list({
        tibble(airTemp.prcp2 = cov(data$airTemp, data$prcp2), airTemp.prcp30 = cov(data$airTemp, data$prcp30))
      }),
      .groups = "drop"
    )
  
  x <- left_join(x_mean, x_cov, by = "featureid")
    
  
  if (length(remaining_featureids) > 0) {
    return(bind_rows(x, get_daymet_stats(remaining_featureids, batch_size = batch_size)))
  } else {
    return(x)
  }
}

x_daymet <- get_daymet_stats(featureids, batch_size = 500)
write_rds(x_daymet, "daymet.rds")

x_daymet %>% 
  select(featureid, daymet) %>% 
  unnest(daymet) %>% 
  summary()
x_daymet %>% 
  select(featureid, cov) %>% 
  unnest(cov) %>% 
  summary()


# covariates --------------------------------------------------------------

x_covariates <- readRDS(file.path(model_wd, "data-covariates.rds")) %>%
  filter(featureid %in% featureids) %>% 
  mutate(
    allonnet = if_else(allonnet > 70, NA_real_, allonnet),
    impoundArea = AreaSqKM * allonnet / 100
  ) %>% 
  select(-allonnet) %>% 
  nest_by(featureid, .key = "covariates")

# coefficients ------------------------------------------------------------

coef_fixed <- data.frame(
  name = m_out$covs$fixed.ef,
  value = m_out$results$mean$B.0
)
b_fixed <- tibble(
  featureid = featureids,
  group = "fixed"
) %>% 
  crossing(coef_fixed)

coef_featureid <- as.data.frame(m_out$results$mean$B.site) %>% 
  set_names(m_out$covs$site.ef) %>% 
  rename(intercept = intercept.site) %>% 
  as_tibble() %>% 
  mutate(
    featureid = m_out$ids$site$featureid, .before = 1
  )
coef_featureid_mean <- coef_featureid %>% 
  summarise(across(-c(featureid), mean)) %>% 
  as.list()

b_featureid <- tibble(
  featureid = featureids,
  group = "featureid"
) %>% 
  left_join(coef_featureid, by = "featureid") %>% 
  mutate(
    intercept = coalesce(intercept, coef_featureid_mean$intercept),
    airTemp = coalesce(airTemp, coef_featureid_mean$airTemp),
    temp7p = coalesce(temp7p, coef_featureid_mean$temp7p)
  ) %>% 
  pivot_longer(-c(featureid, group))

coef_huc8 <- as.data.frame(m_out$results$mean$B.huc) %>% 
  set_names(m_out$covs$huc.ef) %>% 
  rename(intercept = intercept.huc) %>% 
  as_tibble() %>% 
  mutate(
    huc8 = m_out$ids$huc$huc8, .before = 1
  )
coef_huc8_mean <- coef_huc8 %>% 
  summarise(across(-c(huc8), mean)) %>% 
  as.list()

b_huc8 <- tibble(
  featureid = featureids,
  group = "huc8"
) %>% 
  left_join(select(df_huc, featureid, huc8), by = "featureid") %>% 
  left_join(coef_huc8, by = "huc8") %>% 
  mutate(
    intercept = coalesce(intercept, coef_huc8_mean$intercept),
    airTemp = coalesce(airTemp, coef_huc8_mean$airTemp),
    temp7p = coalesce(temp7p, coef_huc8_mean$temp7p)
  ) %>% 
  select(-huc8) %>% 
  pivot_longer(-c(featureid, group))

coef_year <- data.frame(
  year = m_out$ids$year$year,
  intercept_year = m_out$results$mean$B.year[, 1]
) %>% 
  complete(year = 1980:max(m_out$ids$year$year)) %>% 
  mutate(intercept_year = coalesce(intercept_year, mean(m_out$results$mean$B.year[, 1]))) %>% 
  summarise(value = mean(intercept_year)) %>% 
  mutate(name = "intercept", .before = 1)

b_year <- tibble(
  featureid = featureids,
  group = "year"
) %>% 
  crossing(coef_year)

x_coef <- bind_rows(
  b_fixed,
  b_huc8,
  b_featureid,
  b_year
) %>% 
  group_by(featureid, name) %>% 
  summarise(value = sum(value), .groups = "drop") %>% 
  pivot_wider() %>% 
  nest_by(featureid, .key = "coef")


# export -------------------------------------------------------------------


x_daymet
x_covariates
x_coef

x_all <- x_daymet %>% 
  full_join(x_covariates, by = "featureid") %>% 
  full_join(x_coef, by = "featureid") %>% 
  rowwise() %>% 
  transmute(
    featureid,
    covariates = list(c(daymet, covariates)),
    covariances = list(c(cov)),
    coefficients = list(c(coef))
  ) %>% 
  print


std <- m_in$std

x_adjust <- list(airTemp = 0, prcp = 1, forest = 1)
x_inp <- as_tibble(x_all$covariates[[1]])
x_inp_adj <- x_inp %>% 
  mutate(
    airTemp = airTemp + x_adjust$airTemp,
    temp7p = temp7p + x_adjust$airTemp,
    prcp2 = prcp2 * x_adjust$prcp,
    prcp30 = prcp30 * x_adjust$prcp,
    forest = forest * x_adjust$forest
  )
x_inp_adj_std <- x_inp_adj %>% 
  pivot_longer(everything()) %>% 
  left_join(std, by = c("name" =  "var")) %>% 
  mutate(value = (value - mean) / sd) %>% 
  select(name, value) %>% 
  pivot_wider()
x_inp_adj_std_int <- x_inp_adj_std %>% 
  mutate(
    prcp2.da = prcp2 * AreaSqKM,
    prcp30.da = prcp30 * AreaSqKM,
    airTemp.prcp2 = airTemp * prcp2 + x_all$covariances[[1]][["airTemp.prcp2"]] * x_adjust$prcp,
    airTemp.prcp2.da = (airTemp * prcp2 + x_all$covariances[[1]][["airTemp.prcp2"]] * x_adjust$prcp) * AreaSqKM,
    airTemp.prcp30 = airTemp * prcp30 + x_all$covariances[[1]][["airTemp.prcp30"]] * x_adjust$prcp,
    airTemp.prcp30.da = (airTemp * prcp30 + x_all$covariances[[1]][["airTemp.prcp30"]] * x_adjust$prcp) * AreaSqKM,
    airTemp.forest = airTemp * forest,
    airTemp.devel_hi = airTemp * devel_hi,
    airTemp.da = airTemp * AreaSqKM,
    airTemp.impoundArea = airTemp * impoundArea,
    airTemp.agriculture = airTemp * agriculture,
    intercept = 1
  )
x_pred <- x_inp_adj_std_int %>% 
  pivot_longer(everything()) %>% 
  left_join(
    as_tibble(x_all$coefficients[[1]]) %>% 
      pivot_longer(everything(), values_to = "beta"),
    by = "name"
  ) %>% 
  mutate(
    x = value * beta
  )
sum(x_pred$x)


compare_predict(201471023, list(airTemp = 2, prcp = 1.2, forest = 1)) 


# export ------------------------------------------------------------------

x_all

pb <- progress::progress_bar$new(total = nrow(x_all), format = "[:bar] :percent :eta")
for (i in 1:nrow(x_all)) {
  pb$tick()
  row <- x_all[i, ]
  filename <- glue::glue("../public/data/temp-model/{row$featureid}.json")
  list(
    featureid = row$featureid,
    val = row$covariates[[1]],
    cov = row$covariances[[1]],
    coef = row$coefficients[[1]],
    std = m_in$std %>% 
      select(-var) %>% 
      split(m_in$std$var) %>% 
      map(as.list)
  ) %>% 
    write_json(filename, pretty = TRUE, auto_unbox = TRUE)
}
