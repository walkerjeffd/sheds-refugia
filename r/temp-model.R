# run from temp-model repo

library(tidyverse)
library(lubridate)
library(DBI)

# for a single feature id
# calculate mean july temperature
# from daily predictions
# and mean predictions

featureid <- 201411588

model_wd <- "~/Projects/sheds/data/temp-model/1.2.0/"


# data --------------------------------------------------------------------

df_huc <- readRDS(file.path(model_wd, "data-huc.rds"))


# model -------------------------------------------------------------------

m_in <- readRDS(file.path(model_wd, "model-input.rds"))
m_out <- readRDS(file.path(model_wd, "model-output.rds"))

# df_cov_std <- m_in$std
# cov_list <- m_out$covs
# ids_list <- m_in$ids
# B.site.mean <- colMeans(m_out$results$mean$B.site)
# B.huc.mean <- colMeans(m_out$results$mean$B.huc)
# B.year.mean <- colMeans(m_out$results$mean$B.year)
# 
# coef_list <- list(
#   fixed = m_out$results$mean$B.0,
#   site = m_out$results$mean$B.site,
#   huc = m_out$results$mean$B.huc,
#   year = m_out$results$mean$B.year
# )

df_beta_fixed <- tibble(
  name = m_out$covs$fixed.ef,
  beta = m_out$results$mean$B.0
)

df_beta_site <- as_tibble(m_out$results$mean$B.site, .name_repair = "unique")
names(df_beta_site) <- m_out$covs$site.ef
df_beta_site$featureid <- m_in$ids$featureid$featureid
df_beta_site <- df_beta_site %>%
  pivot_longer(-featureid, values_to = "beta")

df_beta_huc <- as_tibble(m_out$results$mean$B.huc, .name_repair = "unique")
names(df_beta_huc) <- m_out$covs$huc.ef
df_beta_huc$huc8 <- m_in$ids$huc8$huc8
df_beta_huc <- df_beta_huc %>%
  pivot_longer(-huc8, values_to = "beta")

df_beta_year <- as_tibble(m_out$results$mean$B.year, .name_repair = "unique")
names(df_beta_year) <- m_out$covs$year.ef
df_beta_year$year <- m_in$ids$year$year
df_beta_year <- df_beta_year %>%
  pivot_longer(-year, values_to = "beta")

df_beta_site_mean <- df_beta_site %>%
  group_by(name) %>%
  summarise(beta = mean(beta))
df_beta_huc_mean <- df_beta_huc %>%
  group_by(name) %>%
  summarise(beta = mean(beta))
df_beta_year_mean <- df_beta_year %>%
  group_by(name) %>%
  summarise(beta = mean(beta))

beta <- list(
  fixed = df_beta_fixed,
  site = df_beta_site,
  huc = df_beta_huc,
  year = df_beta_year
)

B.site.mean <- colMeans(m_out$results$mean$B.site)
B.huc.mean <- colMeans(m_out$results$mean$B.huc)
B.year.mean <- colMeans(m_out$results$mean$B.year)

# covariates --------------------------------------------------------------

df_covariates <- readRDS(file.path(model_wd, "data-covariates.rds")) %>%
  filter(
    AreaSqKM <= 200,
    allonnet < 70
  ) %>%
  mutate(
    impoundArea = AreaSqKM * allonnet / 100
  )
df_covariates <- df_covariates[complete.cases(df_covariates), ]


# daymet ------------------------------------------------------------------

get_daymet <- function (featureid, delta_airTemp = 0) {
  con <- dbConnect(RPostgreSQL::PostgreSQL(), host = "osensei.cns.umass.edu", dbname = "daymet", user = "jeff")
  sql <- paste0("
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
  rs <- dbSendQuery(con, sql, featureid)
  df <- dbFetch(rs)%>%
    as_tibble()
  dbClearResult(rs)
  dbDisconnect(con)
  
  df %>%
    mutate(
      airTemp = (tmin + tmax) / 2 + delta_airTemp,
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

get_daymet(featureid = 201411588)


# merge --------------------------------------------------------------------

raw_input <- function (featureid, delta_airTemp = 0) {
  x_daymet <- get_daymet(featureid, delta_airTemp)
  
  x_daymet %>%
    mutate(year = year(date)) %>% 
    left_join(df_huc, by = "featureid") %>% 
    left_join(df_covariates, by = "featureid") %>%
    left_join(m_out$ids$site, by = "featureid") %>%
    left_join(m_out$ids$huc, by = "huc8") %>%
    left_join(m_out$ids$year, by = "year") %>% 
    select(
      featureid, featureid_id, huc8, huc8_id, year, year_id, date,
      airTemp, prcp2, prcp30, temp7p,
      AreaSqKM, forest, devel_hi, agriculture, impoundArea
    )
}

raw_input(201411588)

create_input <- function(featureid, delta_airTemp = 0) {
  x_inp <- raw_input(featureid, delta_airTemp)

  x_standardized <- x_inp %>%
    gather(var, value, -featureid, -featureid_id, -huc8, -huc8_id, -year, -year_id, -date) %>%
    left_join(m_in$std, by = "var") %>%
    mutate(value = (value - mean) / sd) %>%
    select(-mean, -sd) %>%
    spread(var, value)
  
  x_standardized %>%
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

inp_201411588 <- create_input(201411588)


# predict daily -----------------------------------------------------------


predict_daily <- function(featureid, delta_airTemp = 0) {
  x <- create_input(featureid, delta_airTemp)

  # compute predictions
  X.0 <- x %>%
    select(one_of(m_out$covs$fixed.ef)) %>%
    as.matrix()
  B.0 <- as.matrix(m_out$results$mean$B.0)
  Y.0 <- (X.0 %*% B.0)[, 1]
  
  X.site <- x %>%
    select(one_of(m_out$covs$site.ef)) %>%
    as.matrix()
  B.site <- m_out$results$mean$B.site[x$featureid_id, ]
  for (i in seq_along(B.site.mean)) {
    B.site[is.na(B.site[, i]), i] <- B.site.mean[i]
  }
  Y.site <- rowSums(X.site * B.site)
  
  X.huc <- x %>%
    select(one_of(m_out$covs$huc.ef)) %>%
    as.matrix()
  B.huc <- m_out$results$mean$B.huc[x$huc8_id, ]
  for (i in seq_along(B.huc.mean)) {
    B.huc[is.na(B.huc[, i]), i] <- B.huc.mean[i]
  }
  Y.huc <- rowSums(X.huc * B.huc)
  
  X.year <- x %>%
    select(one_of(m_out$covs$year.ef)) %>%
    as.matrix()
  B.year <- as.matrix(m_out$results$mean$B.year[x$year_id, ])
  for (i in seq_along(B.year.mean)) {
    B.year[is.na(B.year[, i]), i] <- B.year.mean[i]
  }
  Y.year <- rowSums(X.year * B.year)
  
  x$temp <- Y.0 + Y.site + Y.year + Y.huc
  
  x
}

day_201411588_0 <- predict_daily(201411588)
day_201411588_2 <- predict_daily(201411588, 2)

# mean july temp
day_201411588_0 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>%
  mean()


# predict mean ------------------------------------------------------------

x <- create_input(201411588, 0) %>% 
  filter(month(date) == 7)

# fixed
X.0_day <- x %>%
  select(one_of(m_out$covs$fixed.ef)) %>%
  as.matrix()
Y.0_day <- (X.0_day %*% as.matrix(m_out$results$mean$B.0))[, 1]

X.0_mean <- x %>%
  select(one_of(m_out$covs$fixed.ef)) %>%
  as.matrix() %>% 
  colMeans()
Y.0_mean <- sum(X.0_mean * m_out$results$mean$B.0)

mean(Y.0_day) - Y.0_mean

# site random
X.site_day <- x %>%
  select(one_of(m_out$covs$site.ef)) %>%
  as.matrix()
B.site_day <- m_out$results$mean$B.site[x$featureid_id, ]
for (i in seq_along(B.site.mean)) {
  B.site_day[is.na(B.site_day[, i]), i] <- B.site.mean[i]
}
Y.site_day <- rowSums(X.site_day * B.site_day)

X.site_mean <- x %>%
  select(one_of(m_out$covs$site.ef)) %>%
  as.matrix() %>% 
  colMeans()
B.site_mean <- m_out$results$mean$B.site[unique(x$featureid_id), ]
if (all(is.na(B.site_mean))) {
  B.site_mean <- B.site.mean
}
Y.site_mean <- sum(X.site_mean * B.site_mean)
 
mean(Y.site_day)
Y.site_mean

# huc random
X.huc_day <- x %>%
  select(one_of(m_out$covs$huc.ef)) %>%
  as.matrix()
B.huc_day <- m_out$results$mean$B.huc[x$huc8_id, ]
for (i in seq_along(B.huc.mean)) {
  B.huc_day[is.na(B.huc_day[, i]), i] <- B.huc.mean[i]
}
Y.huc_day <- rowSums(X.huc_day * B.huc_day)

X.huc_mean <- x %>%
  select(one_of(m_out$covs$huc.ef)) %>%
  as.matrix() %>% 
  colMeans()
B.huc_mean <- m_out$results$mean$B.huc[unique(x$huc8_id), ]
if (all(is.na(B.huc_mean))) {
  B.huc_mean <- B.huc.mean
}
Y.huc_mean <- sum(X.huc_mean * B.huc_mean)

mean(Y.huc_day)
Y.huc_mean

# year random
X.year_day <- x %>%
  select(one_of(m_out$covs$year.ef)) %>%
  as.matrix()
B.year_day <- as.matrix(m_out$results$mean$B.year[x$year_id, ])
for (i in seq_along(B.year.mean)) {
  B.year_day[is.na(B.year_day[, i]), i] <- B.year.mean[i]
}
Y.year_day <- rowSums(X.year_day * B.year_day)

X.year_mean <- x %>%
  select(one_of(m_out$covs$year.ef)) %>%
  as.matrix() %>% 
  colMeans()
B.year_mean <- B.year.mean
Y.year_mean <- sum(X.year_mean * B.year_mean)

mean(Y.year_day)
Y.year_mean

temp_day <- Y.0_day + Y.site_day + Y.huc_day + Y.year_day
temp_mean <- Y.0_mean + Y.site_mean + Y.huc_mean + Y.year_mean

# all three methods are the same
mean(temp_day)
temp_mean
day_201411588_0 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>% 
  mean()
 
day_201411588_2 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>% 
  mean()

# change in std airTemp = delta / sd_airTemp
mean(day_201411588_2$airTemp - day_201411588_0$airTemp)
2 / m_in$std$sd[m_in$std$var == "airTemp"]



# delta daily algorithm ---------------------------------------------------

primary_covariates <- c(
  "airTemp", "prcp2", "prcp30", "temp7p",
  "AreaSqKM", "forest", "devel_hi", "agriculture", "impoundArea"
)

cov_std <- split(m_in$std, m_in$std$var)

# primary cov
x_primary <- create_input(201411588, 0) %>% 
  filter(month(date) == 7) %>% 
  select(featureid:date, one_of(primary_covariates))

# adjust using sd
x_adjust <- x_primary %>% 
  mutate(
    airTemp = airTemp + 2 / cov_std$airTemp$sd,
    temp7p = temp7p + 2 / cov_std$temp7p$sd
  )

mean(x_adjust$airTemp - x_primary$airTemp)
mean(x_adjust$temp7p - x_primary$temp7p)

# calculate interaction
x_interaction <- x_adjust %>%
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

# calculate mean effects
X.0 <- x_interaction %>%
  select(one_of(m_out$covs$fixed.ef)) %>%
  as.matrix() %>% 
  colMeans()
X.0 - X.0_mean
Y.0 <- sum(X.0 * m_out$results$mean$B.0)
Y.0 - Y.0_mean

X.site <- x_interaction %>%
  select(one_of(m_out$covs$site.ef)) %>%
  as.matrix() %>% 
  colMeans()
B.site <- m_out$results$mean$B.site[unique(x_interaction$featureid_id), ]
if (all(is.na(B.site))) {
  B.site <- B.site.mean
}
Y.site <- sum(X.site * B.site)
Y.site - Y.site_mean

X.huc <- x_interaction %>%
  select(one_of(m_out$covs$huc.ef)) %>%
  as.matrix() %>% 
  colMeans()
B.huc <- m_out$results$mean$B.huc[unique(x_interaction$huc8_id), ]
if (all(is.na(B.huc))) {
  B.huc <- B.huc.mean
}
Y.huc <- sum(X.huc * B.huc)
Y.huc - Y.huc_mean

X.year <- x_interaction %>%
  select(one_of(m_out$covs$year.ef)) %>%
  as.matrix() %>% 
  colMeans()
B.year <- B.year.mean
Y.year <- sum(X.year * B.year)
Y.year - Y.year_mean

temp <- Y.0 + Y.site + Y.huc + Y.year
temp
day_201411588_2 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>% 
  mean()

day_201411588_0_july <- day_201411588_0 %>% 
  filter(month(date) == 7)
day_201411588_2_july <- day_201411588_2 %>% 
  filter(month(date) == 7)


# delta mean algorithm ----------------------------------------------------

# mean(X*Y) = mean(X) * mean(Y) + (1 - 1/n) * cov(X,Y)
mean(day_201411588_0_july$airTemp.prcp2)
mean(day_201411588_0_july$airTemp) * mean(day_201411588_0_july$prcp2) + (1 - 1 / nrow(day_201411588_0_july)) * cov(day_201411588_0_july$airTemp, day_201411588_0_july$prcp2)

# cov(X+dX,Y) = cov(X, Y)
cov(day_201411588_0_july$airTemp + 20, day_201411588_0_july$prcp2)
cov(day_201411588_0_july$airTemp, day_201411588_0_july$prcp2)
cov(day_201411588_2_july$airTemp, day_201411588_2_july$prcp2)

# mean(X+dX) = mean(X) + dX
mean(day_201411588_2_july$airTemp)
mean(day_201411588_0_july$airTemp + 2 / cov_std$airTemp$sd)
mean(day_201411588_0_july$airTemp) + 2 / cov_std$airTemp$sd

# mean((X+dX)*Y) = mean(X+dX) * mean(Y) + (n-1 / n) * cov(X+dX,Y)
#                = mean(X+dX) * mean(Y) + (1 - 1/n) * cov(X,Y)
#                = mean(X) * mean(Y) + (1 - 1/n) * cov(X,Y) + dX * mean(Y)
#                = mean(X*Y) + dX * mean(Y)
mean(day_201411588_2_july$airTemp.prcp2)
mean(day_201411588_0_july$airTemp + 2 / cov_std$airTemp$sd) * mean(day_201411588_0_july$prcp2) + (1 - 1 / nrow(day_201411588_0_july)) * cov(day_201411588_0_july$airTemp, day_201411588_0_july$prcp2)
mean(day_201411588_0_july$airTemp.prcp2) + (2 / cov_std$airTemp$sd) * mean(day_201411588_0_july$prcp2)

# NOTE: mean((X+dX)*Y) = mean(X*Y) + dX * mean(Y)

