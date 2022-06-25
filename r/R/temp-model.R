targets_temp_model <- list(
  tar_target(temp_model_inp_file, file.path(temp_model_dir, "model-input.rds"), format = "file"),
  tar_target(temp_model_inp, read_rds(temp_model_inp_file)),
  tar_target(temp_model_std, temp_model_inp$std),
  tar_target(temp_model_covariates_file, file.path(temp_model_dir, "data-covariates.rds"), format = "file"),
  tar_target(temp_model_covariates, read_rds(temp_model_covariates_file)),
  
  tar_target(temp_model_coef, {
    coef_fixed <- data.frame(
      name = temp_model_out$covs$fixed.ef,
      value = temp_model_out$results$mean$B.0
    )
    b_fixed <- tibble(
      featureid = featureids,
      group = "fixed"
    ) |> 
      crossing(coef_fixed)
    
    coef_featureid <- as.data.frame(temp_model_out$results$mean$B.site) |> 
      set_names(temp_model_out$covs$site.ef) |> 
      rename(intercept = intercept.site) |> 
      as_tibble() |> 
      mutate(
        featureid = temp_model_out$ids$site$featureid, .before = 1
      )
    coef_featureid_mean <- coef_featureid |> 
      summarise(across(-c(featureid), mean)) |> 
      as.list()
    
    b_featureid <- tibble(
      featureid = featureids,
      group = "featureid"
    ) |> 
      left_join(coef_featureid, by = "featureid") |> 
      mutate(
        intercept = coalesce(intercept, coef_featureid_mean$intercept),
        airTemp = coalesce(airTemp, coef_featureid_mean$airTemp),
        temp7p = coalesce(temp7p, coef_featureid_mean$temp7p)
      ) |> 
      pivot_longer(-c(featureid, group))
    
    coef_huc8 <- as.data.frame(temp_model_out$results$mean$B.huc) |> 
      set_names(temp_model_out$covs$huc.ef) |> 
      rename(intercept = intercept.huc) |> 
      as_tibble() |> 
      mutate(
        huc8 = temp_model_out$ids$huc$huc8, .before = 1
      )
    coef_huc8_mean <- coef_huc8 |> 
      summarise(across(-c(huc8), mean)) |> 
      as.list()
    
    b_huc8 <- tibble(
      featureid = featureids,
      group = "huc8"
    ) |> 
      left_join(select(huc_catchment, featureid, huc8), by = "featureid") |> 
      left_join(coef_huc8, by = "huc8") |> 
      mutate(
        intercept = coalesce(intercept, coef_huc8_mean$intercept),
        airTemp = coalesce(airTemp, coef_huc8_mean$airTemp),
        temp7p = coalesce(temp7p, coef_huc8_mean$temp7p)
      ) |> 
      select(-huc8) |> 
      pivot_longer(-c(featureid, group))
    
    coef_year <- data.frame(
      year = temp_model_out$ids$year$year,
      intercept_year = temp_model_out$results$mean$B.year[, 1]
    ) |> 
      complete(year = 1980:max(temp_model_out$ids$year$year)) |> 
      mutate(intercept_year = coalesce(intercept_year, mean(temp_model_out$results$mean$B.year[, 1]))) |> 
      summarise(value = mean(intercept_year)) |> 
      mutate(name = "intercept", .before = 1)
    
    b_year <- tibble(
      featureid = featureids,
      group = "year"
    ) |> 
      crossing(coef_year)
    
    bind_rows(
      b_fixed,
      b_huc8,
      b_featureid,
      b_year
    ) |> 
      group_by(featureid, name) |> 
      summarise(value = sum(value), .groups = "drop") |> 
      pivot_wider() |> 
      nest_by(featureid, .key = "coef")
  }),
  
  tar_target(temp_model_out_file, file.path(temp_model_dir, "model-output.rds"), format = "file"),
  tar_target(temp_model_out, read_rds(temp_model_out_file)),
  
  tar_target(temp_model_pred_file, file.path(temp_model_dir, "model-predict-derived.rds"), format = "file"),
  tar_target(temp_model_pred, {
    read_rds(temp_model_pred_file) |>
      filter(featureid %in% featureids) |> 
      select(featureid, starts_with("mean_jul_temp"))
  })
)