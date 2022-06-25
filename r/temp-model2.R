library(tidyverse)
library(lubridate)
library(DBI)

model_wd <- "~/data/ecosheds/temp-model/1.3.0/"

stopifnot(dir.exists(model_wd))

df_huc <- read_rds(file.path(model_wd, "data-huc.rds"))
m_in <- read_rds(file.path(model_wd, "model-input.rds"))
m_out <- read_rds(file.path(model_wd, "model-output.rds"))
# variable_std <- m_in$std


# daymet ------------------------------------------------------------------

get_daymet <- function (featureids) {
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
                paste0("$", seq_along(featureids), collapse = ", "),
                ")), t2 AS (
                       SELECT
                       featureid, year,
                       row_number() OVER () as i,
                       tmax, tmin, prcp
                       FROM t1
                       )
                       SELECT
                       featureid, year,
                       (DATE (year || '-01-01')) + ((row_number() OVER (PARTITION BY featureid, year ORDER BY i)) - 1)::integer AS date,
                       tmax, tmin, prcp
                       FROM t2
                       ")
  rs <- dbSendQuery(con, sql, featureids)
  df <- dbFetch(rs)%>%
    as_tibble()
  dbClearResult(rs)
  dbDisconnect(con)
  
  df %>%
    mutate(
      featureid = as.numeric(featureid),
      airTemp = (tmin + tmax) / 2,
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
    select(-tmin, -tmax)
}

get_daymet(201411588)



# inputs ------------------------------------------------------------------

adjust_inp <- function (x, adjust) {
  x %>% 
    mutate(
      airTemp = airTemp + adjust$airTemp,
      temp7p = temp7p + adjust$airTemp,
      prcp2 = prcp2 * adjust$prcp,
      prcp30 = prcp30 * adjust$prcp,
      forest = forest * adjust$forest
    )
} 

covariates <- readRDS(file.path(model_wd, "data-covariates.rds")) %>%
  filter(
    AreaSqKM <= 200,
    allonnet < 70
  ) %>%
  mutate(
    impoundArea = AreaSqKM * allonnet / 100
  ) %>% 
  select(-allonnet)
covariates <- covariates[complete.cases(covariates), ]


create_inp_daily <- function (featureid, adjust = list(airTemp = 0, prcp = 1, forest = 1)) {
  x_daymet <- get_daymet(featureid)
  
  x_daymet %>%
    mutate(year = year(date)) %>% 
    left_join(df_huc, by = "featureid") %>% 
    left_join(covariates, by = "featureid") %>%
    left_join(m_out$ids$site, by = "featureid") %>%
    left_join(m_out$ids$huc, by = "huc8") %>%
    left_join(m_out$ids$year, by = "year") %>% 
    select(
      featureid, featureid_id, huc8, huc8_id, year, year_id, date,
      airTemp, prcp2, prcp30, temp7p,
      AreaSqKM, forest, devel_hi, agriculture, impoundArea
    ) %>% 
    adjust_inp(adjust)
}

create_inp_daily(201411588)
create_inp_daily(201411588, list(airTemp = 2, prcp = 1.1, forest = 1.1))


# standardize -------------------------------------------------------------

standardize_inp <- function (x) {
  x %>%
    gather(var, value, -featureid, -featureid_id, -huc8, -huc8_id, -year, -year_id, -date) %>%
    left_join(m_in$std, by = "var") %>%
    mutate(value = (value - mean) / sd) %>%
    select(-mean, -sd) %>%
    spread(var, value) %>%
    mutate(
      prcp2.da = prcp2 * AreaSqKM,
      prcp30.da = prcp30 * AreaSqKM,
      airTemp.prcp2 = airTemp * prcp2,
      airTemp.prcp2.da = airTemp * prcp2 * AreaSqKM,
      airTemp.prcp30 = airTemp * prcp30,
      airTemp.prcp30.da = airTemp * prcp30 * AreaSqKM,
      airTemp.forest = airTemp * forest,
      airTemp.devel_hi = airTemp * devel_hi,
      airTemp.da = airTemp * AreaSqKM,
      airTemp.impoundArea = airTemp * impoundArea,
      airTemp.agriculture = airTemp * agriculture,
      intercept = 1,
      intercept.site = 1,
      intercept.huc = 1,
      intercept.year = 1
    )
}

standardize_inp(create_inp_daily(201411588))


# daily model -------------------------------------------------------------

predict_daily <- function(featureid, adjust = list(airTemp = 0, prcp = 1, forest = 1)) {
  x_daily <- create_inp_daily(featureid, adjust) %>% 
    standardize_inp() %>% 
    filter(month(date) == 7)
  
  B.site.mean <- colMeans(m_out$results$mean$B.site)
  B.huc.mean <- colMeans(m_out$results$mean$B.huc)
  B.year.mean <- colMeans(m_out$results$mean$B.year)
  
  # compute predictions
  X.0 <- x_daily %>%
    select(one_of(m_out$covs$fixed.ef)) %>%
    as.matrix()
  B.0 <- as.matrix(m_out$results$mean$B.0)
  Y.0 <- (X.0 %*% B.0)[, 1]
  
  X.site <- x_daily %>%
    select(one_of(m_out$covs$site.ef)) %>%
    as.matrix()
  B.site <- m_out$results$mean$B.site[x_daily$featureid_id, ]
  for (i in seq_along(B.site.mean)) {
    B.site[is.na(B.site[, i]), i] <- B.site.mean[i]
  }
  Y.site <- rowSums(X.site * B.site)
  
  X.huc <- x_daily %>%
    select(one_of(m_out$covs$huc.ef)) %>%
    as.matrix()
  B.huc <- m_out$results$mean$B.huc[x_daily$huc8_id, ]
  for (i in seq_along(B.huc.mean)) {
    B.huc[is.na(B.huc[, i]), i] <- B.huc.mean[i]
  }
  Y.huc <- rowSums(X.huc * B.huc)
  
  X.year <- x_daily %>%
    select(one_of(m_out$covs$year.ef)) %>%
    as.matrix()
  B.year <- as.matrix(m_out$results$mean$B.year[x_daily$year_id, ])
  for (i in seq_along(B.year.mean)) {
    B.year[is.na(B.year[, i]), i] <- B.year.mean[i]
  }
  Y.year <- rowSums(X.year * B.year)
  
  x_daily$temp_fixed <- Y.0
  x_daily$temp_huc8 <- Y.huc
  x_daily$temp_catchment <- Y.site
  x_daily$temp_year <- Y.year
  x_daily$temp <- Y.0 + Y.site + Y.year + Y.huc
  
  x_daily
}

predict_daily(201411588, list(airTemp = 0, prcp = 1, forest = 1)) %>% 
  pull(temp) %>% 
  mean()

# coefficients ------------------------------------------------------------

get_coef <- function (featureid) {
  featureid_id <- m_out$ids$site$featureid_id[m_out$ids$site$featureid == featureid]
  huc8 <- df_huc$huc8[df_huc$featureid == featureid]
  huc8_id <- m_out$ids$huc$huc8_id[m_out$ids$huc$huc8 == huc8]
  
  coef_fixed <- data.frame(
    name = m_out$covs$fixed.ef,
    value = m_out$results$mean$B.0
  )
  
  if (length(huc8_id) == 1) {
    coef_huc8 <- data.frame(name = m_out$covs$huc.ef, value = m_out$results$mean$B.huc[huc8_id, ])
  } else {
    coef_huc8 <- data.frame(name = m_out$covs$huc.ef, value = colMeans(m_out$results$mean$B.huc))
  }
  if (length(featureid_id) == 1) {
    coef_catchment <- data.frame(name = m_out$covs$site.ef, value = m_out$results$mean$B.site[featureid_id, ])
  } else {
    coef_catchment <- data.frame(name = m_out$covs$site.ef, value = colMeans(m_out$results$mean$B.site))
  }
  
  coef_year <- data.frame(
    year = m_out$ids$year$year,
    intercept_year = m_out$results$mean$B.year[, 1]
  ) %>% 
    complete(year = 1980:max(m_out$ids$year$year)) %>% 
    mutate(intercept_year = coalesce(intercept_year, mean(m_out$results$mean$B.year[, 1]))) %>% 
    summarise(value = mean(intercept_year)) %>% 
    mutate(name = "intercept")
  
  coef_fixed %>% 
    select(name, b_fix = value) %>% 
    full_join(
      coef_huc8 %>% 
        select(name, b_huc = value) %>% 
        mutate(name = if_else(name == "intercept.huc", "intercept", name)),
      by = "name"
    ) %>% 
    full_join(
      coef_catchment %>% 
        select(name, b_catchment = value) %>% 
        mutate(name = if_else(name == "intercept.site", "intercept", name)),
      by = "name"
    ) %>% 
    full_join(
      coef_year %>% 
        select(name, b_year = value),
      by = "name"
    ) %>% 
    mutate(
      across(starts_with("b_"), ~ coalesce(.x, 0)),
      b = b_fix + b_huc + b_catchment + b_year
    )
}

get_coef(201411588)
featureid <- 201411588

# mean --------------------------------------------------------------------

compute_inp_covariance <- function (featureid) {
  x <- create_inp_daily(featureid) %>% 
    filter(month(date) == 7) %>% 
    standardize_inp()
  
  list(
    airTemp.prcp2 = with(x, (1 - 1 / nrow(x)) * cov(airTemp, prcp2)),
    airTemp.prcp30 = with(x, (1 - 1 / nrow(x)) * cov(airTemp, prcp30))
  )
}
compute_inp_covariance(201411588)

create_inp_mean <- function (featureid, adjust = list(airTemp = 0, prcp = 1, forest = 1)) {
  x_inp_daily <- create_inp_daily(featureid) %>% 
    filter(month(date) == 7)
  
  x_inp_daily %>% 
    select(airTemp:impoundArea) %>% 
    summarise(across(everything(), mean)) %>% 
    adjust_inp(adjust)
}
x_inp <- create_inp_mean(201411588, list(airTemp = 0, prcp = 1, forest = 1))

standardize_inp_mean <- function (x, covariance, adjust = list(airTemp = 0, prcp = 1, forest = 1)) {
  x %>% 
    pivot_longer(everything()) %>% 
    left_join(m_in$std, by = c("name" = "var")) %>% 
    mutate(value = (value - mean) / sd) %>% 
    select(-mean, -sd) %>% 
    pivot_wider() %>% 
    mutate(
      prcp2.da = prcp2 * AreaSqKM,
      prcp30.da = prcp30 * AreaSqKM,
      airTemp.prcp2 = airTemp * prcp2 + covariance[["airTemp.prcp2"]] * adjust$prcp,
      airTemp.prcp2.da = (airTemp * prcp2 + covariance[["airTemp.prcp2"]] * adjust$prcp) * AreaSqKM,
      airTemp.prcp30 = airTemp * prcp30 + covariance[["airTemp.prcp30"]] * adjust$prcp,
      airTemp.prcp30.da = (airTemp * prcp30 + covariance[["airTemp.prcp30"]] * adjust$prcp) * AreaSqKM,
      airTemp.forest = airTemp * forest,
      airTemp.devel_hi = airTemp * devel_hi,
      airTemp.da = airTemp * AreaSqKM,
      airTemp.impoundArea = airTemp * impoundArea,
      airTemp.agriculture = airTemp * agriculture,
      intercept = 1
    )
}

create_inp_mean(201411588, list(airTemp = 0, prcp = 1.2, forest = 1)) %>% 
  standardize_inp_mean(compute_inp_covariance(201411588), list(airTemp = 0, prcp = 1.2, forest = 1)) %>% 
  pivot_longer(everything(), values_to = "mean") %>% 
  left_join(
    predict_daily(201411588, list(airTemp = 0, prcp = 1.2, forest = 1)) %>% 
      filter(month(date) == 7) %>% 
      select(agriculture:airTemp.agriculture) %>% 
      summarise(across(everything(), mean)) %>% 
      pivot_longer(everything(), values_to = "daily"),
    by = "name"
  ) %>% 
  mutate(diff = mean - daily) %>% 
  print(n = Inf)

predict_mean <- function(featureid, adjust = list(airTemp = 0, prcp = 1, forest = 1)) {
  x_inp_mean <- create_inp_mean(featureid) %>% 
    adjust_inp(adjust)
  x_covariance <- compute_inp_covariance(featureid)
  x_inp_mean_std <- standardize_inp_mean(x_inp_mean, x_covariance, adjust)
  x_coef <- get_coef(featureid)
  
  x_inp_mean_std %>% 
    pivot_longer(everything()) %>% 
    left_join(x_coef, by = "name") %>% 
    mutate(temp = value * b) %>% view
    pull(temp) %>% 
    sum()
}
compare_predict <- function (featureid, adjust) {
  c(
    "mean" = predict_mean(featureid, adjust),
    "daily" = predict_daily(featureid, adjust) %>% 
      pull(temp) %>% 
      mean()
  )
}

compare_predict(featureid = 201411588, adjust = list(airTemp = 0, prcp = 1.2, forest = 1))
compare_predict(201411588, list(airTemp = 2, prcp = 1.2, forest = 1))

create_inp_mean(featureid) %>% 
  adjust_inp(adjust) %>% 
  standardize_inp_mean(compute_inp_covariance(featureid)) %>% 
  pivot_longer(everything(), values_to = "mean") %>% 
  left_join(
    predict_daily(featureid, adjust) %>% 
      select(agriculture:airTemp.agriculture) %>% 
      summarise(across(everything(), mean)) %>% 
      pivot_longer(everything(), values_to = "daily"),
    by = "name"
  ) %>% 
  mutate(diff = mean - daily) %>% 
  print(n = Inf)


predict_daily(201411588, list(airTemp = 0, prcp = 1.2, forest = 1))

x <- create_inp_daily(201411588, list(airTemp = 0, prcp = 1.2, forest = 1)) %>% 
  filter(month(date) == 7)
x_std <- standardize_inp(x)

x_var_std <- list(
  airTemp = m_in$std %>% 
    filter(var == "airTemp") %>% 
    select(-var) %>% 
    as.list(),
  prcp2 = m_in$std %>% 
    filter(var == "prcp2") %>% 
    select(-var) %>% 
    as.list()
)

x_airTemp <- x$airTemp
x_airTemp_std <- (x_airTemp - x_var_std$airTemp$mean) / x_var_std$airTemp$sd
mean(x_airTemp_std)
mean(x_std$airTemp)

x_prcp2 <- x$prcp2
x_prcp2_std <- (x_prcp2 - x_var_std$prcp2$mean) / x_var_std$prcp2$sd
mean(x_prcp2_std)
mean(x_std$prcp2)

x_cov <- (1 - 1 / length(x_airTemp_std)) * cov(x_airTemp_std, x_prcp2_std)
print(x_cov)

mean(x_airTemp_std) * mean(x_prcp2_std) + x_cov
mean(x_airTemp_std * x_prcp2_std)
mean(x_std$airTemp.prcp2)

mean(x_airTemp * x_prcp2)
mean(x_airTemp) * mean(x_prcp2) + (1 - 1 / length(x_airTemp)) * cov(x_airTemp, x_prcp2)

mean((x_airTemp + 2) * (1.2 * x_prcp2))
(mean(x_airTemp) + 2) * (1.2 * mean(x_prcp2)) + (1 - 1 / length(x_airTemp)) * cov(x_airTemp, x_prcp2) * 1.2
