const { resolve } = require("path");

module.exports = {
  entry: "./src/index.ts",
  mode: "production",
  target: "node20",
  output: {
    filename: "bundle.js",
    path: resolve(__dirname, "dist"),
  },
  resolve: {
    extensions: [".ts", ".js"],
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: "ts-loader",
        exclude: /node_modules/,
      },
    ],
  },
  optimization: {
    minimize: false,
  },
  externals: {
    ws: "commonjs ws",
    "nostr-tools/pool": "commonjs nostr-tools/pool",
  },
};
