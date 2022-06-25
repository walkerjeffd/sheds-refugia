tar_option_set(packages = c("tidyverse", "lubridate", "janitor", "glue", "units", "sf", "jsonlite", "dotenv"))

targets_export <- list(
  tar_target(export_temp_model_files, {
    filenames <- glue("../public/data/temp-model/{inp$featureid}.json")
    for (i in 1:nrow(inp)) {
      row <- inp[i, ]
      list(
        featureid = row$featureid,
        val = row$covariates[[1]],
        cov = row$covariances[[1]],
        coef = row$coefficients[[1]],
        std = temp_model_std |> 
          select(-var) |> 
          split(temp_model_std$var) |> 
          map(as.list)
      ) |> 
        jsonlite::write_json(filenames[i], pretty = TRUE, auto_unbox = TRUE)
    }
    filenames
  }, format = "file"),
  tar_target(export_attributes, {
    x_bto <- projections_bto |> 
      mutate(
        name = case_when(
          rcp_scenario == "base_0" ~ "occ_current",
          str_starts(rcp_scenario, "base") ~ str_c("occ_air_", parse_number(rcp_scenario)),
          TRUE ~ str_c("occ_", parse_number(rcp_scenario) * 10, "_", period)
        ),
      ) |>
      select(featureid, name, value = prob) |> 
      pivot_wider() |> 
      select(featureid, occ_current, starts_with("occ_air"), everything())
    huc_catchment |> 
      select(featureid, huc8) |> 
      filter(featureid %in% featureids) |> 
      left_join(
        inp_covariates |>
          unnest(covariates),
        by = "featureid"
      ) |> 
      left_join(
        temp_model_pred |> 
          select(featureid, mean_jul_temp),
        by = "featureid"
      ) |> 
      left_join(
        x_bto,
        by = "featureid"
      ) |> 
      select(featureid, huc8, AreaSqKM, impoundArea, agriculture, devel_hi, forest, everything()) |> 
      mutate(
        impoundArea = impoundArea / AreaSqKM,
        AreaSqKM = log10(AreaSqKM)
      )
  }),
  tar_target(export_attributes_file, {
    filename <- "../public/data/attributes.csv"
    write_csv(export_attributes, filename, na = "")
    filename
  }, format = "file")
)