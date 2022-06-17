/* global $, L, d3, topojson, crossfilter, Plotly */

let topoSVG
let topos
let transform
let path
let tooltip
let map

function setupMap () {
  map = new L.Map('map', {
    attributionControl: false,
    zoomControl: false,
    minZoom: 8,
    maxZoom: 20,
    inertiaDeceleration: 1000,
    worldCopyJump: true,
    maxBounds: [[40.5, -77.5], [44.0, -66.5]],
    zoomSnap: 0.5,
    zoomDelta: 0.5,
    maxBoundsViscosity: 0.75
  })
  map.fitBounds([[41.5, -74], [43, -69.5]])
  map.zoomToggle = 6 // use to set the zoom level for which to transition geoIndicator points betwen tiles and SVG
}
function setupUi () {
  // add panel icons
  d3.select('#headerControls')
    .append('div')
    .attr('id', 'panelTools')

  const hcPanels = ['info', 'legend', 'map', 'plot', 'locate', 'extent']
  const hcGlyphs = ['fa-info', 'fa-th-list', 'fa-map', 'fa-area-chart', 'fa-search', 'fa-globe']
  const hcLabel = ['Identify', 'Legend', 'Catchments', 'Plot', 'Locate', 'Zoom']

  d3.select('#panelTools').selectAll('divs')
    .data(hcPanels)
    .enter()
    .append('div')
    .attr('id', function (d) { return 'hc' + d.charAt(0).toUpperCase() + d.slice(1) + 'Div' })
    .attr('class', function (d) {
      if (d !== 'select') {
        return 'hcPanelDivs layerList'
      } else {
        return 'hcPanelDivs layerList disabled'
      }
    })
    .property('title', function (d, i) {
      if (d === 'extent') {
        return 'Click to zoom to initial extent'
      } else {
        return 'Click to show ' + hcLabel[i] + ' window'
      }
    })
    .html(function (d, i) {
      if (d !== 'search') {
        return '<span class="fa ' + hcGlyphs[i] + '"></span>'
      } else {
        return '<span class="fa ' + hcGlyphs[i] + '" data-toggle="collapse" data-target="#bingGeoLocate"></span>'
      }
    })
    .on('click', function (d) {
      switch (d) {
        case 'extent':
          map.fitBounds([[41.5, -74], [43, -69.5]])
          break
        default:
          toggleWindow(d)
          break
      }
    })

  // make tooltip for displaying attribute data
  tooltip = d3.select('body')
    .append('div')
    .attr('id', 'd3Tooltip')
    .attr('class', 'd3Tooltip')

  // make div for geoIndicator attributes
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'pointDiv')

  $('#pointDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option' })

  d3.select('#pointDiv')
    .append('h4')
    .text('Plot Attributes')
    .attr('class', 'legTitle')
    .attr('id', 'pointTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Identify</b></u></p><p>Displays attribute values for selected plot point.</p>"</span>')

  d3.select('#pointTitle')
    .html(d3.select('#pointTitle').html() + '<div class="exitDiv"><span id="hidePoint" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hidePoint')
    .on('click', function () { toggleWindow('point') })

  d3.select('#pointDiv')
    .append('div')
    .attr('id', 'pointAttrDiv')
    .append('table')
    .attr('id', 'pointAttrTable')

  // make div for info
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'infoDiv')

  $('#infoDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option' })

  d3.select('#infoDiv')
    .append('h4')
    .text('Identify')
    .attr('class', 'legTitle')
    .attr('id', 'infoTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Identify</b></u></p><p>Displays attribute value for visible overlay layers for a clicked point on the map</p>"</span>')

  d3.select('#infoTitle')
    .html(d3.select('#infoTitle').html() + '<div class="exitDiv"><span id="hideInfo" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hideInfo')
    .on('click', function () { toggleWindow('info') })

  d3.select('#infoDiv')
    .append('div')
    .attr('id', 'info')

  //* *****Make div for download
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'downloadDiv')

  $('#downloadDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option' })

  d3.select('#downloadDiv')
    .append('h4')
    .text('Download')
    .attr('class', 'legTitle')
    .attr('id', 'downloadTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Download</b></u></p><p>Download data for the current set of filtered locations as either a CSV or geoJSON (spatial files only) file.<br><br>NOTE: Queries for large numbers of sample locations and/or for raw data may take an extended time, but will appear in the bottom of this window for download once complete.</p>"</span>')

  d3.select('#downloadTitle')
    .html(d3.select('#downloadTitle').html() + '<div class="exitDiv"><span id="hideDownload" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hideDownload')
    .on('click', function () { toggleWindow('download') })

  d3.select('#downloadDiv')
    .append('div')
    .attr('id', 'download')
    .append('div')
    .html('<h6 class="filterHeader">File Format</h6><select id="downloadSelect" class="cl_select"><option>CSV</option><option>geoJSON</option></select><hr><h6 class="filterHeader">Output Tables</h6><div id="downloadChkDiv"><input type="checkbox" id="chkIndicators" class="downloadChk" checked>Indicator Data</input><br><input type="checkbox" id="chkSpecies" class="downloadChk">Species Data</input><br><input type="checkbox" id="chkRaw" class="downloadChk">Raw Data</input></div><hr>')

  d3.select('#download')
    .append('div')
    .attr('id', 'downloadButton')
    .attr('class', 'ldcButton')
    .text('Proceed')
    .property('title', 'Click to initiate queries for selected data')
    // .on('click', function () { downloadData() })

  d3.select('#download')
    .append('div')
    .attr('id', 'downloadLinks')
    .html('<img id="downloadGif" class="disabled" src="img/processing.gif"></img>')

  //* *****Add description to info tooltip
  d3.select('#info')
    .append('p')
    .attr('id', 'infoP')

  //* *****Make div for filter
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'filterDiv')

  $('#filterDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option' })

  d3.select('#filterDiv')
    .append('h4')
    .text('Filter')
    .attr('class', 'legTitle')
    .attr('id', 'filterTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Filter</b></u></p><p>Enables the filtering of data point locations through either feature selection on the map or attribute selection through the dropdown menu<br><br>NOTE: Display of filtered points on the map will only be visible at higher zoom levels.</p>"</span>')

  d3.select('#filterTitle')
    .html(d3.select('#filterTitle').html() + '<div class="exitDiv"><span id="hideFilter" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hideFilter')
    .on('click', function () { toggleWindow('filter') })

  d3.select('#filterDiv')
    .append('div')
    .attr('id', 'filter')
    .append('div')
    .attr('id', 'spatialFilter')
    .html('<h6 class="filterHeader">Spatial Filter</h6><input id="spatialFilterCB" type="checkbox"></input><label id="spatialFilterCBLabel">Enable</label><select id="spatialFilterSelect" class="cl_select disabled"></select>')

  d3.select('#filter')
    .append('hr')

  d3.select('#filter')
    .append('div')
    .attr('id', 'textFilter')
    .html('<h6 class="filterHeader">Attribute Filter</h6><label>Attribute</label><select id="catFilterSelect" class="cl_select"></select><br><label>Value</label><select id="valFilterSelect" class="cl_select disabled"><option>Select value...</option></select>')

  d3.select('#filter')
    .append('hr')

  d3.select('#filter')
    .append('div')
    .attr('id', 'filterCntDiv')
    .html('<p><span id="filterCnt">0</span> out of <span id="totalCnt">0</span> locations</p>')

  d3.select('#filter')
    .append('hr')

  d3.select('#filter')
    .append('div')
    .attr('id', 'filterCondDiv')

  d3.select('#filter')
    .append('div')
    .attr('id', 'spatialFilterClear')
    .attr('class', 'ldcButton')
    .text('Clear All Conditions')
}

function initPage () { // eslint-disable-line
  $('[data-toggle="tooltip"]').tooltip()

  window.addEventListener('resize', resizePanels)

  setupMap()

  // watch events and get data from postgres when level is appropriate and add as SVG
  map.on('moveend', function () {
    d3.select('#map').style('cursor', '')
    reset()
    polyFilter()
  })
  map.on('movestart', function () { d3.select('#map').style('cursor', 'grabbing') })

  topoSVG = d3.select(map.getPanes().overlayPane)
    .append('svg')
    .attr('id', 'topoSVG')
  topos = {}
  transform = d3.geoTransform({ point: projectPoint })
  path = d3.geoPath().projection(transform)
    .pointRadius(3.5 + (((map.getZoom() / 10) - 1) * 2))

  L.control.mousePosition().addTo(map)

  // * **Bing geocoder control
  let tmpPoint = new L.marker() // eslint-disable-line
  const bingGeocoder = new L.Control.BingGeocoder('At3gymJqaoGjGje-JJ-R5tJOuilUk-gd7SQ0DBZlTXTsRoMfVWU08ZWF1X7QKRRn', {
    callback: function (results) {
      if (results.statusCode === 200) {
        if (d3.select('#bingGeocoderSubmit').classed('fa-search')) {
          $(document).ready(function () {
            $('[data-toggle="tooltip"]').tooltip()
          })
          document.getElementById('bingGeocoderInput').blur()
          const bbox = results.resourceSets[0].resources[0].bbox
          const first = new L.LatLng(bbox[0], bbox[1])
          const second = new L.LatLng(bbox[2], bbox[3])
          const tmpBounds = new L.LatLngBounds([first, second])
          this._map.fitBounds(tmpBounds)
          this._map.removeLayer(tmpPoint)
          tmpPoint = new L.marker(results.resourceSets[0].resources[0].point.coordinates) // eslint-disable-line
          this._map.addLayer(tmpPoint)
          d3.select('.leaflet-marker-icon')
            .attr('id', 'mapIcon')
            .attr('value', results.resourceSets[0].resources[0].name)
            .attr('data-toggle', 'tooltip')
            .attr('data-container', 'body')
            .attr('data-placement', 'top')
            .attr('data-html', 'true')
            .attr('title', '<p><b>' + results.resourceSets[0].resources[0].name + '</b></p>')
          d3.select(tmpPoint)
            .on('click', function () { clearSearch() })
          d3.select('#bingGeocoderSubmit')
            .classed('fa-search', false)
            .classed('fa-times', true)
            .property('title', 'Click to clear locate results')
        } else {
          clearSearch()
        }
      } else {
        d3.select('#bingGeocoderInput').property('value', 'No matching results')
      }
    }
  })

  d3.select('body')
    .insert('div', ':first-child')
    .attr('id', 'headerControls')

  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'locateDiv')

  $('#locateDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option' })

  d3.select('#locateDiv')
    .append('h4')
    .text('Locate')
    .attr('class', 'legTitle')
    .attr('id', 'locateTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Locate</b></u></p><p>Enter name or coordinates to zoom to a location on the map.</p>"</span>')

  d3.select('#locateTitle')
    .html(d3.select('#locateTitle').html() + '<div class="exitDiv"><span id="hideLocate" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hideLocate')
    .on('click', function () { toggleWindow('locate') })

  d3.select('#locateDiv')
    .append('div')
    .attr('id', 'bingGeoLocate')

  document.getElementById('bingGeoLocate').appendChild(bingGeocoder.onAdd(map))
  d3.select('#bingGeocoderInput')
    .on('mouseup', function () { if (this.value === 'No matching results') { this.value = '' } else { $(this).select() } })
    .on('blur', function () { modifySearch(this, 'blur') })
    .on('keyup', function () { modifySearch(this, 'key') })

  function modifySearch (tmpEl, tmpEvent) {
    if (tmpEvent === 'blur') {
      if ((tmpEl.value === '' || tmpEl.value === 'No matching results') && document.getElementById('mapIcon')) {
        tmpEl.value = d3.select('#mapIcon').attr('value')
        d3.select('#bingGeocoderSubmit').classed('fa-times', true).classed('fa-search', false)
      } else if (tmpEl.value === 'No matching results' && !document.getElementById('mapIcon')) {
        tmpEl.value = ''
      }
    } else if (document.getElementById('mapIcon')) {
      if (tmpEl.value !== d3.select('#mapIcon').attr('value')) {
        d3.select('#bingGeocoderSubmit').classed('fa-times', false).classed('fa-search', true)
      } else {
        d3.select('#bingGeocoderSubmit').classed('fa-times', true).classed('fa-search', false)
      }
    }
  }

  // clear the results of the geo search
  function clearSearch () {
    map.removeLayer(tmpPoint)
    d3.select('.tooltip').remove()
    d3.select('#bingGeocoderInput').property('value', '')

    d3.select('#bingGeocoderSubmit')
      .classed('fa-times', false)
      .classed('fa-search', true)
      .style('background', '')
      .property('title', 'Click to zoom to specified location')
  }

  const googleHybrid = L.tileLayer('https://{s}.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}', {
    maxZoom: 20,
    subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
  })
  const googleSatellite = L.tileLayer('https://{s}.google.com/vt/lyrs=s&x={x}&y={y}&z={z}', {
    maxZoom: 20,
    subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
  })
  const googleStreet = L.tileLayer('https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', {
    maxZoom: 20,
    subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
  })
  const googleTerrain = L.tileLayer('https://{s}.google.com/vt/lyrs=p&x={x}&y={y}&z={z}', {
    maxZoom: 20,
    subdomains: ['mt0', 'mt1', 'mt2', 'mt3']
  })
  // var usgsTopo = new L.tileLayer('https://basemap.nationalmap.gov/ArcGIS/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}', {
  //   maxZoom: 15,
  //   zIndex: 0,
  //   attribution: '<a href="http://www.doi.gov">U.S. Department of the Interior</a> | <a href="https://www.usgs.gov">U.S. Geological Survey</a> | <a href="https://www.usgs.gov/laws/policies_notices.html">Policies</a>'
  // });

  // var countries = L.tileLayer.wms('https://landscapedatacommons.org/geoserver/wms', {
  //   layers: 'ldc:countries_wgs84',
  //   format: 'image/png',
  //   transparent: true,
  //   tiled: true,
  //   version: '1.3.0',
  //   maxZoom: 20
  // });
  const blank = new L.tileLayer('') // eslint-disable-line

  const background = L.tileLayer.wms('https://ecosheds.org/geoserver/wms', {
    layers: 'refugia:background',
    format: 'image/png',
    transparent: true,
    tiled: true,
    version: '1.3.0',
    maxZoom: 20
  })

  const counties = L.tileLayer.wms('https://ecosheds.org/geoserver/wms', {
    layers: 'refugia:counties_ma',
    format: 'image/png',
    transparent: true,
    tiled: true,
    version: '1.3.0',
    maxZoom: 20
  })

  const huc8 = L.tileLayer.wms('https://ecosheds.org/geoserver/wms', {
    layers: 'refugia:huc8_ma',
    format: 'image/png',
    transparent: true,
    tiled: true,
    version: '1.3.0',
    maxZoom: 20
  })

  const huc10 = L.tileLayer.wms('https://ecosheds.org/geoserver/wms', {
    layers: 'refugia:huc10_ma',
    format: 'image/png',
    transparent: true,
    tiled: true,
    version: '1.3.0',
    maxZoom: 20
  })

  const huc12 = L.tileLayer.wms('https://ecosheds.org/geoserver/wms', {
    layers: 'refugia:huc12_ma',
    format: 'image/png',
    transparent: true,
    tiled: true,
    version: '1.3.0',
    maxZoom: 20
  })

  const flowlines = L.tileLayer.wms('https://ecosheds.org/geoserver/wms', {
    layers: 'refugia:flowlines_ma',
    format: 'image/png',
    transparent: true,
    tiled: true,
    version: '1.3.0',
    maxZoom: 20
  })

  const opaVar = [counties, huc8, huc10, huc12, flowlines]
  const infoObj = {
    counties_ma: 'Counties',
    huc8_ma: 'HUC-8',
    huc10_ma: 'HUC-10',
    huc12_ma: 'HUC-12',
    flowlines_ma: 'Streams'
  }
  const infoIDField = {
    counties_ma: 'county',
    huc8_ma: 'name',
    huc10_ma: 'name',
    huc12_ma: 'name',
    flowlines_ma: 'featureid'
  }
  const overlayID = d3.keys(infoObj)
  const baselayers = {
    'Google Terrain': googleTerrain,
    'Google Hybrid': googleHybrid,
    'Google Satellite': googleSatellite,
    'Google Street': googleStreet,
    None: blank
  }
  const overlays = {
    Counties: counties,
    'HUC-8': huc8,
    'HUC-10': huc10,
    'HUC-12': huc12,
    Streams: flowlines
  }
  const overlayTitles = d3.keys(overlays)

  const layerNames = {}
  layerNames.baseLayers = baselayers
  layerNames.baseLayers.keys = d3.keys(layerNames.baseLayers)
  layerNames.baseLayers.values = d3.values(layerNames.baseLayers)

  layerNames.overlays = {}
  overlayTitles.forEach(function (tmpTitle, i) {
    layerNames.overlays[tmpTitle] = opaVar[i]
  })
  layerNames.overlays.keys = d3.keys(overlays)
  layerNames.overlays.values = d3.values(overlays)

  d3.select('#headerControls')
    .insert('div', ':first-child')
    .attr('id', 'mapTools')
    .append('div')
    .attr('id', 'baselayerSelect')
    .attr('class', 'layerList')
    .append('div')
    .attr('id', 'baselayerList')
    .attr('class', 'cl_select')
    .property('title', 'Click to change map baselayer')
    .html('<span id="baselayerListHeader">Change Baselayer</span><span class="fa fa-caret-down pull-right" style="position:relative;top:3px;"></span>')
    .on('click', function () {
      if (d3.select('#baselayerListDropdown').style('display') === 'none') {
        d3.select('#baselayerListDropdown').style('display', 'inline-block')
      } else {
        d3.select('#baselayerListDropdown').style('display', 'none')
      }
    })

  d3.select('#baselayerSelect')
    .append('div')
    .attr('id', 'baselayerListDropdown')
    .attr('class', 'layerListDropdown')
    .on('mouseleave', function () {
      return d3.select(this).style('display', 'none')
    })

  d3.select('#baselayerListDropdown').selectAll('div')
    .data(layerNames.baseLayers.keys)
    .enter()
    .append('div')
    .attr('class', 'layerName')
    .text(function (d) { return d })
    .property('value', function (d, i) { return i })
    .property('title', function (d) { return d })
    .on('click', function () { changeBaselayer(this) })
    .append('span')
    .attr('class', 'fa fa-check pull-right activeOverlay')
    .style('visibility', function (d, i) { if (i === 0) { return 'visible' } else { return 'hidden' } })

  map.addLayer(googleTerrain)
  map.addLayer(background)

  function changeBaselayer (tmpDiv) {
    const layerDivs = d3.select('#baselayerListDropdown').selectAll('div')

    layerDivs._groups[0].forEach(function (tmpLayer) {
      if (d3.select(tmpLayer).select('span').style('visibility') === 'visible') {
        d3.select(tmpLayer).select('span').style('visibility', 'hidden')
        map.removeLayer(layerNames.baseLayers.values[d3.select(tmpLayer).property('value')])
      }
    })

    d3.select(tmpDiv).select('span').style('visibility', 'visible')
    map.addLayer(layerNames.baseLayers.values[tmpDiv.value])
    layerNames.baseLayers.values[tmpDiv.value].bringToBack()
  }

  d3.select('#mapTools')
    .append('div')
    .attr('id', 'overlaySelect')
    .attr('class', 'layerList')
    .append('div')
    .attr('id', 'overlayList')
    .attr('class', 'cl_select')
    .property('title', 'Click to select overlay layers to display on map')
    .html('<span id="overlayListHeader">View Overlay Layers</span><span class="fa fa-caret-down pull-right" style="position:relative;top:3px;"></span>')
    .on('click', function () {
      if (d3.select('#overlayListDropdown').style('display') === 'none') {
        d3.select('#overlayListDropdown').style('display', 'inline-block')
      } else {
        d3.select('#overlayListDropdown').style('display', 'none')
      }
    })
  d3.select('#overlaySelect')
    .append('div')
    .attr('id', 'overlayListDropdown')
    .attr('class', 'layerListDropdown')
    .on('mouseleave', function () {
      return d3.select(this).style('display', 'none')
    })

  d3.select('#overlayListDropdown').selectAll('div')
    .data(layerNames.overlays.keys)
    .enter()
    .append('div')
    .attr('id', function (d, i) { return 'layerToggleDiv' + i })
    .attr('class', 'layerName')
    .text(function (d) { return d })
    .property('value', function (d, i) { return i })
    .property('title', function (d) { return d })
    .property('name', function (d, i) { return overlayID[i] })
    .on('click', function () { changeOverlay(this) })
    .append('span')
    .attr('class', 'fa fa-check pull-right activeOverlay')
    .style('visibility', 'hidden')

  function changeOverlay (tmpDiv) {
    if (d3.select(tmpDiv).select('span').style('visibility') === 'hidden') {
      d3.select(tmpDiv).select('span').style('visibility', 'visible')
      map.addLayer(layerNames.overlays.values[tmpDiv.value])
      layerNames.overlays.values[tmpDiv.value].bringToFront()
      addLegendImg(tmpDiv.name, tmpDiv.title, layerNames.overlays.values[tmpDiv.value], ['overlays', tmpDiv.title])
    } else {
      d3.select(tmpDiv).select('span').style('visibility', 'hidden')
      removeTopo(topos[d3.select(tmpDiv).property('name')])
      map.removeLayer(layerNames.overlays.values[tmpDiv.value])
      remLegendImg(tmpDiv.name)
    }
  }

  d3.select('#topoSVG').selectAll('g')
    .data(overlayID)
    .enter()
    .append('g')
    .attr('id', function (d) { topos[d] = { g: this, class: d }; return d + 'G' })
    .attr('class', 'leaflet-zoom-hide')

  for (const obj in infoIDField) {
    topos[obj].id = infoIDField[obj]
    topos[obj].gids = []
    topos[obj].feats = []
  }

  d3.select('#topoSVG')
    .append('g')
    .attr('id', 'catchments_maG')
    .attr('class', 'leaflet-zoom-hide')

  topos.catchments_ma = {
    g: d3.select('#catchments_maG')._groups[0][0],
    id: 'FEATUREID',
    gids: [],
    feats: []
  }

  Promise.all([
    d3.json('data/geojson/catchments_ma.json'),
    d3.tsv('data/model/1.2.2/df_app_data.tsv'),
    d3.csv('data/model/1.2.2/df_z_group.csv'),
    d3.csv('data/model/1.2.2/ranef_glmm.csv'),
    d3.csv('data/model/1.2.2/summary_glmm.csv'),
    d3.json('data/model/2.0.0/bto-model-v2.0.0-params.json')
  ]).then(render)

  function render (data) {
    topos.catchments_ma.topo = topojson.feature(data[0], data[0].objects.catchments_ma)

    // crossfilter
    const xf = crossfilter(data[1])
    topos.xf = {}
    topos.xf.ranges = {}
    topos.xf.xf = xf
    topos.xf.all = xf.groupAll()
    const keys = data[1].columns
    topos.xf.keys = keys
    keys.forEach(key => {
      topos.xf[key] = xf.dimension(d => d[key] === '' ? -Infinity : +d[key])
      // topos.xf[key + 's'] = topos.xf[key].group() //* **Probably not necessary to make groups since we're not graphing
      topos.xf[key].filterFunction(d => d > -Infinity)

      topos.xf.ranges[key] = {
        min: parseFloat(topos.xf[key].bottom(1)[0][key]),
        max: parseFloat(topos.xf[key].top(1)[0][key])
      }
      topos.xf[key].filterAll()
    })

    const newKeys = JSON.parse(JSON.stringify(keys))
    newKeys[0] = 'None'
    newKeys.splice(1, 1)
    d3.select('#catchmentSelect').selectAll('options')
      .data(newKeys)
      .enter()
      .append('option')
      .attr('data-attr', function (d) { return d })
      .attr('value', function (d) { return d })
      .text(function (d) { return d })

    topos.model = {}
    topos.model.app_data = {}
    topos.model.z_group = {}
    topos.model.ranef_glmm = {}
    topos.model.summary_glmm = {}
    topos.model.params = data[5]
    topos.model.params.randomMap = d3.map(data[5].random, d => d.huc8)

    data[1].forEach(function (row) {
      const tmpObj = {}
      data[1].columns.slice(1).forEach(function (key) {
        if (key === 'huc10') {
          tmpObj[key] = row[key]
        } else {
          tmpObj[key] = parseFloat(row[key])
        }
      })
      topos.model.app_data[row.FEATUREID.toString()] = tmpObj
    })

    data[2].forEach(function (row) {
      topos.model.z_group[row.var] = { mean: parseFloat(row.mean), sd: parseFloat(row.sd) }
    })

    data[3].forEach(function (row) {
      topos.model.ranef_glmm[row.huc10] = { Intercept: parseFloat(row.Intercept), AreaSqKM: parseFloat(row.AreaSqKM), agriculture: parseFloat(row.agriculture), summer_prcp_mm: parseFloat(row.summer_prcp_mm), mean_jul_temp: parseFloat(row.mean_jul_temp) }
    })

    data[4].forEach(function (row) {
      topos.model.summary_glmm[row.variable] = { Estimate: parseFloat(row.Estimate), SE: parseFloat(row['Std.Error']) }
    })

    topos.catchments_ma.topo.features.forEach(function (feat) {
      feat.properties = Object.assign({}, feat.properties, topos.model.app_data[feat.properties.FEATUREID.toString()])
    })

    addTopo(topos.catchments_ma)

    d3.select('#plotY')
      .on('change', function () {
        if (d3.select('#plotDiv').attr('data-props') != null) {
          makePlot(JSON.parse(d3.select('#plotDiv').attr('data-props')))
        }
      })
      .selectAll('option')
      .data(data[1].columns.slice(2, 8))
      .enter()
      .append('option')
      .text(function (d) { return d })

    d3.select('#plotX')
      .on('change', function () {
        if (d3.select('#plotDiv').attr('data-props') != null) {
          makePlot(JSON.parse(d3.select('#plotDiv').attr('data-props')))
        }
      })
      .selectAll('option')
      .data(data[1].columns.slice(2, 8))
      .enter()
      .append('option')
      .text(function (d) { return d })

    d3.select('#plotX')
      .property('selectedIndex', 1)
    d3.select('#plotY')
      .property('selectedIndex', 3)

    d3.select('#catchmentSelect')
      .property('selectedIndex', 8)

    setMappedAttribute(d3.select('#catchmentSelect').property('value'), color)
    toggleWindow('map')
  }

  // remove selectable SVG layer when spatial filter is unchecked or layer is removed
  function polyFilter () {
    const tmpLayer = d3.select('#spatialFilterSelect').attr('data-layer')
    if (d3.select('#spatialFilterCB').property('checked')) {
      if (tmpLayer != null) {
        d3.selectAll('.' + tmpLayer).classed('disabled', false)
        addTopo(topos[tmpLayer])
      } else {
        d3.selectAll('.' + tmpLayer).remove()
      }
    } else {
      d3.selectAll('.' + tmpLayer).classed('disabled', true)
    }
  }

  setupUi()

  d3.select('#spatialFilterCB')
    .on('click', function () {
      if (this.checked) {
        d3.select('#spatialFilterSelect').classed('disabled', false)
      } else {
        d3.select('#spatialFilterSelect').classed('disabled', true)
      }
      polyFilter()
    })

  d3.select('#spatialFilterCBLabel')
    .on('click', function () { $('#spatialFilterCB').trigger('click') })

  d3.select('#spatialFilterClear')
    .on('click', function () {
      for (const obj in topos.geoIndicators.cf.filters) {
        if (obj !== 'type' && obj !== 'geoIndicators') {
          topos.geoIndicators.cf[obj].filterAll()
          topos.geoIndicators.cf.filters[obj] = []
        }
      }

      for (const obj in topos.geoIndicators.cf.filters) {
        if (obj !== 'type' && obj !== 'geoIndicators' && topos.geoIndicators.cf.filters.type[obj] === 'spatial') {
          spatialFilter(obj)
          break
        }
      }

      for (const obj in topos.geoIndicators.cf.filters) {
        if (obj !== 'type' && obj !== 'geoIndicators' && topos.geoIndicators.cf.filters.type[obj] === 'categorical') {
          catFilter(obj)
          break
        }
      }

      d3.select('#filterCondDiv').selectAll('div').remove()
      d3.selectAll('.svgSelected').classed('svgSelected', false)
      d3.select('#valFilterSelect').property('selectedIndex', 0)
      d3.select(this).style('display', 'none')
    })

  const optList = {
    'Select Layer': '',
    States: 'layerToggleDiv0',
    Counties: 'layerToggleDiv1',
    MLRA: 'layerToggleDiv3',
    'HUC-6': 'layerToggleDiv5',
    'HUC-8': 'layerToggleDiv6'
  }
  const topoArray = [null, 'tl_2017_us_state_wgs84', 'tl_2017_us_county_wgs84', 'mlra_v42_wgs84', 'wbdhu6_wgs84', 'wbdhu8_wgs84']
  d3.select('#spatialFilterSelect')
    .attr('data-layer', null)
    .on('change', function () {
      if (d3.select('#' + this.value).select('span').style('visibility') === 'hidden') {
        changeOverlay(d3.select('#' + this.value)._groups[0][0])
      }
      const tmpLayer = d3.select(document.getElementById('spatialFilterSelect').selectedOptions[0]).attr('data-layer')
      d3.selectAll('.' + d3.select(this).attr('data-layer')).remove()
      d3.select(this).attr('data-layer', tmpLayer)
      polyFilter()
      spatialFilter(tmpLayer)
    })
    .on('mousedown', function () { d3.select(this).select('option').style('display', 'none') })
    .selectAll('option')
    .data(d3.keys(optList))
    .enter()
    .append('option')
    .property('disabled', function (d, i) { if (i === 0) { return 'disabled' } })
    .attr('value', function (d) { return optList[d] })
    .attr('data-layer', function (d, i) { return topoArray[i] })
    .text(function (d) { return d })

  function catFilter (tmpCat) {
    if (topos.geoIndicators.cf.filters[tmpCat].length > 0) {
      topos.geoIndicators.cf[tmpCat].filterFunction(function (d) { return topos.geoIndicators.cf.filters[tmpCat].indexOf(d) > -1 })
    } else {
      topos.geoIndicators.cf[tmpCat].filterAll()
    }

    const tmpGeo = topos.geoIndicators.cf[tmpCat].bottom(Infinity)
    const geoIDs = tmpGeo.map(function (d) { return d.geoIndicators })
    d3.selectAll('.geoIndicators')
      .style('display', function (d) {
        if (geoIDs.indexOf(d.id) > -1) {
          return 'block'
        } else {
          return 'none'
        }
      })
    d3.selectAll('#filterCnt').text(topos.geoIndicators.cf.geoIndicators.top(Infinity).length)
  }

  //* *****Make div for catchment styling
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'mapDiv')

  $('#mapDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option' })

  d3.select('#mapDiv')
    .append('h4')
    .text('Catchments')
    .attr('class', 'legTitle')
    .attr('id', 'mapTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Catchments</b></u></p><p>Control the display and mapped attribute for the catchments.</p>"</span>')

  d3.select('#mapTitle')
    .html(d3.select('#mapTitle').html() + '<div class="exitDiv"><span id="hideMap" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hideMap')
    .on('click', function () { toggleWindow('map') })

  d3.select('#mapDiv')
    .append('div')
    .attr('id', 'catchmentDiv')
    .html('<div><h5 class="plotSelectTitle" id="catchDisplayH5">Display</h5><span><input id="catchDisplay" type="checkbox" data-toggle="toggle" checked></input></span></div>' +
      '<hr>' +
      '<div><h5 class="plotSelectTitle">Mapped Attribute</h5><select id="catchmentSelect"></select></div>' +
      '<div id="colorScale"></div>' +
      '<div id="csLabelContainer"><div id="csMinDiv" class="csLabelDiv"><p1 id="csMin" class="csLabel"></p1></div><div id="csMidDiv" class="csLabelDiv"><p1 id="csMid" class="csLabel"></p1></div><div id="csMaxDiv" class="csLabelDiv"><p1 id="csMax" class="csLabel"></p1></div></div>' +
      '<hr>' +
      '<div id="catchOpacity" class="plotSlider" title="Catchment fill opacity: 100%"></div>'
    )

  $('#catchDisplay').bootstrapToggle({ on: 'YES', off: 'NO', size: 'mini', style: 'on_off', width: '55px' }).change(function () { if ($(this).prop('checked')) { d3.selectAll('.activeTopo').style('visibility', 'visible') } else { d3.selectAll('.activeTopo').style('visibility', 'hidden') } })

  d3.select('#catchmentSelect')
    .on('change', function () { d3.selectAll('.svgSelected').classed('svgSelected', false); setMappedAttribute(this.value, color) })

  const color = d3.scaleLinear()
    .domain([0, 0.25, 0.5, 0.75, 1])
    .range([d3.rgb(68, 2, 86), d3.rgb(59, 82, 139), d3.rgb(33, 145, 140), d3.rgb(42, 176, 127), d3.rgb(253, 231, 37)])
    .interpolate(d3.interpolateRgb)

  const tmpDiv = d3.select('#colorScale')
  for (let i = 0; i < 100; i++) {
    tmpDiv.append('div')
      .attr('class', 'colorScaleDiv')
      .style('background', function () { return color(i / 100) })
  }

  $('#catchOpacity').slider({ animate: 'fast', min: 0, max: 100, value: 100, slide: function (event, ui) { d3.selectAll('.activeTopo').style('fill-opacity', function () { d3.select('#catchOpacity').property('title', 'Catchment fill opacity: ' + ui.value + '%'); return ui.value / 100 }) } })

  //* *****Make div for plot
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'plotDiv')

  $('#plotDiv').draggable({ containment: 'html', cancel: '.toggle-group,input,textarea,button,select,option,#surfaceDiv,.plotSlider' })

  d3.select('#plotDiv')
    .append('h4')
    .text('Plot')
    .attr('class', 'legTitle')
    .attr('id', 'plotTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Plot</b></u></p><p>Create a bivariate surface plot of brook trout occupancy for two customizable variables.</p>"</span>')

  d3.select('#plotTitle')
    .html(d3.select('#plotTitle').html() + '<div class="exitDiv"><span id="hidePlot" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hidePlot')
    .on('click', function () {
      return toggleWindow('plot')
    })

  d3.select('#plotDiv')
    .append('div')
    .attr('id', 'plotControlDiv')
    .html('<div class="plotSelectDiv">' +
      '<h5 class="plotSelectTitle">Y-Axis Variable</h5>' +
      '<select id="plotY" class="cl_select"></select>' +
      '</div>' +
      '<div class="plotSelectDiv">' +
      '<h5 class="plotSelectTitle">X-Axis Variable</h5>' +
      '<select id="plotX" class="cl_select"></select>' +
      '</div>' +
      '<div id="surfaceDiv"></div>' +
      '<div class="plotSliderDiv">' +
      '<h5 id="plotSliderTitleY" class="plotSelectTitle">Y-Axis Variable</h5>' +
      '<div id="plotSliderY" class="plotSlider"></div>' +
      '<span id="plotRefreshY" class="fa fa-refresh sliderSpan" title="Reset to initial value"></span>' +
      '</div>' +
      '<div class="plotSliderDiv">' +
      '<h5 id="plotSliderTitleX" class="plotSelectTitle">X-Axis Variable</h5>' +
      '<div id="plotSliderX" class="plotSlider"></div>' +
      '<span id="plotRefreshX" class="fa fa-refresh sliderSpan" title="Reset to initial value"></span>' +
      '</div>' +
      '<div id="predOccDiv"><h5>Predicted Occupancy: <span id="predOcc">0.00</span></h5></div>'
    )

  //* *****Make div for legend
  d3.select('body')
    .append('div')
    .attr('class', 'legend gradDown')
    .attr('id', 'legendDiv')

  $('#legendDiv').draggable({ containment: 'html', cancel: '.toggle-group,.layerLegend,textarea,button,select,option' })

  d3.select('#legendDiv')
    .append('h4')
    .text('Legend')
    .attr('class', 'legTitle')
    .attr('id', 'legendTitle')
    .append('span')
    .html('<span class="fa fa-info-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p><u><b>Legend</b></u></p><p>Displays legends for added map layers enabling their interpretation along with control over their transparency.<br><br>Drag and drop layers to change their order on the map.</p>"</span>')

  d3.select('#legendTitle')
    .html(d3.select('#legendTitle').html() + '<div class="exitDiv"><span id="hideLegend" class="fa fa-times-circle" data-toggle="tooltip" data-container="body" data-placement="auto" data-html="true" title="<p>Click to hide window</p>"</span></div>')

  d3.select('#hideLegend')
    .on('click', function () { toggleWindow('legend') })

  d3.select('#legendDiv')
    .append('div')
    .attr('id', 'legendDefault')
    .text('Add a map layer to view its legend...')

  d3.select('#legendDiv')
    .append('div')
    .attr('id', 'legendImgDiv')

  $('#legendImgDiv').sortable({ appendTo: '#legendImgDiv', containment: '#legendImgDiv', cancel: 'input,textarea,button,select,option', forcePlaceholderSize: true, placeholder: 'sortable-placeholder', helper: 'original', tolerance: 'pointer', stop: function (event, ui) { reorder(event, ui) }, start: function (event, ui) { helperPlaceholder(event, ui) } })

  // change the layer orders after drag and drop
  function reorder (tmpEvent, tmpUI) {
    const tmpCnt = tmpEvent.target.children.length
    let i = 0
    for (const child of tmpEvent.target.children) {
      overlays[infoObj[child.id.slice(0, -6)]].setZIndex(tmpCnt - i)
      i += 1
    }
  }

  // style the helper and placeholder when dragging/sorting
  function helperPlaceholder (tmpEvent, tmpUI) {
    console.log(tmpUI)
    d3.select('.ui-sortable-placeholder.sortable-placeholder').style('width', d3.select('#' + tmpUI.item[0].id).style('width')).style('height', '37px') // .style("background", "rgba(255,255,255,0.25)");
  }

  // adds images to the legend
  function addLegendImg (tmpName, tmpTitle, tmpLayer, tmpPath) {
    let tmpOpa = 1
    if (tmpName.includes('surf') || tmpName.includes('mlra')) {
      tmpOpa = 0.6
    }
    tmpLayer.setOpacity(tmpOpa)

    d3.select('#legendImgDiv')
      .insert('div', ':first-child')
      .attr('id', tmpName + 'Legend')
      .attr('value', tmpPath)
      .attr('class', 'layerLegend')
      .append('div')
      .attr('id', tmpName + 'LegendHeader')
      .attr('data-toggle', 'collapse')
      .attr('data-target', '#' + tmpName + 'collapseDiv')
      .on('click', function () { changeCaret(d3.select(this).select('span')._groups[0][0]) })
      .append('div')
      .attr('class', 'legendTitle')
      .html('<h6>' + tmpTitle + '</h6><div class="exitDiv"><span class="fa fa-caret-down legendCollapse" title="View legend"></span></div>')

    function changeCaret (tmpSpan) {
      if (d3.select(tmpSpan).classed('fa-caret-down')) {
        d3.select(tmpSpan).classed('fa-caret-down', false).classed('fa-caret-up', true).property('title', 'Hide legend')
      } else {
        d3.select(tmpSpan).classed('fa-caret-up', false).classed('fa-caret-down', true).property('title', 'View legend')
      }
    }

    d3.select('#' + tmpName + 'Legend')
      .append('div')
      .attr('id', tmpName + 'collapseDiv')
      .attr('class', 'collapseDiv collapse')
      .append('div')
      .attr('id', tmpName + 'LegImgDiv')
      .attr('class', 'legImgDiv')
      .append('img')
      .attr('id', tmpName + 'LegendImg')
      .attr('class', 'legendImg')
      .property('title', tmpTitle)

    $('#' + tmpName + 'collapseDiv').on('shown.bs.collapse', function () { resizePanels() })
    $('#' + tmpName + 'collapseDiv').on('hidden.bs.collapse', function () { resizePanels() })

    //* **Set div width and offset after the image has been loaded
    $('#' + tmpName + 'LegendImg').one('load', function () {
      const tmpRect = document.getElementById(tmpName + 'LegendImg').getBoundingClientRect()
      d3.select('#' + tmpName + 'LegImgDiv').style({ 'max-height': tmpRect.height - 67 + 'px', 'max-width': tmpRect.width + 'px' })
      d3.select('#' + tmpName + 'Legend').style('opacity', '1')
    }).attr('src', 'https://ecosheds.org/geoserver/wms?REQUEST=GetLegendGraphic&VERSION=1.0.0&FORMAT=image/png&WIDTH=30&HEIGHT=30&LAYER=refugia:' + tmpName)

    d3.select('#' + tmpName + 'collapseDiv')
      .append('div')
      .attr('id', tmpName + 'LegendSlider')
      .property('title', tmpTitle + ' Layer Opacity: ' + tmpOpa * 100 + '%')

    $('#' + tmpName + 'LegendSlider').slider({ animate: 'fast', min: 0, max: 100, value: tmpOpa * 100, slide: function (event, ui) { layerOpacity(ui, tmpLayer) } })

    d3.select('#legendDefault').style('display', 'none')

    d3.select('#legendImgDiv')
      .style('display', 'block')

    if (d3.select('#legendDiv').style('opacity') === 0) {
      toggleWindow('legend')
    }

    resizePanels()
  }

  // removes images to the legend
  function remLegendImg (tmpName) {
    d3.select('#' + tmpName + 'Legend').remove()

    if (d3.select('#legendImgDiv').selectAll('div')._groups[0].length === 0) {
      d3.select('#legendImgDiv').style('display', 'none')
      d3.select('#legendDefault').style('display', 'block')
    }
  }

  // change transparency of current legend layer
  function layerOpacity (tmpSlider, tmpLayer) {
    const tmpOpacity = tmpSlider.value / 100
    tmpSlider.title = 'Opacity: ' + tmpSlider.value + '%'
    tmpLayer.setOpacity(tmpOpacity)
  }

  // add div for catchment attribute info
  d3.select('body')
    .append('div')
    .attr('id', 'catchInfoVals')
    .attr('class', 'd3Tooltip')

  //* *****Set z-indexes of moveable divs so that clicked one is always on top
  d3.selectAll('#legendDiv,#infoDiv,#locateDiv,#filterDiv,#pointDiv,#downloadDiv,#plotDiv,#mapDiv')
    .on('mousedown', function () { setZ(this) })

  map.addEventListener('click', getInfo)

  function getInfo (e) {
    // console.log(e.latlng.lat.toFixed(3) + ", " + e.latlng.lng.toFixed(3));
    let i = -1
    let tmpLayers = ''
    map.eachLayer(function (layer) {
      i += 1
      //* **Exclude baselayer and points layer
      if (typeof layer.options.layers !== 'undefined' && layer.options.layers.includes('background') === false && layer.options.layers.includes('countries_wgs84') === false) {
        if (tmpLayers === '') {
          tmpLayers = layer.options.layers
        } else {
          tmpLayers = layer.options.layers + ',' + tmpLayers
        }
      }
    })

    const bbox = map.getBounds() // .toBBoxString();
    const tmpStr = bbox._southWest.lat + ',' + bbox._southWest.lng + ',' + bbox._northEast.lat + ',' + bbox._northEast.lng
    const tmpWidth = map.getSize().x
    const tmpHeight = map.getSize().y
    const tmpI = map.layerPointToContainerPoint(e.layerPoint).x
    const tmpJ = map.layerPointToContainerPoint(e.layerPoint).y

    const tmpUrl = 'https://ecosheds.org/geoserver/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetFeatureInfo&LAYERS=' + tmpLayers + '&QUERY_LAYERS=' + tmpLayers + '&BBOX=' + tmpStr + '&FEATURE_COUNT=' + (i * 5) + '&HEIGHT=' + tmpHeight + '&WIDTH=' + tmpWidth + '&INFO_FORMAT=application/json&CRS=EPSG:4326&i=' + tmpI + '&j=' + tmpJ
    // console.log(tmpUrl);

    // send the request using jQuery $.ajax
    $.ajax({
      url: tmpUrl,
      dataType: 'json',
      type: 'GET',
      success: function (data) {
        let tmpText = ''
        data.features.forEach(function (tmpFeat, j) {
          let tmpID = tmpFeat.id.split('.')[0]
          if (tmpID !== '') {
            addInfo(tmpID, tmpFeat.properties[infoIDField[tmpID]])
          } else if (tmpID === '') {
            if (tmpID === '') {
              tmpID = 'aspect_elevation'
            }
            let tmpObj = 'NULL'
            if (typeof tmpFeat.properties.PALETTE_INDEX !== 'undefined') {
              tmpObj = 'PALETTE_INDEX'
            } else if (typeof tmpFeat.properties.GRAY_INDEX !== 'undefined') {
              tmpObj = 'GRAY_INDEX'
            }
            addInfo(tmpID, Math.round(tmpFeat.properties[tmpObj]))
          } else {
            addInfo(tmpID, '')
          }
        })
        d3.select('#infoP').text(tmpText)
        if (d3.select('#infoDiv').style('opacity') === 0) { toggleWindow('info') }
        resizePanels()

        function addInfo (tmpId, tmpInfo) {
          if (tmpText === '') {
            tmpText = infoObj[tmpId] + ': ' + tmpInfo
          } else {
            tmpText += '\n' + infoObj[tmpId] + ': ' + tmpInfo
          }
        }
      }
    })
  }

  reset()
}

function setZ (el) {
  // console.log('setZ()', el)
  if (!d3.select('#map').classed('introjs-showElement')) {
    d3.selectAll('#legendDiv,#infoDiv,#locateDiv,#filterDiv,#pointDiv,#downloadDiv,#plotDiv,#mapDiv')
      .style('z-index', function () {
        if (d3.select(this).style('opacity') === 1) {
          return 1001
        } else {
          return 7500
        }
      })
    d3.select(el).style('z-index', 1002)
  }
}

function toggleWindow (name) {
  console.log(`toggleWindow(${name})`)

  const labels = {
    legend: 'Legend',
    info: 'Identify',
    locate: 'Locate',
    filter: 'Filter',
    plot: 'Plot',
    map: 'Catchments'
  }

  if (d3.select('#' + name + 'Div').style('opacity') === '1') {
    // hide
    d3.select('#' + name + 'Div')
      .transition()
      .style('opacity', '0')
      .style('visibility', 'hidden')
      .style('display', function () {
        if (name === 'plot') {
          return 'none'
        }
      })
    d3.select('#hc' + name.charAt(0).toUpperCase() + name.slice(1) + 'Div')
      .property('title', 'Click to show ' + labels[name] + ' window')
  } else {
    // show
    d3.select('#' + name + 'Div')
      .transition()
      .duration(250)
      .ease(d3.easeCubic)
      .style('opacity', '1')
      .style('display', 'block')
      .style('visibility', 'visible')
      .on('end', resizePanels)
    d3.select('#hc' + name.charAt(0).toUpperCase() + name.slice(1) + 'Div')
      .property('title', 'Click to hide ' + labels[name] + ' window')
    setZ(d3.select('#' + name + 'Div')._groups[0][0])
  }
}

function setMappedAttribute (attribute, colorScale) {
  console.log('setMappedAttribute()', attribute, colorScale)
  d3.selectAll('.activeTopo')
    .style('fill', d => {
      return attribute === 'None' ? 'none' : colorScale(d.properties[attribute] / topos.xf.ranges[attribute].max)
    })
    .style('stroke', () => {
      return attribute !== 'None' ? '#333333' : ''
    })
    .property('data-tt', d => {
      return parseFloat(d.properties[attribute]).toFixed(3)
    })

  // set legend labels
  const range = topos.xf.ranges[attribute]
  d3.select('#csMin').text(range.min.toFixed(1))
  d3.select('#csMid').text((((range.max - range.min) / 2) + range.min).toFixed(1))
  d3.select('#csMax').text(range.max.toFixed(1))
}

function projectPoint (x, y) {
  const point = map.latLngToLayerPoint(new L.LatLng(y, x))
  this.stream.point(point.x, point.y)
}

function addTopo (topo) {
  $(function () {
    $('[data-toggle="tooltip"]').tooltip()
  })

  const tmpFeats = d3.select(topo.g).selectAll('.' + topo.class)
    .data(topo.topo.features, function (d) { return d.id })

  tmpFeats.enter()
    .append('path')
    .attr('d', path)
    .attr('class', function (d) {
      if (topo.class !== 'geoIndicators') {
        return topo.class + ' activeTopo'
      } else {
        return topo.class + ' activeTopo_geoInd'
      }
    })
    .property('data-attr', function (d) { return d.properties[topo.id] })
    .property('data-tt', function (d) { return d.properties[topo.id] })
    .attr('data-toggle', function () { if (topo.class === 'geoIndicators') { return 'tooltip' } })
    .attr('data-container', 'body')
    .attr('data-placement', 'auto')
    .attr('data-html', 'true')
    .attr('title', function (d) { return d.properties[topo.id] })
    .style('stroke-width', 1 + ((map.getZoom() - 9) / 100))
    .on('mouseenter', function () { d3.select(this).classed('svgHover', true); if (topo.class !== 'geoIndicators') { if (d3.select(this).style('visibility') === 'visible') { showIt(d3.select(this).property('data-tt')); resizeTooltip() } } })
    .on('mousemove', function () { if (topo.class !== 'geoIndicators') { tooltip.style('top', (d3.event.pageY - 50) + 'px').style('left', (d3.event.pageX) + 'px'); resizeTooltip() } })
    .on('mouseleave', function () { d3.select(this).classed('svgHover', false); tooltip.style('visibility', 'hidden') })
    .call(d3.drag()) //* **Prevents default for click event when the map is being dragged
    .on('click', function (d) {
      if (d3.select(this).style('visibility') === 'visible') {
        // const tmpPath = this
        d3.selectAll('.svgSelected').classed('svgSelected', false)
        d3.select(this).classed('svgSelected', true)

        d3.select('#plotDiv')
          .attr('data-props', JSON.stringify(d.properties))

        makePlot(d.properties)
        if (d3.select('#plotDiv').style('opacity') === 0) {
          toggleWindow('plot')
        }
      }
    })
    .on('touchstart', function () { d3.select(this).classed('svgHover', true) })
    .on('touchend', function () { d3.select(this).classed('svgHover', false); if (d3.select(this).classed('geoIndicators') === false) { if (d3.select(this).classed('svgSelected') === true) { d3.select(this).classed('svgSelected', false) } else { d3.select(this).classed('svgSelected', true) } } })

  tmpFeats.exit().remove()
}

function makePlot (props) {
  console.log('makePlot', props)

  const Y = {}
  const X = {}

  Y.var = d3.select('#plotY').property('value')
  X.var = d3.select('#plotX').property('value')

  console.log('vars:', X.var, Y.var)

  Y.min = topos.xf.ranges[Y.var].min
  Y.max = topos.xf.ranges[Y.var].max
  Y.range = Y.max - Y.min
  Y.step = Y.range / 100

  X.min = topos.xf.ranges[X.var].min
  X.max = topos.xf.ranges[X.var].max
  X.range = X.max - X.min
  X.step = X.range / 100

  d3.select('#plotSliderTitleY').text(Y.var)
  d3.select('#plotSliderTitleX').text(X.var)

  d3.select('#plotSliderY').property('title', props[Y.var])
  d3.select('#plotSliderX').property('title', props[X.var])

  d3.select('#plotRefreshY').on('click', function () { $('#plotSliderY').slider('value', props[Y.var]); updateY(props, props[Y.var]) })
  d3.select('#plotRefreshX').on('click', function () { $('#plotSliderX').slider('value', props[X.var]); updateX(props, props[X.var]) })

  $('#plotSliderY').slider({ animate: 'fast', min: Y.min, max: Y.max, value: props[Y.var], slide: function (event, ui) { updateY(props, ui.value) } })
  $('#plotSliderX').slider({ animate: 'fast', min: X.min, max: X.max, value: props[X.var], slide: function (event, ui) { updateX(props, ui.value) } })

  function updateY (props, tmpVal) {
    const propsCopy = JSON.parse(JSON.stringify(props))
    propsCopy[Y.var] = tmpVal
    propsCopy[X.var] = $('#plotSliderX').slider('value')
    const tmpOcc = calcOcc(propsCopy)
    data[1].y[0] = tmpVal
    data[1].z[0] = tmpOcc
    Plotly.redraw('surfaceDiv')
    d3.select('#plotSliderY').property('title', tmpVal)
    if (!isNaN(props.occ_current)) {
      d3.select('#predOcc').text(tmpOcc.toFixed(3))
    }
  }

  function updateX (props, tmpVal) {
    const propsCopy = JSON.parse(JSON.stringify(props))
    propsCopy[X.var] = tmpVal
    propsCopy[Y.var] = $('#plotSliderY').slider('value')
    const tmpOcc = calcOcc(propsCopy)
    data[1].x[0] = tmpVal
    data[1].z[0] = tmpOcc
    Plotly.redraw('surfaceDiv')
    d3.select('#plotSliderX').property('title', tmpVal)
    if (!isNaN(props.occ_current)) {
      d3.select('#predOcc').text(tmpOcc.toFixed(3))
    }
  }

  d3.select('#predOcc').text(props.occ_current.toFixed(3))

  const propsCopy = JSON.parse(JSON.stringify(props))

  const cs = [['0.0', 'rgb(68, 2, 86)'], ['0.25', 'rgb(59, 82, 139)'], ['0.5', 'rgb(33, 145, 140)'], ['0.75', 'rgb(42, 176, 127)'], ['1.0', 'rgb(253, 231, 37)']]

  const data = [
    {
      x: [],
      y: [],
      z: [],
      type: 'contour',
      colorscale: cs
    }, {
      x: [props[X.var]],
      y: [props[Y.var]],
      z: [props.occ_current],
      mode: 'markers',
      type: 'scatter',
      marker: {
        size: 8,
        color: 'rgb(255, 77, 255)',
        line: {
          width: 1,
          color: 'black'
        }
      }
    }
  ]
  let a = -1

  for (let j = Y.min; j <= Y.max + (Y.max * 0.001); j += Y.step) {
    data[0].y.push(j)
    propsCopy[Y.var] = j
    data[0].z.push([])
    a += 1
    for (let i = X.min; i <= X.max + (X.max * 0.001); i += X.step) {
      if (j === Y.min) { data[0].x.push(i) }
      propsCopy[X.var] = i
      const tmpOcc = calcOcc(propsCopy)
      if (!isNaN(props.mean_jul_temp)) {
        data[0].z[a].push(tmpOcc)
      }
    }
  }

  const layout = {
    title: 'Brook trout occupancy for<br>catchment <span id="selCatchID">' + props.FEATUREID + '</span>',
    width: 400,
    height: 400,
    xaxis: {
      title: X.var
    },
    yaxis: {
      title: Y.var
    },
    hovermode: 'closest'
  }

  Plotly.newPlot('surfaceDiv', data, layout)

  //* **Add catchment properties as hover
  if (document.getElementById('catchInfo') == null) {
    d3.select('#surfaceDiv').select('.svg-container')
      .append('span')
      .attr('id', 'catchInfo')
      .attr('class', 'fa fa-info-circle')
  }
  d3.select('#catchInfo')
    .on('click', function () { console.log(props) })
    .on('mouseenter', function () { d3.select('#catchInfoVals').style('visibility', 'visible').style('top', (d3.event.pageY + 10) + 'px').style('left', (d3.event.pageX - 195) + 'px') })
    .on('mouseleave', function () { d3.select('#catchInfoVals').style('visibility', 'hidden') })

  d3.select('#catchInfoVals')
    .text(function () {
      let tmpText = ''
      for (const key in props) {
        tmpText += key + ':   ' + props[key] + '\n'
      }
      return tmpText
    })
}

function calcOcc (x) {
  const params = topos.model.params
  const std = params.std
  const fixed = params.fixed

  // const sumFixed = (topos.model.summary_glmm.Intercept.Estimate) +
  //   (topos.model.summary_glmm.AreaSqKM.Estimate * ((x.AreaSqKM - topos.model.z_group.AreaSqKM.mean) / topos.model.z_group.AreaSqKM.sd)) +
  //   (topos.model.summary_glmm.summer_prcp_mm.Estimate * ((x.summer_prcp_mm - topos.model.z_group.summer_prcp_mm.mean) / topos.model.z_group.summer_prcp_mm.sd)) +
  //   (topos.model.summary_glmm.mean_jul_temp.Estimate * ((x.mean_jul_temp - topos.model.z_group.mean_jul_temp.mean) / topos.model.z_group.mean_jul_temp.sd)) +
  //   (topos.model.summary_glmm.forest.Estimate * ((x.forest - topos.model.z_group.forest.mean) / topos.model.z_group.forest.sd)) +
  //   (topos.model.summary_glmm.allonnet.Estimate * ((x.allonnet - topos.model.z_group.allonnet.mean) / topos.model.z_group.allonnet.sd)) +
  //   (topos.model.summary_glmm.devel_hi.Estimate * ((x.devel_hi - topos.model.z_group.devel_hi.mean) / topos.model.z_group.devel_hi.sd)) +
  //   (topos.model.summary_glmm.agriculture.Estimate * ((x.agriculture - topos.model.z_group.agriculture.mean) / topos.model.z_group.agriculture.sd)) +
  //   (topos.model.summary_glmm['AreaSqKM:summer_prcp_mm'].Estimate * ((x.AreaSqKM - topos.model.z_group.AreaSqKM.mean) / topos.model.z_group.AreaSqKM.sd) * ((x.summer_prcp_mm - topos.model.z_group.summer_prcp_mm.mean) / topos.model.z_group.summer_prcp_mm.sd)) +
  //   (topos.model.summary_glmm['mean_jul_temp:forest'].Estimate * ((x.mean_jul_temp - topos.model.z_group.mean_jul_temp.mean) / topos.model.z_group.mean_jul_temp.sd) * ((x.forest - topos.model.z_group.forest.mean) / topos.model.z_group.forest.sd)) +
  //   (topos.model.summary_glmm['summer_prcp_mm:forest'].Estimate * ((x.summer_prcp_mm - topos.model.z_group.summer_prcp_mm.mean) / topos.model.z_group.summer_prcp_mm.sd) * ((x.forest - topos.model.z_group.forest.mean) / topos.model.z_group.forest.sd))

  // if (typeof topos.model.ranef_glmm[x.huc10.toString()] !== 'undefined') {
  //   sumRandom = (topos.model.ranef_glmm[x.huc10.toString()].Intercept) +
  //     (topos.model.ranef_glmm[x.huc10.toString()].AreaSqKM * ((x.AreaSqKM - topos.model.z_group.AreaSqKM.mean) / topos.model.z_group.AreaSqKM.sd)) +
  //     (topos.model.ranef_glmm[x.huc10.toString()].agriculture * ((x.agriculture - topos.model.z_group.agriculture.mean) / topos.model.z_group.agriculture.sd)) +
  //     (topos.model.ranef_glmm[x.huc10.toString()].summer_prcp_mm * ((x.summer_prcp_mm - topos.model.z_group.summer_prcp_mm.mean) / topos.model.z_group.summer_prcp_mm.sd)) +
  //     (topos.model.ranef_glmm[x.huc10.toString()].mean_jul_temp * ((x.mean_jul_temp - topos.model.z_group.mean_jul_temp.mean) / topos.model.z_group.mean_jul_temp.sd))
  // }
  const sumFixed = fixed.intercept + fixed.mean_jul_temp * (x.mean_jul_temp - std.mean_jul_temp.mean) / std.mean_jul_temp.sd

  let sumRandom = 0
  const huc8 = x.huc10.substr(0, 8)
  if (topos.model.params.randomMap.has(huc8)) {
    sumRandom = topos.model.params.randomMap.get(huc8).intercept
  }

  const y = sumFixed + sumRandom
  const prob = Math.exp(y) / (1 + Math.exp(y))
  return prob
}

function reset () {
  d3.select('#map').style('cursor', '')

  // set bounds
  // NOTE: These will need to change if outside points are added and if so the max zoom might need to be lowered
  let tmpPoint = map.latLngToLayerPoint(new L.LatLng(17, -170))
  const bottomLeft = [tmpPoint.x, tmpPoint.y]
  tmpPoint = map.latLngToLayerPoint(new L.LatLng(72, -64))
  const topRight = [tmpPoint.x, tmpPoint.y]

  topoSVG.attr('width', topRight[0] - bottomLeft[0])
    .attr('height', bottomLeft[1] - topRight[1])
    .style('margin-left', bottomLeft[0] + 'px')
    .style('margin-top', topRight[1] + 'px')

  // select all layer g elements
  const tmpG = topoSVG.selectAll('g')

  // loop through each g element and transform the path
  tmpG._groups[0].forEach(function (g) {
    const curG = d3.select(g)
    const feature = curG.selectAll('path')
    curG.attr('transform', 'translate(' + -bottomLeft[0] + ',' + -topRight[1] + ')')
    feature.attr('d', path).style('stroke-width', function () { return 1 + ((map.getZoom() - 9) / 10) })
  })
}

function removeTopo (topo) {
  d3.select(topo.g).selectAll('.' + topo.class).remove()
}

function showIt (tmpID) {
  tooltip.text(tmpID)
  tooltip.style('visibility', 'visible')
  tooltip.property('title', tmpID)
}

function resizeTooltip () {
  const mapRect = document.getElementById('map').getBoundingClientRect()
  const tmpWindows = ['d3Tooltip']

  tmpWindows.forEach(function (win) {
    const winRect = document.getElementById(win).getBoundingClientRect()
    if (winRect.bottom > mapRect.bottom) {
      d3.select('#' + win).style('top', mapRect.height - winRect.height + 'px')
    }
    if (winRect.right > mapRect.right) {
      d3.select('#' + win).style('left', mapRect.width - winRect.width + 'px')
    }
  })
}

function resizePanels () {
  const bodyRect = document.body.getBoundingClientRect()
  const tmpWindows = ['infoDiv', 'pointDiv', 'locateDiv', 'legendDiv', 'filterDiv', 'downloadDiv', 'plotDiv', 'mapDiv']

  tmpWindows.forEach(function (win) {
    const winRect = document.getElementById(win).getBoundingClientRect()
    if (winRect.bottom > bodyRect.bottom) {
      d3.select('#' + win).style('top', bodyRect.height - winRect.height + 'px')
    }
    if (winRect.right > bodyRect.right) {
      d3.select('#' + win).style('left', bodyRect.width - winRect.width + 'px')
    }
  })
  d3.select('#legendImgDiv').style('min-width', '0px').style('width', 'auto')
  const legRect = document.getElementById('legendImgDiv').getBoundingClientRect()
  d3.select('#legendImgDiv').style('min-width', legRect.width + 'px')
}

function spatialFilter (tmpLayer) {
  //* **Filter using crossfilter
  // var tmpLayer = d3.select("#spatialFilterSelect").attr("data-layer");
  if (tmpLayer != null) {
    const tmpID = topos.geoIndicators.cf.filters[tmpLayer]
    // d3.selectAll(".svgSelected").each(function(d) { tmpID.push(d.id); });

    topos.geoIndicators.cf[tmpLayer].filterAll() //* **Remove spatial filters for layer
    let tmpGeo
    let geoIDs
    if (tmpID.length > 0) {
      topos.geoIndicators.cf[tmpLayer].filterFunction(function (d) { return tmpID.indexOf(d) > -1 })

      tmpGeo = topos.geoIndicators.cf[tmpLayer].bottom(Infinity)
      geoIDs = tmpGeo.map(function (d) { return d.geoIndicators })
      d3.selectAll('.geoIndicators')
        .style('display', function (d) {
          if (geoIDs.indexOf(d.id) > -1) {
            return 'block'
          } else {
            return 'none'
          }
        })
    } else {
      tmpGeo = topos.geoIndicators.cf[tmpLayer].bottom(Infinity)
      geoIDs = tmpGeo.map(function (d) { return d.geoIndicators })
      d3.selectAll('.geoIndicators')
        .style('display', function (d) {
          if (geoIDs.indexOf(d.id) > -1) {
            return 'block'
          } else {
            return 'none'
          }
        })
    }
    d3.select('#filterCnt').text(topos.geoIndicators.cf.geoIndicators.top(Infinity).length)
  }
}
