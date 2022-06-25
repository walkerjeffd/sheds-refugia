/* eslint-disable dot-notation */

function computeTemp (featureid, userAdjust) {
  const model = require(`./${featureid}.json`)

  const defaultAdjust = {
    airTemp: 0,
    prcp: 1,
    forest: model.val.forest,
    agriculture: model.val.agriculture,
    devel_hi: model.val.devel_hi
  }

  const adjust = {
    ...defaultAdjust,
    ...userAdjust
  }

  // adjust and standardize
  const inp = {
    airTemp: ((model.val.airTemp + adjust.airTemp) - model.std.airTemp.mean) / model.std.airTemp.sd,
    temp7p: ((model.val.temp7p + adjust.airTemp) - model.std.temp7p.mean) / model.std.temp7p.sd,
    prcp2: ((model.val.prcp2 * adjust.prcp) - model.std.prcp2.mean) / model.std.prcp2.sd,
    prcp30: ((model.val.prcp30 * adjust.prcp) - model.std.prcp30.mean) / model.std.prcp30.sd,
    forest: (adjust.forest - model.std.forest.mean) / model.std.forest.sd,
    agriculture: (adjust.agriculture - model.std.agriculture.mean) / model.std.agriculture.sd,
    devel_hi: (adjust.devel_hi - model.std.devel_hi.mean) / model.std.devel_hi.sd,
    impoundArea: (model.val.impoundArea - model.std.impoundArea.mean) / model.std.impoundArea.sd,
    AreaSqKM: (model.val.AreaSqKM - model.std.AreaSqKM.mean) / model.std.AreaSqKM.sd
  }

  inp['prcp2.da'] = inp.prcp2 * inp.AreaSqKM
  inp['prcp30.da'] = inp.prcp30 * inp.AreaSqKM
  inp['airTemp.prcp2'] = inp.airTemp * inp.prcp2 + model.cov['airTemp.prcp2'] * adjust.prcp
  inp['airTemp.prcp2.da'] = (inp.airTemp * inp.prcp2 + model.cov['airTemp.prcp2'] * adjust.prcp) * inp.AreaSqKM
  inp['airTemp.prcp30'] = inp.airTemp * inp.prcp30 + model.cov['airTemp.prcp30'] * adjust.prcp
  inp['airTemp.prcp30.da'] = (inp.airTemp * inp.prcp30 + model.cov['airTemp.prcp30'] * adjust.prcp) * inp.AreaSqKM
  inp['airTemp.forest'] = inp.airTemp * inp.forest
  inp['airTemp.devel_hi'] = inp.airTemp * inp.devel_hi
  inp['airTemp.da'] = inp.airTemp * inp.AreaSqKM
  inp['airTemp.impoundArea'] = inp.airTemp * inp.impoundArea
  inp['airTemp.agriculture'] = inp.airTemp * inp.agriculture
  inp['intercept'] = 1

  const values = Object.keys(inp).map(x => {
    return inp[x] * model.coef[x]
  })

  const temp = values.reduce((p, v) => p + v, 0)

  return temp
}

console.log(computeTemp(201411588, { airTemp: 0 }))
console.log(computeTemp(201411588, { airTemp: 2 }))
console.log(computeTemp(201411588, { airTemp: 4 }))
console.log(computeTemp(201411588, { airTemp: 6 }))

process.exit(0)

