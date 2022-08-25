library(targets)

invisible(sapply(list.files("R", pattern = ".R$", full.names = TRUE), source))

options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("tidyverse", "lubridate", "janitor", "glue", "units", "sf", "jsonlite", "dotenv"))

# load packages into session
if (interactive()) {
  sapply(tar_option_get("packages"), require, character.only = TRUE)
}

list(
  targets_projections,
  targets_gis,
  targets_temp_model,
  targets_bto_model,
  targets_inp,
  targets_export,
  
  tar_target(catchments_projections, {
    catchments_majorbasin |> 
      left_join(
        projections_summer_median, by = "basin"
      )
  }),
  tar_target(catchments_projections_map, {
    catchments_sf_pnt |> 
      left_join(catchments_projections, by = "featureid") |> 
      ggplot() +
      geom_sf(aes(color = delta), size = 0.5) +
      scale_color_viridis_c() +
      facet_grid(vars(rcp_scenario), vars(period))
  })
)
