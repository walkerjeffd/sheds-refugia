var express = require('express');
var app = express();
var compression = require('compression');

app.use(compression());

app.use(express.static('/home/jason/refugia'));

app.listen(3420);

console.log("Running on 3420...");
