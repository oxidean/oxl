import { readFileSync } from "node:fs";

const grammar = JSON.parse(
  readFileSync(new URL("./oxl.tmLanguage.json", import.meta.url), "utf8"),
);

// Shiki lang ids are lowercase; the grammar's own `name` is "OXL".
export default { ...grammar, name: "oxl", embeddedLangs: [] };
