import { readFileSync } from "node:fs";

const grammar = JSON.parse(
  readFileSync(new URL("./oxl.tmLanguage.json", import.meta.url), "utf8"),
);
const modGrammar = JSON.parse(
  readFileSync(new URL("./oxl-mod.tmLanguage.json", import.meta.url), "utf8"),
);

// Shiki lang ids are lowercase; the grammar's own `name` is "OXL".
export default { ...grammar, name: "oxl", embeddedLangs: [] };

// oxl.mod / oxl.work are a directive DSL, not oxl syntax — separate lang.
export const oxlModGrammar = {
  ...modGrammar,
  name: "oxlmod",
  aliases: ["oxl.mod", "oxl.work"],
  embeddedLangs: [],
};
