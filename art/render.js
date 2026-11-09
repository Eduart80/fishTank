// Renders an SVG in art/ to a PNG of the given size with headless Edge (no extra packages).
// Usage: node art/render.js icon.svg 512 512
//        node art/render.js thumbnail.svg 1920 1080
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const [file = "icon.svg", width = "512", height = "512"] = process.argv.slice(2);
const svg = path.join(__dirname, file);
const out = svg.replace(/\.svg$/, ".png");
const html = path.join(__dirname, ".render.html");
fs.writeFileSync(
	html,
	`<!doctype html><html><body style="margin:0;overflow:hidden">${fs.readFileSync(svg, "utf8")}</body></html>`
);

const edge = "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe";
execFileSync(edge, [
	"--headless=new",
	"--disable-gpu",
	"--hide-scrollbars",
	"--force-device-scale-factor=1",
	`--window-size=${width},${height}`,
	`--screenshot=${out}`,
	"file:///" + html.replace(/\\/g, "/"),
], { stdio: "ignore" });
fs.unlinkSync(html);
console.log("wrote", out);
