"use strict";

const express = require('express');
const app = express();
const mysql = require('mysql');

const HOST = "0.0.0.0";
const PORT = "8080";

const connection = mysql.createConnection({
    host: process.env.DB_HOST,
    user: process.env.DB_USERNAME,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
});

connection.connect((err) => {
    if (err) throw err;
    console.log("Connected to MySQL Server!");
});

app.get("/", (req, result) => {
    connection.query("SELECT * from data LIMIT 1", (err, rows) => {
        if (err) throw err;
        result.send(rows[0]["value"]);
    });
});

app.listen(PORT, HOST);
console.log("Running on http://${HOST}:${PORT}");