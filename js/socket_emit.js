function socket_emit() {
  var socket = io();
  
  socket.on('connect', function () {
    console.log('connected!');
  });

  socket.on("test", function(tmpData) {
    console.log(tmpData);
  });

  var secureCheck = "no_code";
  socket.on("login", function(tmpData) {
    secureCheck = tmpData.check;
    switch (tmpData.code) {
      case 200:
        var tmpSpan = d3.select("#secureDiv").select("span");
        d3.select("#loginErr").text("").style("display", "");
        $('#loginModal').modal('hide')
        socket.emit("secure", {"match":"true", "data_filter": tmpData.data_filter});
        if(tmpSpan.classed("fa-lock") == true) {
          tmpSpan.classed("fa-lock", false);
          tmpSpan.classed("fa-unlock", true);
          tmpSpan.property("title", "Click to log out");
        }
        break;
      case 401:
        if(d3.select("#loginModal").style("display") == "block") {
          d3.select("#loginErr").text("Incorrect password").style("display", "block");
        }
        socket.emit("secure", "false");
        break;
      case 404:
        if(d3.select("#loginModal").style("display") == "block") {
          d3.select("#loginErr").text("User does not exist").style("display", "block");
        }
        socket.emit("secure", "false");
        break;
      default:
        if(d3.select("#loginModal").style("display") == "block") {
          d3.select("#loginErr").text("Error encountered").style("display", "block");
        }
        socket.emit("secure", "false");
        break;
    }
  });

  var secureStat = "bad";
  socket.on("secure", function(tmpData) {
    secureStat = tmpData.status;
    getGeoInd({"data_filter": tmpData.data_filter});
  });

  socket.on("getGeoInd", function(tmpData) {
    if(typeof tmpData.error == "undefined") {
      topos.geoIndicators.topo = tmpData;
      topos.geoIndicators.unfiltered = JSON.parse(JSON.stringify(tmpData)); //***Makes a deep copy
      topos.geoIndicators.unfiltered.id = topos.geoIndicators.unfiltered.features.map(function(d) { return d.id; });
      getGeoInd_sj();
      if(map.getZoom() >= map.zoomToggle) { getGeoIndID_d3(); } //Updates d3 layer through client if zoomed in on map
      //if(map.getZoom() >= map.zoomToggle) { getGeoIndID({bounds: map.getBounds()}); } //Updates d3 layer through server if zoomed in on map DEPRECATED
    }
    else {
      alert("Error encountered acquiring geoIndicator data from postgreSQL.\n\n" + tmpData.error.hint);
    }
  });

  socket.on("getGeoIndID", function(tmpData) {
      var tmpArray = tmpData.map(function(d) { return d.ogc_fid; });
      topos.geoIndicators.topo.features = [];
      topos.geoIndicators.unfiltered.features.forEach(function(d) { if(tmpArray.indexOf(d.id) > -1) { topos.geoIndicators.topo.features.push(d); } });
      addTopo(topos.geoIndicators);
  });

  socket.on("getGeoInd_sj", function(tmpData) {
    var tmpCF = crossfilter(tmpData);
    topos.geoIndicators.cf = {};
    topos.geoIndicators.cf.filters = { "type": {} };
    topos.geoIndicators.cf.cf = tmpCF;
    topos.geoIndicators.cf.all = tmpCF.groupAll();
    var tmpKeys = d3.keys(tmpData[0]);
    topos.geoIndicators.cf.keys = tmpKeys;
    tmpKeys.forEach(function(key) {
      topos.geoIndicators.cf[key] = tmpCF.dimension(function(d) { return d[key]; });
      topos.geoIndicators.cf[key + "s"] = topos.geoIndicators.cf[key].group();  //***Probably not necessary to make groups since we're not graphing
      topos.geoIndicators.cf.filters[key] = [];
      topos.geoIndicators.cf.filters.type[key] = "spatial";
    });
    cfFilter();
    setCatFilter(tmpKeys);
  });

  socket.on("getDownload", function(tmpData) {
    d3.select("#downloadGif").classed("disabled", true);
    for(i in tmpData) {
      switch(tmpData[i].table.slice(0,3)) {
        case "geo":
          if(d3.select("#downloadSelect").property("value") == "CSV") {
            outputCSV(tmpData[i].rows, tmpData[i].table);
          }
          else {  //***geoJSON
            outputGeoJSON(tmpData[i].rows, tmpData[i].table);
          }          
          break;
        case "dat":
            outputCSV(tmpData[i].rows, tmpData[i].table);          
          break;
       }
    }
    resizePanels();
  });

  socket.on("getLayers", function(tmpData) {
    tmpData.layers.forEach(function(layer) {
      if(typeof tmpData[layer] != "undefined") {
        topos[layer].topo = topojson.feature(tmpData[layer], tmpData[layer].objects.temp);
        addTopo(topos[layer]);
      }
    });
  });

  socket.on("getGeoSpe", function(tmpData) {
    //***Point data is returned as a geoJSON, not a topoJSON
    topos["geoSpe"].topo = tmpData;
    addTopo(topos["geoSpe"]);
  });




  tryLogin = function(tmpData) {
    socket.emit("login", tmpData);
  }

  getGeoInd = function(tmpData) {
    socket.emit("getGeoInd", {"check": secureCheck, "status": secureStat, "data_filter": tmpData.data_filter});
  }

  getGeoIndID = function(tmpData) {
    console.log("get ID")
    socket.emit("getGeoIndID", tmpData);
  }

  getGeoInd_sj = function() {
    if(typeof(topos.geoIndicators.cf) != "object") {
      socket.emit("getGeoInd_sj");
    }
    else {
      cfFilter();
    }
  }

  downloadData = function() {
    d3.selectAll(".linkDiv").remove();
    d3.select("#downloadGif").classed("disabled", false);
    resizePanels();

    var tmpID = topos.geoIndicators.cf.geoIndicators.bottom(Infinity);
    var mapID = tmpID.map(function(d) { return d.geoIndicators; });
    var pkArr = [];
    topos.geoIndicators.unfiltered.features.forEach(function(d) {
      if(mapID.indexOf(d.id) > -1) {
        pkArr.push("'" + d.properties.PrimaryKey + "'");
      }
    });
    var tmpData = {"format": d3.select("#downloadSelect").property("value"), "ids": pkArr, "tables": {"indicators": d3.select("#chkIndicators").property("checked"), "species": d3.select("#chkSpecies").property("checked"), "raw": d3.select("#chkRaw").property("checked")}};
    socket.emit("getDownload", tmpData);
  }

  cfFilter = function() {
    topos.geoIndicators.cf.geoIndicators.filterFunction(function(d) { return topos.geoIndicators.unfiltered.id.indexOf(d) > -1; });  //***Filter by geoInd points available to user
    d3.selectAll("#totalCnt").text(topos.geoIndicators.unfiltered.id.length);
    d3.selectAll("#filterCnt").text(topos.geoIndicators.cf.geoIndicators.top(Infinity).length);
  }


  //******Function to output both spatial and regular data as CSV
  function outputCSV(tmpData, tmpTable) {
    var tmpKeys = d3.keys(tmpData[0]);
    tmpKeys.splice(tmpKeys.indexOf("wkb_geometry"), 1);
    tmpKeys.splice(tmpKeys.indexOf("coords"), 1);

    if(tmpTable.slice(0,3) == "geo") {
      var tmpStr = tmpKeys.join() + ",Longitude,Latitude" + String.fromCharCode(13);
      tmpData.forEach(function(row) {
        tmpKeys.forEach(function(key) {
          tmpStr += row[key] + ",";
        });
        row.coords = JSON.parse(row.coords);
        if(row.coords != null) {
          tmpStr += row.coords.coordinates[0] + "," + row.coords.coordinates[1] + String.fromCharCode(13);
        }
        else {
          tmpStr += null + "," + null + "," + String.fromCharCode(13);
        }
      });
    }
    else {    //***raw data table
      var tmpStr = tmpKeys.join();
      tmpData.forEach(function(row) {
        tmpKeys.forEach(function(key) {
          tmpStr += row[key] + ",";
        });
        tmpStr += String.fromCharCode(13);
      });      
    }
    var blob = new Blob([tmpStr], {type: "text/plain"});
    var url = URL.createObjectURL(blob);

    d3.select("#downloadLinks")
      .append("div")
      .attr("class", "linkDiv")
      .attr("id", tmpTable + "LinkDiv")
      .html('<p>' + tmpTable + '</p><a id="' + tmpTable + 'Link" title="Click to save file"><span class="fa fa-download downloadLink"></span></a>');
    
    var a = d3.select("#" + tmpTable + "Link");
    a.property("download",  tmpTable + ".csv");
    a.property("href", url);
  }


  //******Function to output spatial data as geoJSON
  function outputGeoJSON(tmpData, tmpTable) {
    var tmpJSON = {"type": "FeatureCollection", "features": []}
    var tmpKeys = d3.keys(tmpData[0]);
    tmpKeys.splice(tmpKeys.indexOf("wkb_geometry"), 1);
    tmpKeys.splice(tmpKeys.indexOf("coords"), 1);

    tmpData.forEach(function(row) {
      var tmpProps = {};
      tmpKeys.forEach(function(key) {
        tmpProps[key] = row[key];
      });

      tmpJSON.features.push({"type": "Feature", "id": row.Primarykey, "properties": tmpProps, "geometry": JSON.parse(row.coords)});
    });
    var tmpStr = JSON.stringify(tmpJSON);

    var blob = new Blob([tmpStr], {type: "text/plain"});
    var url = URL.createObjectURL(blob);

    d3.select("#downloadLinks")
      .append("div")
      .attr("class", "linkDiv")
      .attr("id", tmpTable + "LinkDiv")
      .html('<p>' + tmpTable + '</p><a id="' + tmpTable + 'Link" title="Click to save file"><span class="fa fa-download downloadLink"></span></a>');
    
    var a = d3.select("#" + tmpTable + "Link");
    a.property("download",  tmpTable + ".json");
    a.property("href", url);

  }
}