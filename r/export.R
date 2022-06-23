# export data files for web app

library(tidyverse)
library(jsonlite)
library(sf)
library(lme4)


# load catchments ---------------------------------------------------------

catchments_topojson <- read_json("../public/data/geojson/catchments_ma.json")
featureids <- map_dbl(catchments_topojson$objects$catchments_ma$geometries,  ~ .x$properties$FEATUREID)

model_wd <- "~/data/ecosheds/temp-model/1.3.0/"

stopifnot(dir.exists(model_wd))

m_in <- readRDS(file.path(model_wd, "model-input.rds"))

# covariates --------------------------------------------------------------
# df_app_data.tsv
#   FEATUREID
#   huc10
#   AreaSqKM
#   summer_prcp_mm
#   mean_jul_temp
#   forest
#   allonnet
#   devel_hi
#   agriculture
#   occ_current
#   occ_air_2
#   occ_air_4
#   occ_air_6

covariates_variables <- c(
  "featureid",
  "huc8",
  
  "AreaSqKM",
  "forest",
  "devel_hi",
  "agriculture",
  
  "summer_prcp_mm",
  
  "mean_jul_temp",
  
  "occ_current",
  "occ_air_2",
  "occ_air_4",
  "occ_air_6"
)

covariates <- readRDS(file.path(model_wd, "data-covariates.rds")) %>%
  select(
    featureid,
    AreaSqKM,
    forest,
    devel_hi,
    agriculture
  )

summer_prcp_mm <- read_rds("../../../../data/ecosheds/bto-model/1.4.0/data-covariates.rds") %>% 
  select(featureid, summer_prcp_mm)

huc <- read_rds("../../../../data/ecosheds/bto-model/1.4.0/data-huc.rds") %>% 
  select(featureid, huc8)

temp_model <- read_rds("../../../../data/ecosheds/temp-model/1.3.0/model-predict-derived.rds") %>% 
  select(featureid, mean_jul_temp)

bto_model <- read_rds("../../../../data/ecosheds/bto-model/2.0.0/bto-model-v2.0.0.rds")$pred %>% 
  select(featureid, starts_with("occ_"))

attributes <- huc %>% 
  full_join(covariates, by = "featureid") %>% 
  full_join(summer_prcp_mm, by = "featureid") %>% 
  full_join(temp_model, by = "featureid") %>% 
  full_join(bto_model, by = "featureid") %>% 
  filter(featureid %in% featureids) %>% 
  select(all_of(covariates_variables))

write_csv(attributes, "../public/data/attributes.csv", na = "")

devapp_data_existing <- read_tsv("../data/model/1.2.2/df_app_data.tsv")
setdiff(app_data$FEATUREID, app_data_existing$FEATUREID)
setdiff(app_data_existing$FEATUREID, app_data$FEATUREID)


# variable std ------------------------------------------------------------
# df_z_group.csv
#  <rowname>
#  var
#  mean
#  sd

bto_input <- read_rds("../../data/bto-model/1.2.2/model-input.rds")
var_std <- bto_input$var_std

write.csv(var_std, "../data/model/dev/df_z_group.csv")


# random effects ----------------------------------------------------------
# ranef_glmm.csv
#   huc10
#   Intercept
#   AreaSqKM
#   agriculture
#   summer_prcp_mm
#   mean_jul_temp
bto_calib <- read_rds("../../data/bto-model/1.2.2/model-calib.rds")
bto_model <- bto_calib$model

ranef <- ranef(bto_model)$huc10 %>% 
  as_tibble(rownames = "huc10") %>% 
  rename(Intercept = `(Intercept)`)

write_csv(ranef, "../data/model/dev/ranef_glmm.csv")


# fixed effects -----------------------------------------------------------
# summary_glmm.csv
#   variable
#   Estimate
#   Std.Error
#   z.value
#   Pr.z

bto_fixed <- summary(bto_model)$coefficients %>% 
  as_tibble(rownames = "variable") %>% 
  select(
    variable,
    Estimate,
    `Std.Error` = `Std. Error`,
    `z.value` = `z value`,
    `Pr.z` = `Pr(>|z|)`
  ) %>% 
  mutate(
    variable = if_else(variable == "(Intercept)", "Intercept", variable)
  )

write_csv(bto_fixed, "../data/model/dev/summary_glmm.csv")
