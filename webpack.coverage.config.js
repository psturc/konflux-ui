import { merge } from 'webpack-merge';
import prodConfig from './webpack.prod.config.js';

// Set environment for Babel to enable instrumentation
process.env.NODE_ENV = 'test';
process.env.CYPRESS_COVERAGE = 'true';

export default merge(prodConfig, {
  // Keep production mode for optimizations
  mode: 'production',
  // Use source maps for better coverage mapping (keep production source-map)
  devtool: 'source-map',
  module: {
    rules: [
      {
        test: /\.[jt]sx?$/i,
        exclude: /(node_modules)/,
        use: [
          {
            loader: 'babel-loader',
            options: {
              // Force Babel to read .babelrc.cjs which includes Istanbul instrumentation
              configFile: './.babelrc.cjs',
              cacheDirectory: false, // Disable cache to ensure instrumentation is applied
            },
          },
        ],
      },
    ],
  },
});
