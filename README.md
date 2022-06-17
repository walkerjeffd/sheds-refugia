Massachusetts Coldwater Refugia Tool
====================================

Jeffrey D Walker, PhD <jeff@walkerenvres.com>  
Walker Environmental Research LLC

Originally developed by Jason Coombs for USDA Forest Service

## Overview

The Massachusetts ColdWater Refugia Tool is a map-based data visualization tool for exploring coldwater refugia based on predicted stream temperature and brook trout occupancy.

This tool is part of the USGS [EcoSHEDS project](https://usgs.gov/apps/ecosheds/).

## Development

Install node dependencies.

```sh
npm i
```

Run development server

```sh
npm start
```

## Production

Copy contents of `./public` to static web server.

```sh
rsync -avz public/ user@host:/path/to/deployment
```
