# run from temp-model repo

library(tidyverse)
library(lubridate)
library(DBI)

# for a single feature id
# calculate mean july temperature
# from daily predictions
# and mean predictions

featureid <- 201411588

model_wd <- "~/data/ecosheds/temp-model/1.3.0/"

stopifnot(dir.exists(model_wd))


# data --------------------------------------------------------------------

df_huc <- readRDS(file.path(model_wd, "data-huc.rds"))


# model -------------------------------------------------------------------

m_in <- readRDS(file.path(model_wd, "model-input.rds"))
m_out <- readRDS(file.path(model_wd, "model-output.rds"))
variable_std <- m_in$std

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

beta_fixed <- tibble(
  name = m_out$covs$fixed.ef,
  beta = m_out$results$mean$B.0
)

beta_site <- as_tibble(m_out$results$mean$B.site, .name_repair = "unique")
names(beta_site) <- m_out$covs$site.ef
beta_site$featureid <- m_in$ids$featureid$featureid
beta_site <- beta_site %>%
  pivot_longer(-featureid, values_to = "beta")

beta_huc <- as_tibble(m_out$results$mean$B.huc, .name_repair = "unique")
names(beta_huc) <- m_out$covs$huc.ef
beta_huc$huc8 <- m_in$ids$huc8$huc8
beta_huc <- beta_huc %>%
  pivot_longer(-huc8, values_to = "beta")

beta_year <- as_tibble(m_out$results$mean$B.year, .name_repair = "unique")
names(beta_year) <- m_out$covs$year.ef
beta_year$year <- m_in$ids$year$year
beta_year <- beta_year %>%
  pivot_longer(-year, values_to = "beta")

beta_site_mean <- beta_site %>%
  group_by(name) %>%
  summarise(beta = mean(beta))
beta_huc_mean <- beta_huc %>%
  group_by(name) %>%
  summarise(beta = mean(beta))
beta_year_mean <- beta_year %>%
  group_by(name) %>%
  summarise(beta = mean(beta))

beta <- list(
  fixed = beta_fixed,
  site = beta_site,
  huc = beta_huc,
  year = beta_year
)

B.site.mean <- colMeans(m_out$results$mean$B.site)
B.huc.mean <- colMeans(m_out$results$mean$B.huc)
B.year.mean <- colMeans(m_out$results$mean$B.year)

# covariates --------------------------------------------------------------

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


# daymet ------------------------------------------------------------------

get_daymet <- function (featureid) {
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

get_daymet(featureid = 201411588) %>% 
  pull(airTemp) %>% 
  mean(na.rm = TRUE)
get_daymet(featureid = 201411588, 1, 0.1) %>% 
  pull(airTemp) %>% 
  mean(na.rm = TRUE)
get_daymet(featureid = 201411588, 0, 0.1) %>% 
  pull(airTemp) %>% 
  mean(na.rm = TRUE)

# merge --------------------------------------------------------------------

raw_input <- function (featureid, delta_airTemp = 0, delta_precip = 0) {
  x_daymet <- get_daymet(featureid, delta_airTemp, delta_precip)
  
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
    )
}

raw_input(201411588, 0, 0) %>% 
  pull(prcp2) %>% 
  mean(na.rm = TRUE)
raw_input(201411588, 0, 0.1) %>% 
  pull(prcp2) %>% 
  mean(na.rm = TRUE)
raw_input(201411588, 2, 0.1) %>% 
  pull(prcp2) %>% 
  mean(na.rm = TRUE)

create_input <- function(featureid, delta_airTemp = 0, delta_precip = 0) {
  x_inp <- raw_input(featureid, delta_airTemp, delta_precip)

  x_standardized <- x_inp %>%
    gather(var, value, -featureid, -featureid_id, -huc8, -huc8_id, -year, -year_id, -date) %>%
    left_join(variable_std, by = "var") %>%
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

variable_std
inp_201411588 <- create_input(201411588)

create_input(201411588) %>% 
  pull(prcp2) %>% 
  mean(na.rm = TRUE)

export_featureid <- inp_201411588 %>% 
  select(featureid, agriculture, airTemp, AreaSqKM, devel_hi, forest, impoundArea, prcp2, prcp30, temp7p)


featureid_id <- m_out$ids$site$featureid_id[m_out$ids$site$featureid == 201411588]
huc8 <- df_huc$huc8[df_huc$featureid == 201411588]
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
  mutate(intercept_year = coalesce(intercept_year, mean(m_out$results$mean$B.year[, 1])))
coef_year <- as.list(set_names(coef_year$intercept_year, nm = coef_year$year))

coef = list(
  fixed = coef_fixed,
  huc8 = coef_huc8,
  catchment = coef_catchment,
  year = coef_year
)

export_featureid = list(
  inp = list(
    fixed = covariates %>% 
      filter(featureid == 201411588) %>% 
      select(-featureid) %>% 
      as.list(),
    daily = get_daymet(201411588) %>% 
      select(date, year, airTemp, prcp2, prcp30, temp7p) %>% 
      filter(month(date) == 7) %>% 
      left_join(
        tibble(
          year = m_out$ids$year$year,
          intercept_year = m_out$results$mean$B.year[, 1]
        ),
        by = "year"
      ) %>% 
      mutate(
        intercept_year = coalesce(intercept_year, mean(m_out$results$mean$B.year[, 1]))
      )
  ),
  coef = coef,
  std = map(split(select(variable_std, -var), variable_std$var), as.list)
)

jsonlite::write_json(export_featureid, path = "../model/201411588.json", auto_unbox = TRUE, pretty = TRUE, digits = 8)

export_featureid <- function (x, daymet, path = "export") {
  filepath <- glue::glue("export/{x}.json")
  
  featureid_id <- m_out$ids$site$featureid_id[m_out$ids$site$featureid == x]
  huc8 <- df_huc$huc8[df_huc$featureid == x]
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
    mutate(intercept_year = coalesce(intercept_year, mean(m_out$results$mean$B.year[, 1])))
  coef_year <- as.list(set_names(coef_year$intercept_year, nm = coef_year$year))
  
  coef = list(
    fixed = coef_fixed,
    huc8 = coef_huc8,
    catchment = coef_catchment,
    year = coef_year
  )
  
  export_featureid = list(
    inp = list(
      fixed = covariates %>% 
        filter(featureid == x) %>% 
        select(-featureid) %>% 
        as.list(),
      daily = daymet %>% 
        filter(featureid == x) %>% 
        select(date, year, airTemp, prcp2, prcp30, temp7p) %>% 
        filter(month(date) == 7) %>% 
        left_join(
          tibble(
            year = m_out$ids$year$year,
            intercept_year = m_out$results$mean$B.year[, 1]
          ),
          by = "year"
        ) %>% 
        mutate(
          intercept_year = coalesce(intercept_year, mean(m_out$results$mean$B.year[, 1]))
        )
    ),
    coef = coef,
    std = map(split(select(variable_std, -var), variable_std$var), as.list)
  )
  jsonlite::write_json(export_featureid, path = filepath, auto_unbox = TRUE, pretty = FALSE, digits = 8)
}

library(sf)
catchments <- st_read("../public/data/geojson/catchments_ma.json")
# catchments <- head(catchments, 200)

skip_featureids <- as.numeric(str_remove(list.files("export"), ".json"))

featureids <- setdiff(catchments$FEATUREID, skip_featureids)
batch_size <- 100
batches <- split(featureids, ceiling(seq_along(featureids) / batch_size))
pb <- progress::progress_bar$new(total = length(featureids), format = "[:bar] :percent :eta")
for (i in 1:length(batches)) {
  featureids <- batches[[i]]
  daymet <- get_daymet(featureids)
  for (x in featureids) {
    pb$tick()
    export_featureid(x, daymet)
  }
}



# predict daily -----------------------------------------------------------

adjust <- list(
  forest = 67.7,
  airTemp = 5,
  prcp = 0
)

predict_daily <- function(featureid, delta_airTemp = 0, delta_precip = 0) {
  x <- create_input(featureid, delta_airTemp, delta_precip) %>% 
    filter(month(date) == 7)

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
  
  x$temp_fixed <- Y.0
  x$temp_huc8 <- Y.huc
  x$temp_catchment <- Y.site
  x$temp_year <- Y.year
  x$temp <- Y.0 + Y.site + Y.year + Y.huc
  
  x
}

day_201411588_0 <- predict_daily(201411588)
day_201411588_2 <- predict_daily(201411588, 2)
day_201411588_2_2 <- predict_daily(201411588, 2, 0.1)
day_201411588_0_2 <- predict_daily(201411588, 0, 0.1)

# mean july temp
day_201411588_0 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>%
  mean()
day_201411588_2 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>%
  mean()
day_201411588_2_2 %>% 
  filter(month(date) == 7) %>% 
  pull(temp) %>%
  mean()
day_201411588_0_2 %>% 
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

day_201411588_2_2 %>% 
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

day_201411588_2_july

mean(day_201411588_2_july$temp_year)
enframe(coef$year) %>% 
  mutate(value = map_dbl(value, ~ .x)) %>% 
  summarise(value = mean(value)) %>% 
  pull(value)



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

# mean((X+dX)*(Y+dY)) = mean(X+dX) * mean(Y+dY) + (n-1 / n) * cov(X+dX,Y+dY)
#                = mean(X+dX) * mean(Y+dY) + (1 - 1/n) * cov(X,Y)
#                = mean(X) * mean(Y) + (1 - 1/n) * cov(X,Y) + dX * mean(Y)
#                = mean(X*Y) + dX * mean(Y)
mean(day_201411588_2_july$airTemp.prcp2)
mean(day_201411588_0_july$airTemp + 2 / cov_std$airTemp$sd) * mean(day_201411588_0_july$prcp2) + (1 - 1 / nrow(day_201411588_0_july)) * cov(day_201411588_0_july$airTemp, day_201411588_0_july$prcp2)
mean(day_201411588_0_july$airTemp.prcp2) + (2 / cov_std$airTemp$sd) * mean(day_201411588_0_july$prcp2)


# NOTE: mean((X+dX)*Y) = mean(X*Y) + dX * mean(Y)

day_201411588_0_july$temp %>% mean

day_201411588_0_july




mean(day_201411588_0_july$temp)
day_201411588_2_july <- day_201411588_2 %>% 
  filter(month(date) == 7)



bind_rows(
  `0` = day_201411588_0 %>% 
    summarise(across(agriculture:airTemp.agriculture, mean)),
  `2` = day_201411588_2 %>% 
    summarise(across(agriculture:airTemp.agriculture, mean)),
  .id = "air"
) %>% 
  pivot_longer(-air) %>% 
  pivot_wider(names_from = "air") %>% 
  mutate(delta = `2` - `0`) %>% 
  left_join(variable_std, by = c("name" = "var")) %>% 
  mutate(`delta*sd` = delta * sd)

with(day_201411588_0, cor(airTemp, prcp2))

with(day_201411588_0, mean(airTemp) * mean(prcp2) + (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp2))
with(day_201411588_0, mean(airTemp.prcp2))


with(day_201411588_0, mean(airTemp) * mean(prcp2) + (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp2)) +
  with(day_201411588_0, mean(prcp2) * (2 / variable_std$sd[variable_std$var == "airTemp"]))
with(day_201411588_2, mean(airTemp) * mean(prcp2) + (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp2))
with(day_201411588_2, mean(airTemp.prcp2))


airTemp * (prcp2 + prcp2 * AreaSqKM + prcp30 + prcp30 * AreaSqKM + forest + devel_hi + AreaSqKM + impoundArea + agriculture)

airTemp.prcp2
airTemp.prcp2.da
airTemp.prcp30
airTemp.prcp30.da
airTemp.forest
airTemp.devel_hi
airTemp.da
airTemp.impoundArea
airTemp.agriculture





featureid_id <- m_out$ids$site$featureid_id[m_out$ids$site$featureid == 201411588]
huc8 <- df_huc$huc8[df_huc$featureid == 201411588]
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

coef = list(
  fixed = coef_fixed,
  huc8 = coef_huc8,
  catchment = coef_catchment,
  year = coef_year
)


day_201411588_0_mean <- day_201411588_0 %>% 
  summarise(across(agriculture:airTemp.agriculture, mean)) %>% 
  mutate(intercept = 1) %>% 
  pivot_longer(everything()) %>% 
  left_join(
    coef_fixed %>% 
      select(name, b_fix = value),
    by = "name"
  ) %>% 
  left_join(
    coef_huc8 %>% 
      select(name, b_huc = value) %>% 
      mutate(name = if_else(name == "intercept.huc", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_catchment %>% 
      select(name, b_catchment = value) %>% 
      mutate(name = if_else(name == "intercept.site", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_year %>% 
      select(name, b_year = value),
    by = "name"
  ) %>% 
  mutate(
    across(starts_with("b_"), ~ coalesce(.x, 0)),
    b = b_fix + b_huc + b_catchment + b_year
  ) %>% 
  mutate(
    x = b * value
  )

day_201411588_2_mean <- day_201411588_2 %>% 
  summarise(across(agriculture:airTemp.agriculture, mean)) %>% 
  mutate(intercept = 1) %>% 
  pivot_longer(everything()) %>% 
  left_join(
    coef_fixed %>% 
      select(name, b_fix = value),
    by = "name"
  ) %>% 
  left_join(
    coef_huc8 %>% 
      select(name, b_huc = value) %>% 
      mutate(name = if_else(name == "intercept.huc", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_catchment %>% 
      select(name, b_catchment = value) %>% 
      mutate(name = if_else(name == "intercept.site", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_year %>% 
      select(name, b_year = value),
    by = "name"
  ) %>% 
  mutate(
    across(starts_with("b_"), ~ coalesce(.x, 0)),
    b = b_fix + b_huc + b_catchment + b_year
  ) %>% 
  mutate(
    x = b * value
  )
day_201411588_2_2_mean <- day_201411588_2_2 %>% 
  summarise(across(agriculture:airTemp.agriculture, mean)) %>% 
  mutate(intercept = 1) %>% 
  pivot_longer(everything()) %>% 
  left_join(
    coef_fixed %>% 
      select(name, b_fix = value),
    by = "name"
  ) %>% 
  left_join(
    coef_huc8 %>% 
      select(name, b_huc = value) %>% 
      mutate(name = if_else(name == "intercept.huc", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_catchment %>% 
      select(name, b_catchment = value) %>% 
      mutate(name = if_else(name == "intercept.site", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_year %>% 
      select(name, b_year = value),
    by = "name"
  ) %>% 
  mutate(
    across(starts_with("b_"), ~ coalesce(.x, 0)),
    b = b_fix + b_huc + b_catchment + b_year
  ) %>% 
  mutate(
    x = b * value
  )

sum(day_201411588_0_mean$x)
mean(day_201411588_0$temp)

sum(day_201411588_2_mean$x)
mean(day_201411588_2$temp)

sum(day_201411588_2_2_mean$x)
mean(day_201411588_2_2$temp)

day_201411588_0_mean %>% 
  select(name, b, value_0 = value) %>% 
  left_join(
    day_201411588_2_mean %>% 
      select(name, value_2 = value),
    by = "name"
  ) %>% 
  mutate(
    delta = value_2 - value_0
  ) %>% 
  left_join(select(variable_std, name = var, sd), by = c("name")) %>% 
  mutate(`delta*sd` = delta * sd) %>% 
  print(n = Inf)

# airTemp.prcp2
with(day_201411588_0, mean(airTemp.prcp2))
with(day_201411588_0, mean(airTemp) * mean(prcp2) + (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp2))

with(day_201411588_2, mean(airTemp.prcp2)) - with(day_201411588_0, mean(airTemp.prcp2))
with(day_201411588_0, mean(prcp2) * (2 / variable_std$sd[variable_std$var == "airTemp"]))

# airTemp.prcp2.da
with(day_201411588_0, mean(airTemp.prcp2.da))
with(day_201411588_0, (mean(airTemp) * mean(prcp2) + (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp2)) * mean(AreaSqKM))

with(day_201411588_2, mean(airTemp.prcp2.da)) - with(day_201411588_0, mean(airTemp.prcp2.da))
with(day_201411588_0, mean(AreaSqKM) * mean(prcp2) * (2 / variable_std$sd[variable_std$var == "airTemp"]))


day_201411588_0_mean %>% 
  select(name, b, value_0 = value) %>% 
  left_join(
    day_201411588_2_mean %>% 
      select(name, value_2 = value),
    by = "name"
  ) %>% 
  mutate(
    delta = value_2 - value_0
  ) %>% 
  left_join(select(variable_std, name = var, sd), by = c("name")) %>% 
  mutate(`delta*sd` = delta * sd) %>% 
  print(n = Inf)

n_days <- nrow(day_201411588_0)
covariance <- list(
  airTemp.prcp2 = with(day_201411588_0, (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp2)),
  airTemp.prcp30 = with(day_201411588_0, (1 - 1 / nrow(day_201411588_0)) * cov(airTemp, prcp30))
)
inp_mean_201411588 <- day_201411588_0_mean %>% 
  select(name, value) %>% 
  head(9) %>% 
  pivot_wider()

inp_mean_201411588 %>% 
  mutate(
    prcp2.da = prcp2 * AreaSqKM,
    prcp30.da = prcp30 * AreaSqKM,
    airTemp.prcp2 = airTemp * prcp2 + covariance[["airTemp.prcp2"]],
    airTemp.prcp2.da = (airTemp * prcp2 + covariance[["airTemp.prcp2"]]) * AreaSqKM,
    airTemp.prcp30 = airTemp * prcp30 + covariance[["airTemp.prcp30"]],
    airTemp.prcp30.da = (airTemp * prcp30 + covariance[["airTemp.prcp30"]]) * AreaSqKM,
    airTemp.forest = airTemp * forest,
    airTemp.devel_hi = airTemp * devel_hi,
    airTemp.da = airTemp * AreaSqKM,
    airTemp.impoundArea = airTemp * impoundArea,
    airTemp.agriculture = airTemp * agriculture,
    intercept = 1
  ) %>%
  pivot_longer(everything()) %>% 
  left_join(
    coef_fixed %>% 
      select(name, b_fix = value),
    by = "name"
  ) %>% 
  left_join(
    coef_huc8 %>% 
      select(name, b_huc = value) %>% 
      mutate(name = if_else(name == "intercept.huc", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_catchment %>% 
      select(name, b_catchment = value) %>% 
      mutate(name = if_else(name == "intercept.site", "intercept", name)),
    by = "name"
  ) %>% 
  left_join(
    coef_year %>% 
      select(name, b_year = value),
    by = "name"
  ) %>% 
  mutate(
    across(starts_with("b_"), ~ coalesce(.x, 0)),
    b = b_fix + b_huc + b_catchment + b_year
  ) %>% 
  mutate(
    x = b * value
  ) %>% 
  pull(x) %>% 
  sum()
sum(day_201411588_0_mean$x)

beta_201411588 <- coef_fixed %>% 
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

inp_mean_201411588 %>% 
  mutate(
    airTemp = airTemp + 2 / variable_std$sd[which(variable_std$var == "airTemp")],
    temp7p = temp7p + 2 / variable_std$sd[which(variable_std$var == "temp7p")]
  ) %>% 
  mutate(
    prcp2.da = prcp2 * AreaSqKM,
    prcp30.da = prcp30 * AreaSqKM,
    airTemp.prcp2 = airTemp * prcp2 + covariance[["airTemp.prcp2"]],
    airTemp.prcp2.da = (airTemp * prcp2 + covariance[["airTemp.prcp2"]]) * AreaSqKM,
    airTemp.prcp30 = airTemp * prcp30 + covariance[["airTemp.prcp30"]],
    airTemp.prcp30.da = (airTemp * prcp30 + covariance[["airTemp.prcp30"]]) * AreaSqKM,
    airTemp.forest = airTemp * forest,
    airTemp.devel_hi = airTemp * devel_hi,
    airTemp.da = airTemp * AreaSqKM,
    airTemp.impoundArea = airTemp * impoundArea,
    airTemp.agriculture = airTemp * agriculture,
    intercept = 1
  ) %>%
  pivot_longer(everything()) %>% 
  left_join(select(beta_201411588, name, b), by = "name") %>% 
  mutate(
    x = b * value
  ) %>% 
  pull(x) %>% 
  sum()

sum(day_201411588_2_mean$x)



x_201411588 <- inp_mean_201411588 %>% 
  mutate(
    # airTemp = airTemp + 2 / variable_std$sd[which(variable_std$var == "airTemp")],
    # temp7p = temp7p + 2 / variable_std$sd[which(variable_std$var == "temp7p")]
    prcp2 = prcp2 + 0.1 / variable_std$sd[which(variable_std$var == "prcp2")],
    prcp30 = prcp30 + 0.1 / variable_std$sd[which(variable_std$var == "prcp30")]
  ) %>% 
  mutate(
    prcp2.da = prcp2 * AreaSqKM,
    prcp30.da = prcp30 * AreaSqKM,
    airTemp.prcp2 = airTemp * prcp2 + covariance[["airTemp.prcp2"]],
    airTemp.prcp2.da = (airTemp * prcp2 + covariance[["airTemp.prcp2"]]) * AreaSqKM,
    airTemp.prcp30 = airTemp * prcp30 + covariance[["airTemp.prcp30"]],
    airTemp.prcp30.da = (airTemp * prcp30 + covariance[["airTemp.prcp30"]]) * AreaSqKM,
    airTemp.forest = airTemp * forest,
    airTemp.devel_hi = airTemp * devel_hi,
    airTemp.da = airTemp * AreaSqKM,
    airTemp.impoundArea = airTemp * impoundArea,
    airTemp.agriculture = airTemp * agriculture,
    intercept = 1
  ) %>%
  pivot_longer(everything()) %>% 
  left_join(select(beta_201411588, name, b), by = "name") %>% 
  mutate(
    x = b * value
  )
sum(x_201411588$x)

sum(day_201411588_0_mean$x)
mean(day_201411588_0$temp)

sum(day_201411588_2_2_mean$x)
mean(day_201411588_2_2$temp)




# final -------------------------------------------------------------------

x_inp_raw <- raw_input(201411588) %>%
  filter(month(date) %in% 7)
x_inp <- x_inp_raw %>% 
  gather(var, value, -featureid, -featureid_id, -huc8, -huc8_id, -year, -year_id, -date) %>%
  left_join(variable_std, by = "var") %>%
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
    intercept = 1
  )
