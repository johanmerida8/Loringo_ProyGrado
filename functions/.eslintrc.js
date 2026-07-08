module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
    "/generated/**/*", // Ignore generated files.
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    "indent": ["error", 2],
    "max-len": ["error", { "code": 120 }], // Permite líneas de hasta 120 caracteres
    "object-curly-spacing": ["error", "always"], // Espacios dentro de objetos {}
    "linebreak-style": ["error", "windows"], // Para Windows (o "unix" si usas Linux/Mac)
    "eol-last": ["error", "always"], // Obliga salto de línea al final
    "@typescript-eslint/no-non-null-assertion": "off", // Desactiva la regla de non-null assertion
  },
};
