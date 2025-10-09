module.exports = {
  root: true,
  env: {
    es2021: true,
    node: true,
  },
  extends: ["google"],
  parserOptions: {
    ecmaVersion: 12,
  },
  rules: {
    "quotes": ["error", "double"],
    "max-len": [
      "error",
      { "code": 100, "ignoreUrls": true, "ignoreComments": true }
    ],
    "object-curly-spacing": ["error", "always"],
  },
};
