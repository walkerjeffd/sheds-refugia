tar_option_set(packages = c("tidyverse", "lubridate", "janitor", "glue", "units", "sf", "jsonlite", "dotenv"))

targets_bto_model <- list(
  tar_target(bto_model_dir, Sys.getenv("BTO_MODEL_DIR"), cue = tar_cue("always")),
  
  tar_target(bto_model_file, file.path(bto_model_dir, "bto-model.rds"), format = "file"),
  tar_target(bto_model, read_rds(bto_model_file)),
  
  tar_target(bto_model_pred, bto_model$pred),
  
  tar_target(bto_model_params_file, file.path(bto_model_dir, "params.json"), format = "file"),
  tar_target(bto_model_params, {
    x <- jsonlite::read_json(bto_model_params_file, simplifyVector = TRUE)
    x$random <- as_tibble(x$random)
    x
  }),
  tar_target(bto_model_params_ranef_map, {
    huc8_sf |> 
      st_transform("EPSG:4326") |> 
      left_join(bto_model_params$random, by = "huc8") |> 
      ggplot() +
      geom_sf(aes(fill = intercept)) +
      scale_fill_viridis_c() +
      labs(title = "BTO Model | HUC8 Random Effect Intercept")
  })
)