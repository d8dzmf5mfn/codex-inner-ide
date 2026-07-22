import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const [sourceDirectory, destinationDirectory] = process.argv.slice(2);
if (!sourceDirectory || !destinationDirectory) {
  throw new Error("usage: stage-renderer.mjs <dist-directory> <renderer-directory>");
}

const names = ["ide.js", "ide.css"];
await mkdir(destinationDirectory, { recursive: true });
const manifest = {};
for (const name of names) {
  const source = path.resolve(sourceDirectory, name);
  const destination = path.resolve(destinationDirectory, name);
  const data = await readFile(source);
  manifest[name] = createHash("sha256").update(data).digest("hex");
  await copyFile(source, destination);
}
await writeFile(
  path.resolve(destinationDirectory, "manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
  "utf8"
);
