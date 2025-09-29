module.exports = function (api) {
  api.cache(true);

  const presets = [
    ['@babel/preset-env', { targets: { node: 'current' } }],
    ['@babel/preset-react', { runtime: 'automatic' }],
    '@babel/preset-typescript'
  ];

  const plugins = [];

  // Add Istanbul instrumentation for coverage in test environment
  if (process.env.NODE_ENV === 'test' || process.env.CYPRESS_COVERAGE === 'true') {
    plugins.push('babel-plugin-istanbul');
  }

  return {
    presets,
    plugins
  };
};
