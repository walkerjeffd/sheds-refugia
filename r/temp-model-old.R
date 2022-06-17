# run from temp-model repo

library(RPostgreSQL)
library(tidyverse)
library(jsonlite)
library(lubridate)
library(zoo)
library(stringr)

source("functions.R")

config <- load_config()

# featureids <- 20625492
# featureids <- 201411588
# adjust_air_temps <- c(0, 2)


# load model --------------------------------------------------------------

m_in <- readRDS(file.path(config$wd, "model-input.rds"))
m_out <- readRDS(file.path(config$wd, "model-output.rds"))

df_cov_std <- m_in$std
cov_list <- m_out$covs
ids_list <- m_in$ids

B.site.mean <- colMeans(m_out$results$mean$B.site)
B.huc.mean <- colMeans(m_out$results$mean$B.huc)
B.year.mean <- colMeans(m_out$results$mean$B.year)

coef_list <- list(
  fixed = m_out$results$mean$B.0,
  site = m_out$results$mean$B.site,
  huc = m_out$results$mean$B.huc,
  year = m_out$results$mean$B.year
)

df_huc <- readRDS(file.path(config$wd, "data-huc.rds"))
df_covariates <- readRDS(file.path(config$wd, "data-covariates.rds")) %>%
  filter(
    AreaSqKM <= 200,
    allonnet < 70
  ) %>%
  mutate(
    impoundArea = AreaSqKM * allonnet / 100
  )
df_covariates <- df_covariates[complete.cases(df_covariates), ]


# load covariates ---------------------------------------------------------

create_input <- function(featureid, delta) {
  con <- dbConnect(PostgreSQL(), host = "osensei.cns.umass.edu", dbname = "daymet", user = "jeff")
  sql_daymet <- paste0("
                       WITH t1 AS (
                       SELECT
                       featureid, year,
                       unnest(tmax) AS tmax,
                       unnest(tmin) AS tmin,
                       unnest(prcp) AS prcp
                       FROM daymet
                       WHERE featureid IN (",
                       paste0("$", seq_along(featureid), collapse = ", "),
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
  rs <- dbSendQuery(con, sql_daymet, featureid)
  df_daymet <- dbFetch(rs)%>%
    as_tibble()
  dbClearResult(rs)
  dbDisconnect(con)
  
  df_daymet_inp <- df_daymet %>%
    mutate(
      adjust_air_temp = delta,
      airTemp = (tmin + tmax) / 2 + adjust_air_temp,
      airTempLagged1 = lag(airTemp, n = 1, fill = NA),
      temp7p = rollapply(
        data = airTempLagged1,
        width = 7,
        FUN = mean,
        align = "right",
        fill = NA,
        na.rm = TRUE
      ),
      prcp2 = rollsum(x = prcp, 2, align = "right", fill = NA),
      prcp30 = rollsum(x = prcp, 30, align = "right", fill = NA)
    ) %>%
    select(-tmin, -tmax)
  
  df_inp <- df_covariates %>%
    filter(featureid %in% !!featureid) %>%
    left_join(df_huc, by = "featureid") %>%
    left_join(df_daymet_inp, by = "featureid") %>%
    mutate(
      spring_bp = 75,
      fall_bp = 330
    ) %>%
    mutate(
      dOY = yday(date)
    ) %>%
    filter(
      dOY >= spring_bp,
      dOY <= fall_bp
    ) %>%
    select(
      adjust_air_temp, featureid, huc8, year, date,
      airTemp, prcp2, prcp30, temp7p,
      AreaSqKM, forest, devel_hi, agriculture, impoundArea
    )
  
  # standardize covariates
  df_inp_std <- df_inp %>%
    gather(var, value, -adjust_air_temp, -featureid, -huc8, -year, -date) %>%
    left_join(df_cov_std, by = "var") %>%
    mutate(value = (value - mean) / sd) %>%
    select(-mean, -sd) %>%
    spread(var, value)
  
  # compute derived covariates
  df_inp_derived <- df_inp_std %>%
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
  
  # add id columns
  df_inp_derived %>%
    left_join(ids_list$featureid, by = "featureid") %>%
    left_join(ids_list$huc8, by = "huc8") %>%
    left_join(ids_list$year, by = "year")
}

x0 <- create_input(201411588, 0)
x2 <- create_input(201411588, 2)


# daily predictions -------------------------------------------------------

predict_daily <- function(x) {
  # compute predictions
  X.0 <- x %>%
    select(one_of(cov_list$fixed.ef)) %>%
    as.matrix()
  B.0 <- as.matrix(coef_list$fixed)
  Y.0 <- (X.0 %*% B.0)[, 1]
  
  X.site <- x %>%
    select(one_of(cov_list$site.ef)) %>%
    as.matrix()
  B.site <- coef_list$site[x$featureid_id, ]
  for (i in seq_along(B.site.mean)) {
    B.site[is.na(B.site[, i]), i] <- B.site.mean[i]
  }
  Y.site <- rowSums(X.site * B.site)
  
  X.huc <- x %>%
    select(one_of(cov_list$huc.ef)) %>%
    as.matrix()
  B.huc <- coef_list$huc[x$huc8_id, ]
  for (i in seq_along(B.huc.mean)) {
    B.huc[is.na(B.huc[, i]), i] <- B.huc.mean[i]
  }
  Y.huc <- rowSums(X.huc * B.huc)
  
  X.year <- x %>%
    select(one_of(cov_list$year.ef)) %>%
    as.matrix()
  B.year <- as.matrix(coef_list$year[x$year_id, ])
  for (i in seq_along(B.year.mean)) {
    B.year[is.na(B.year[, i]), i] <- B.year.mean[i]
  }
  Y.year <- rowSums(X.year * B.year)
  
  temp <- Y.0 + Y.site + Y.year + Y.huc
  
  temp
}

predict_daily(x2) - predict_daily(x0)
mean(predict_daily(x2)) - mean(predict_daily(x0))


# mean predictions --------------------------------------------------------

df_beta_fixed <- tibble(
  name = cov_list$fixed.ef,
  beta = coef_list$fixed
)
df_beta_site <- tibble(
  featureid = ids_list$featureid$featureid,
  name = cov_list$fixed.ef,
  beta = coef_list$fixed
)

df_beta_site <- as_tibble(coef_list$site)
names(df_beta_site) <- cov_list$site.ef
df_beta_site$featureid <- ids_list$featureid$featureid
df_beta_site <- df_beta_site %>%
  pivot_longer(-featureid, values_to = "beta")
df_beta_site_mean <- df_beta_site %>%
  group_by(name) %>%
  summarise(beta = mean(beta))

df_beta_huc <- as_tibble(coef_list$huc)
names(df_beta_huc) <- cov_list$huc.ef
df_beta_huc$huc8 <- ids_list$huc8$huc8
df_beta_huc <- df_beta_huc %>%
  pivot_longer(-huc8, values_to = "beta")
df_beta_huc_mean <- df_beta_huc %>%
  group_by(name) %>%
  summarise(beta = mean(beta))

df_beta_year <- as_tibble(coef_list$year)
names(df_beta_year) <- cov_list$year.ef
df_beta_year$year <- ids_list$year$year
df_beta_year <- df_beta_year %>%
  pivot_longer(-year, values_to = "beta")
df_beta_year_mean <- df_beta_year %>%
  group_by(name) %>%
  summarise(beta = mean(beta))
















list_std <- split(m_in$std, m_in$std$var)

delta_airTemp_std <- 2 / list_std$airTemp$sd
delta_temp7p_std <- 2 / list_std$temp7p$sd

# fixed effects
airTemp <- x0$airTemp
prcp2 <- x0$prcp2
prcp30 <- x0$prcp30
temp7p <- x0$temp7p
AreaSqKM <- x0$AreaSqKM
forest <- x0$forest
devel_hi <- x0$devel_hi
agriculture <- x0$agriculture
impoundArea <- x0$impoundArea
temp7p <- x0$temp7p

# standardize
z_airTemp <- (airTemp - list_std$airTemp$mean) / list_std$airTemp$sd
summary(x0$airTemp - z_airTemp)
z_prcp2 <- (prcp2 - list_std$prcp2$mean) / list_std$prcp2$sd
summary(x0$prcp2 - z_prcp2)
z_prcp30 <- (prcp30 - list_std$prcp30$mean) / list_std$prcp30$sd
summary(x0$prcp30 - z_prcp30)
z_temp7p <- (temp7p - list_std$temp7p$mean) / list_std$temp7p$sd
summary(x0$temp7p - z_temp7p)
z_AreaSqKM <- (AreaSqKM - list_std$AreaSqKM$mean) / list_std$AreaSqKM$sd
summary(x0$AreaSqKM - z_AreaSqKM)
z_forest <- (forest - list_std$forest$mean) / list_std$forest$sd
summary(x0$forest - z_forest)
z_devel_hi <- (devel_hi - list_std$devel_hi$mean) / list_std$devel_hi$sd
summary(x0$devel_hi - z_devel_hi)
z_agriculture <- (agriculture - list_std$agriculture$mean) / list_std$agriculture$sd
summary(x0$agriculture - z_agriculture)
z_impoundArea <- (impoundArea - list_std$impoundArea$mean) / list_std$impoundArea$sd
summary(x0$impoundArea - z_impoundArea)
z_temp7p <- (temp7p - list_std$temp7p$mean) / list_std$temp7p$sd
summary(x0$temp7p - z_temp7p)
summary(df_inp_std_2$temp7p - (z_temp7p + delta_temp7p_std))

df_inp_std %>%
  select(adjust_air_temp, date, temp7p) %>%
  spread(adjust_air_temp, temp7p) %>%
  mutate(delta = `2` - `0`)

# interactions
z_prcp2.da = z_prcp2 * z_AreaSqKM
summary(df_inp_derived_base$prcp2.da - z_prcp2.da)
z_prcp30.da = z_prcp30 * z_AreaSqKM
summary(df_inp_derived_base$prcp30.da - z_prcp30.da)
z_airTemp.prcp2 = z_airTemp * z_prcp2
summary(df_inp_derived_base$airTemp.prcp2 - z_airTemp.prcp2)
z_airTemp.prcp2.da = z_airTemp * z_prcp2 * z_AreaSqKM
summary(df_inp_derived_base$airTemp.prcp2.da - z_airTemp.prcp2.da)
z_airTemp.prcp30 = z_airTemp * z_prcp30
summary(df_inp_derived_base$airTemp.prcp30 - z_airTemp.prcp30)
z_airTemp.prcp30.da = z_airTemp * z_prcp30 * z_AreaSqKM
summary(df_inp_derived_base$airTemp.prcp30.da - z_airTemp.prcp30.da)
z_airTemp.forest = z_airTemp * z_forest
summary(df_inp_derived_base$airTemp.forest - z_airTemp.forest)
z_airTemp.devel_hi = z_airTemp * z_devel_hi
summary(df_inp_derived_base$airTemp.devel_hi - z_airTemp.devel_hi)
z_airTemp.da = z_airTemp * z_AreaSqKM
summary(df_inp_derived_base$airTemp.da - z_airTemp.da)
z_airTemp.impoundArea = z_airTemp * z_impoundArea
summary(df_inp_derived_base$airTemp.impoundArea - z_airTemp.impoundArea)
z_airTemp.agriculture = z_airTemp * z_agriculture
summary(df_inp_derived_base$airTemp.agriculture - z_airTemp.agriculture)

coef_fixed <- as.list(setNames(coef_list$fixed, cov_list$fixed.ef))

y_fixed_base <- coef_fixed$intercept +
  coef_fixed$prcp2 * z_prcp2 +
  coef_fixed$AreaSqKM * z_AreaSqKM +
  coef_fixed$prcp2.da * z_prcp2.da +
  coef_fixed$airTemp.prcp2.da * z_airTemp.prcp2.da +
  coef_fixed$forest * z_forest +
  coef_fixed$airTemp.forest * z_airTemp.forest +
  coef_fixed$devel_hi * z_devel_hi +
  coef_fixed$airTemp.devel_hi * z_airTemp.devel_hi +
  coef_fixed$prcp30 * z_prcp30 +
  coef_fixed$prcp30.da * z_prcp30.da +
  coef_fixed$airTemp.da * z_airTemp.da +
  coef_fixed$airTemp.prcp2 * z_airTemp.prcp2 +
  coef_fixed$airTemp.prcp30 * z_airTemp.prcp30 +
  coef_fixed$airTemp.prcp30.da * z_airTemp.prcp30.da +
  coef_fixed$impoundArea * z_impoundArea +
  coef_fixed$airTemp.impoundArea * z_airTemp.impoundArea +
  coef_fixed$agriculture * z_agriculture +
  coef_fixed$airTemp.agriculture * z_airTemp.agriculture

summary(y_fixed_base - Y.0[1:10240])

y_fixed_delta <- delta_airTemp_std * (
  coef_fixed$airTemp.agriculture * z_agriculture +
    coef_fixed$airTemp.da * z_AreaSqKM +
    coef_fixed$airTemp.devel_hi * z_devel_hi +
    coef_fixed$airTemp.forest * z_forest +
    coef_fixed$airTemp.impoundArea * z_impoundArea +
    coef_fixed$airTemp.prcp2 * z_prcp2 +
    coef_fixed$airTemp.prcp2.da * z_prcp2.da +
    coef_fixed$airTemp.prcp30 * z_prcp30 +
    coef_fixed$airTemp.prcp30.da * z_prcp30.da
)

y_fixed_2 <- y_fixed_base + y_fixed_delta

summary(y_fixed_2 - Y.0[10241:20480])

# random site
# featureid_id <- ids_list$featureid[which(ids_list$featureid$featureid == "201411588"), ]$featureid_id
featureid_id <- ids_list$featureid[which(ids_list$featureid$featureid == featureids), ]$featureid_id
if (length(featureid_id) == 1) {
  coef_site <- as.list(setNames(coef_list$site[featureid_id, ], cov_list$site.ef))
} else {
  coef_site <- as.list(setNames(B.site.mean, cov_list$site.ef))
}
y_site_base <- coef_site$intercept +
  coef_site$airTemp * z_airTemp +
  coef_site$temp7p * z_temp7p
summary(y_site_base - Y.site[1:10240])

y_site_2a <- coef_site$intercept +
  coef_site$airTemp * (z_airTemp + delta_airTemp_std) +
  coef_site$temp7p * (z_temp7p + delta_temp7p_std)

y_site_delta <- delta_airTemp_std * coef_site$airTemp + delta_temp7p_std * coef_site$temp7p
y_site_2b <- y_site_base + y_site_delta

summary(y_site_2a - Y.site[10241:20480])
summary(y_site_2b - Y.site[10241:20480])



# random huc8
# huc8_id <- ids_list$huc8[which(ids_list$huc8$huc8 == "01010003"), ]$huc8_id
huc8_id <- ids_list$huc8[which(ids_list$huc8$huc8 == unique(df_inp$huc8)), ]$huc8_id
if (length(huc8_id) == 1) {
  coef_huc8 <- as.list(setNames(coef_list$huc[huc8_id, ], cov_list$huc.ef))
} else {
  coef_huc8 <- as.list(setNames(B.huc.mean, cov_list$huc.ef))
}
y_huc8_base <- coef_huc8$intercept +
  coef_huc8$airTemp * z_airTemp +
  coef_huc8$temp7p * z_temp7p
summary(y_huc8_base - Y.huc[1:10240])

y_huc8_2a <- coef_huc8$intercept +
  coef_huc8$airTemp * (z_airTemp + delta_airTemp_std) +
  coef_huc8$temp7p * (z_temp7p + delta_temp7p_std)

y_huc8_delta <- delta_airTemp_std * coef_huc8$airTemp + delta_temp7p_std * coef_huc8$temp7p
y_huc8_2b <- y_huc8_base + y_huc8_delta

summary(y_huc8_2a - Y.huc[10241:20480])
summary(y_huc8_2b - Y.huc[10241:20480])

temp_base <- temp[1:10240]
temp_2 <- temp[10241:20480]

y_2 <- temp_base + y_fixed_delta + y_site_delta + y_huc8_delta

y_2 <- temp_base +
  delta_airTemp_std * (
    coef_fixed$airTemp.agriculture * z_agriculture +
      coef_fixed$airTemp.da * z_AreaSqKM +
      coef_fixed$airTemp.devel_hi * z_devel_hi +
      coef_fixed$airTemp.forest * z_forest +
      coef_fixed$airTemp.impoundArea * z_impoundArea +
      coef_fixed$airTemp.prcp2 * z_prcp2 +
      coef_fixed$airTemp.prcp2.da * z_prcp2.da +
      coef_fixed$airTemp.prcp30 * z_prcp30 +
      coef_fixed$airTemp.prcp30.da * z_prcp30.da
  ) +
  delta_airTemp_std * coef_site$airTemp + delta_temp7p_std * coef_site$temp7p +
  delta_airTemp_std * coef_huc8$airTemp + delta_temp7p_std * coef_huc8$temp7p

y_2 <- temp_base +
  delta_airTemp_std * (
    coef_fixed$airTemp.agriculture * z_agriculture +
      coef_fixed$airTemp.da * z_AreaSqKM +
      coef_fixed$airTemp.devel_hi * z_devel_hi +
      coef_fixed$airTemp.forest * z_forest +
      coef_fixed$airTemp.impoundArea * z_impoundArea +
      coef_fixed$airTemp.prcp2 * z_prcp2 +
      coef_fixed$airTemp.prcp2.da * z_prcp2.da +
      coef_fixed$airTemp.prcp30 * z_prcp30 +
      coef_fixed$airTemp.prcp30.da * z_prcp30.da +
      coef_site$airTemp +
      coef_huc8$airTemp
  ) +
  delta_temp7p_std * (coef_site$temp7p + coef_huc8$temp7p)

delta <- 2
y_2 <- temp_base +
  (delta / list_std$airTemp$sd) * (
    coef_fixed$airTemp.agriculture * z_agriculture +
      coef_fixed$airTemp.da * z_AreaSqKM +
      coef_fixed$airTemp.devel_hi * z_devel_hi +
      coef_fixed$airTemp.forest * z_forest +
      coef_fixed$airTemp.impoundArea * z_impoundArea +
      coef_fixed$airTemp.prcp2 * z_prcp2 +
      coef_fixed$airTemp.prcp2.da * z_prcp2.da +
      coef_fixed$airTemp.prcp30 * z_prcp30 +
      coef_fixed$airTemp.prcp30.da * z_prcp30.da +
      coef_site$airTemp +
      coef_huc8$airTemp
  ) +
  (delta / list_std$temp7p$sd) * (
    coef_site$temp7p +
      coef_huc8$temp7p
  )
#
# y_2 <- temp_base +
#   delta * (
#     (
#       coef_fixed$airTemp.agriculture * z_agriculture +
#       coef_fixed$airTemp.da * z_AreaSqKM +
#       coef_fixed$airTemp.devel_hi * z_devel_hi +
#       coef_fixed$airTemp.forest * z_forest +
#       coef_fixed$airTemp.impoundArea * z_impoundArea +
#       coef_fixed$airTemp.prcp2 * z_prcp2 +
#       coef_fixed$airTemp.prcp2.da * z_prcp2.da +
#       coef_fixed$airTemp.prcp30 * z_prcp30 +
#       coef_fixed$airTemp.prcp30.da * z_prcp30.da +
#       coef_site$airTemp +
#       coef_huc8$airTemp
#     ) / list_std$airTemp$sd +
#     (
#       coef_site$temp7p +
#       coef_huc8$temp7p
#     ) / list_std$temp7p$sd
#   )

summary(y_2 - temp_2)

y_2_mean <- mean(temp_base) +
  (delta / list_std$airTemp$sd) * (
    coef_fixed$airTemp.agriculture * mean(z_agriculture) +
      coef_fixed$airTemp.da * mean(z_AreaSqKM) +
      coef_fixed$airTemp.devel_hi * mean(z_devel_hi) +
      coef_fixed$airTemp.forest * mean(z_forest) +
      coef_fixed$airTemp.impoundArea * mean(z_impoundArea) +
      coef_fixed$airTemp.prcp2 * mean(z_prcp2) +
      coef_fixed$airTemp.prcp2.da * mean(z_prcp2.da) +
      coef_fixed$airTemp.prcp30 * mean(z_prcp30) +
      coef_fixed$airTemp.prcp30.da * mean(z_prcp30.da) +
      coef_site$airTemp +
      coef_huc8$airTemp
  ) +
  (delta / list_std$temp7p$sd) * (
    coef_site$temp7p +
      coef_huc8$temp7p
  )
y_2_mean - mean(temp_2)


# summer mean -------------------------------------------------------------


