tar_option_set(packages = c("tidyverse", "lubridate", "janitor", "glue", "units", "sf"))

targets_gis <- list(
  tar_target(catchments_file, "../public/data/geojson/catchments_ma.json", format = "file"),
  tar_target(catchments, st_read(catchments_file)),
  tar_target(featureids, catchments$FEATUREID),
  
  tar_target(huc_catchment, {
    read_rds(file.path(temp_model_dir, "data-huc.rds")) |> 
      filter(featureid %in% featureids)
  }),
  tar_target(huc8_sf, {
    con <- db_connect()
    x <- st_read(con, query = "select huc8, name, geom from wbdhu8;")
    DBI::dbDisconnect(con)
    x %>%
      filter(huc8 %in% unique(huc_catchment$huc8)) %>%
      st_transform("EPSG:5070") %>%
      st_make_valid() %>%
      st_simplify(dTolerance = 1000)
  }),
  tar_target(huc8_sf_map, {
    huc8_sf |> 
      ggplot() +
      geom_sf()
  }),
  
  tar_target(majorbasins_file, "data/majorbasins/MAJBAS_POLY.shp", format = "file"),
  tar_target(majorbasins_sf, {
    st_read(majorbasins_file) |> 
      st_transform("EPSG:4326")
  }),
  
  tar_target(catchments_sf_poly, {
    huc8 <- huc8_sf
    con <- db_connect()
    x <- st_read(con, query = glue::glue("select c.*, substr(ch.huc12, 1, 8) as huc8 from catchments c left join catchment_huc12 ch on c.featureid = ch.featureid where substr(ch.huc12, 1, 8) IN ({str_c(map(huc8$huc8, ~ str_c(\"'\", .x, \"'\")), collapse = \",\")});"))
    DBI::dbDisconnect(con)
    x |> 
      mutate(featureid = as.integer(featureid)) |> 
      filter(featureid %in% featureids)
  }),
  tar_target(catchments_sf_pnt, {
    catchments_sf_poly |> 
      st_point_on_surface()
  }),
  
  tar_target(catchments_majorbasin, {
    x_1 <- catchments_sf_pnt |> 
      st_join(select(majorbasins_sf, basin = NAME))
    
    x_1_missing <- x_1 |>
      filter(is.na(basin)) |>
      pull(featureid)
    
    x_dist <- catchments_sf_pnt |> 
      filter(featureid %in% x_1_missing) |> 
      arrange(featureid) |> 
      st_transform("EPSG:5070") |> 
      st_distance(
        majorbasins_sf |> 
          st_transform("EPSG:5070") |> 
          select(basin = NAME)
      ) |> 
      drop_units()
    colnames(x_dist) <- majorbasins_sf$NAME
    rownames(x_dist) <- sort(x_1_missing)
    
    x_dist_basin <- as_tibble(x_dist, rownames = "featureid", .name_repair = "minimal") |> 
      pivot_longer(-featureid, names_to = "basin") |> 
      arrange(featureid, value) |> 
      group_by(featureid) |> 
      slice(1) |> 
      mutate(featureid = as.integer(featureid))
    
    x_1 |> 
      st_drop_geometry() |> 
      filter(!is.na(basin)) |> 
      select(featureid, basin) |> 
      bind_rows(select(x_dist_basin, featureid, basin)) |> 
      as_tibble() |> 
      mutate(
        basin = toupper(basin),
        basin = case_when(
          basin == "ISLANDS" ~ "CAPE COD",
          TRUE ~ basin
        )
      )
  }),
  tar_target(catchments_majorbasin_map, {
    catchments_sf_pnt |> 
      left_join(catchments_majorbasin, by = "featureid") |> 
      ggplot() +
      geom_sf(aes(color = basin))
  })
)