tar_option_set(packages = c("tidyverse", "lubridate", "janitor", "glue", "units", "sf", "furrr"))

targets_projections <- list(
  tar_target(projections_file, "data/TG.projections.MB.csv", format = "file"),
  tar_target(projections_all, {
    x <- read_csv(projections_file, col_types = cols(.default = col_character(), value = col_number()))
    x_obs <- x |> 
      filter(status == "Observed") |> 
      select(region, season, obs = value)
    x |> 
      filter(status != "Observed") |> 
      left_join(x_obs, by = c("region", "season")) |> 
      mutate(
        value = value + obs,
        across(c(value, obs), ~ drop_units(set_units(set_units(.x, "degF"), "degC"))),
        delta = value - obs,
        percentile = parse_number(percentile),
        region = case_when(
          region == "Narragansett Bay & Mt. Hope Bay Shore" ~ "Narragansett Bay",
          TRUE ~ region
        ),
        region = toupper(region)
      ) |> 
      rename(period = year_30yravg, basin = region) |> 
      select(-status)
  }),
  tar_target(projections_summer_median, {
    projections_all |> 
      filter(season == "Summer", percentile == 50)
  }),
  tar_target(projections_summer_median_plot, {
    projections_summer_median |> 
      ggplot(aes(rcp_scenario, delta)) +
      geom_boxplot() +
      facet_wrap(vars(period))
  }),
  tar_target(projections_catchments, {
    catchments_majorbasin |> 
      left_join(projections_summer_median, by = "basin") |> 
      select(featureid, rcp_scenario, period, delta)
  }),
  tar_target(projections_temp, {
    plan(multisession, workers = 8)
    inp |> 
      filter(covariates$AreaSqKM <= 200) |> 
      ungroup() |> 
      mutate(
        coefficients = future_map(coefficients, ~ pivot_longer(as_tibble(.x), everything(), values_to = "beta")),
        covariates = future_map(covariates, ~ pivot_longer(as_tibble(.x), everything()))
      ) |> 
      left_join(
        projections_catchments |> 
          bind_rows(
            crossing(
              featureid = unique(projections_catchments$featureid),
              delta = c(0, 2, 4, 6)
            ) |> 
              mutate(rcp_scenario = str_c("base_", delta))
          ),
        by = "featureid"
      ) |> 
      mutate(
        inp = future_pmap(
          list(covariates, delta, covariances, coefficients),
          function (covariates, delta, covariances, coefficients) {
            inp <- covariates |> 
              mutate(
                value = if_else(name %in% c("airTemp", "temp7p"), value + delta, value)
              ) %>% 
              left_join(temp_model_std, by = c("name" = "var")) %>% 
              mutate(value = (value - mean) / sd) %>% 
              select(-mean, -sd) %>% 
              pivot_wider() %>% 
              mutate(
                prcp2.da = prcp2 * AreaSqKM,
                prcp30.da = prcp30 * AreaSqKM,
                airTemp.prcp2 = airTemp * prcp2 + covariances[["airTemp.prcp2"]],
                airTemp.prcp2.da = (airTemp * prcp2 + covariances[["airTemp.prcp2"]]) * AreaSqKM,
                airTemp.prcp30 = airTemp * prcp30 + covariances[["airTemp.prcp30"]],
                airTemp.prcp30.da = (airTemp * prcp30 + covariances[["airTemp.prcp30"]]) * AreaSqKM,
                airTemp.forest = airTemp * forest,
                airTemp.devel_hi = airTemp * devel_hi,
                airTemp.da = airTemp * AreaSqKM,
                airTemp.impoundArea = airTemp * impoundArea,
                airTemp.agriculture = airTemp * agriculture,
                intercept = 1
              ) %>% 
              pivot_longer(everything())
            inp |> 
              left_join(
                coefficients,
                by = "name"
              ) |> 
              mutate(temp = value * beta)
          }
        ),
        mean_jul_temp = map_dbl(inp, ~ sum(.x$temp))
      )
  }),
  tar_target(projections_temp_check, {
    projections_temp |> 
      select(featureid, rcp_scenario, period, delta, refugia = mean_jul_temp) |> 
      filter(str_starts(rcp_scenario, "base_")) |> 
      mutate(air = parse_number(rcp_scenario)) |> 
      left_join(
        temp_model_pred |> 
          rename(mean_jul_temp_air0 = mean_jul_temp) |> 
          pivot_longer(-featureid, values_to = "temp_model") |> 
          mutate(air = parse_number(name)),
        by = c("featureid", "air")
      ) |> 
      ggplot(aes(refugia, temp_model)) +
      geom_abline() +
      geom_point(size = 0.5)
  }),
  tar_target(projections_bto, {
    huc_catchment |> 
      select(featureid, huc8) |> 
      crossing(
        distinct(projections_temp, rcp_scenario, period)
      ) |> 
      left_join(
        projections_temp |> 
          select(featureid, rcp_scenario, period, mean_jul_temp),
        by = c("featureid", "rcp_scenario", "period")
      ) |> 
      left_join(
        bto_model_params$random |> 
          rename(ranef = intercept),
        by = "huc8"
      ) |> 
      mutate(
        fixef = bto_model_params$fixed$intercept + bto_model_params$fixed$mean_jul_temp * (mean_jul_temp - bto_model_params$std$mean_jul_temp$mean) / bto_model_params$std$mean_jul_temp$sd,
        totef = fixef + ranef,
        prob = exp(totef) / (1 + exp(totef))
      )
  }),
  tar_target(projections_bto_check, {
    projections_bto |> 
      select(featureid, rcp_scenario, period, refugia = prob) |> 
      filter(str_starts(rcp_scenario, "base_")) |> 
      mutate(air = parse_number(rcp_scenario)) |> 
      left_join(
        bto_model_pred |> 
          select(featureid, starts_with("occ_")) |> 
          rename(occ_air_0 = occ_current) |> 
          pivot_longer(-featureid, values_to = "bto_model") |> 
          mutate(air = parse_number(name)),
        by = c("featureid", "air")
      ) |> 
      ggplot(aes(refugia, bto_model)) +
      geom_abline() +
      geom_point(size = 0.5)
  })
)